// Điều phối: quyền Trợ năng, phát hiện Mos, bật/tắt bộ cuộn + nút
import AppKit
import ApplicationServices
import ServiceManagement
import Combine
import IOKit.hid

final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let mosID = "com.caldis.Mos"

    @Published var trusted = AXIsProcessTrusted()
    @Published var mosRunning = false
    @Published var toast: String?

    let hid = MouseHID.shared
    let settings = Settings.shared
    private var bag = Set<AnyCancellable>()
    private var poll: Timer?
    private var toastWork: DispatchWorkItem?

    func start() {
        hid.start()
        if !settings.firstLaunchDone {
            settings.firstLaunchDone = true
            if MosImport.available { _ = MosImport.run() }
        }
        settings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.syncEngines() }
        }.store(in: &bag)
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.check() }
        // Máy ngủ dậy → dựng lại bộ bắt cuộn + nút (03/11 anh báo chuột không cuộn được sau khi máy ngủ dậy)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.restartEngines(reason: "máy ngủ dậy") }
        }
        check()
    }

    func check() {
        hid.retryIfNeeded()
        let t = AXIsProcessTrusted()
        if t != trusted { trusted = t }
        let m = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.mosID).isEmpty
        if m != mosRunning { mosRunning = m }
        syncEngines()
    }

    /// Dựng lại bộ bắt khi macOS tắt nó (sau khi ngủ dậy, app bị treo lâu…)
    func restartEngines(reason: String) {
        ScrollEngine.shared.stop(); ButtonEngine.shared.stop()
        syncEngines()
        NSLog("DuckMouse: dựng lại bộ bắt cuộn/nút – \(reason)")
    }

    /// Mos đang chạy thì không bật cuộn/nút (tránh cuộn mượt 2 lần, nút chạy 2 lần)
    func syncEngines() {
        if !ScrollEngine.shared.healthy || !ButtonEngine.shared.healthy {
            ScrollEngine.shared.stop(); ButtonEngine.shared.stop()
            NSLog("DuckMouse: bộ bắt bị tắt → bật lại")
        }
        let canRun = trusted && !mosRunning
        if canRun && settings.scrollEnabled { ScrollEngine.shared.start() } else { ScrollEngine.shared.stop() }
        if canRun && settings.buttonsEnabled { ButtonEngine.shared.start() } else { ButtonEngine.shared.stop() }
    }

    func requestTrust() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func requestListen() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    func quitMos() {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.mosID).forEach { $0.terminate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.check() }
    }

    func show(_ text: String) {
        toast = text
        toastWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
    }

    // MARK: Mở khi đăng nhập
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            objectWillChange.send()
        }
    }
}

/// Nhập cài đặt Mos đang dùng (chỉ đọc, không sửa gì của Mos)
enum MosImport {
    private static var mos: UserDefaults? { UserDefaults(suiteName: AppModel.mosID) }
    static var available: Bool { mos?.object(forKey: "step") != nil }

    @discardableResult
    static func run() -> String {
        guard let m = mos, available else { return "Không tìm thấy cài đặt Mos trên máy." }
        let s = Settings.shared
        s.smooth = m.bool(forKey: "smooth")
        s.reverse = m.bool(forKey: "reverse")
        s.step = m.double(forKey: "step")
        s.speed = m.double(forKey: "speed")
        s.duration = m.double(forKey: "duration")
        var nutNote = "không có nút chuột nào được gán"
        if let data = m.data(forKey: "buttonBindings"),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var n = 0
            for b in arr where (b["isEnabled"] as? Bool) == true {
                guard let trig = b["triggerEvent"] as? [String: Any], trig["type"] as? String == "mouse",
                      let code = trig["code"] as? Int, let name = b["systemShortcutName"] as? String else { continue }
                let map: [String: ButtonAction] = ["missionControl": .missionControl, "navigateBack": .quayLai,
                                                   "navigateForward": .diTiep, "showDesktop": .manHinhNen]
                if let a = map[name] { s.setSlot(code + 1, .click, Slot(action: a)); n += 1 }   // Mos đánh số từ 0
            }
            nutNote = "\(n) nút chuột"
        }
        return String(format: "Đã nhập từ Mos: cuộn mượt %@, đảo chiều %@, step %.1f, speed %.2f, duration %.2f, %@.",
                      s.smooth ? "bật" : "tắt", s.reverse ? "bật" : "tắt", s.step, s.speed, s.duration, nutNote)
    }
}

// DuckMouse Dò nút – app nhỏ, 1 cửa sổ: xem đầu thu chuột gửi gì khi bấm nút (dò lỗi nút hông không nhận).
// Bạn bấm các nút → chụp màn hình gửi Duck. Không cài gì, không chạy ngầm, tắt là hết.
// © 2026 by Vduck · CC BY-NC 4.0 (dùng chung giấy phép với DuckMouse)
import SwiftUI
import AppKit
import IOKit.hid

// MARK: - màu (giống DuckMouse)
enum C {
    static func c(_ v: UInt32, _ a: CGFloat = 1) -> Color {
        Color(.sRGB, red: Double(v >> 16 & 255) / 255, green: Double(v >> 8 & 255) / 255, blue: Double(v & 255) / 255, opacity: a)
    }
    static let page = c(0x07080D), card = c(0x13141C), s2 = c(0x1A1B25), ink = c(0xF4F0E8)
    static let ink2 = c(0xF4F0E8, 0.68), ink3 = c(0xF4F0E8, 0.42), line = c(0xFFFFFF, 0.08)
    static let brand = c(0xFFC933), mint = c(0x7EE8C0), warn = c(0xFFB26B), danger = c(0xFF7D8C)
}

enum Sig: Equatable { case button(Int), wheel(Int), other }

struct Part: Identifiable {
    let id: UInt64
    let title: String       // "VXE Mouse 1K Dongle · 3554:F58E"
    let kind: String        // "phần chuột 1/2"
    let declares: String    // "nút chuột 1–5 · lăn · …"
}

struct Line: Identifiable {
    let id = UUID()
    let time: String
    var text: String
    var detail: String
    var color: Color
    var mono = true          // chữ phụ là mã (gói thô…) → font đều
    var count = 1
}

// MARK: - đọc đầu thu
final class Watcher: ObservableObject {
    @Published var parts: [Part] = []
    @Published var hid: [Line] = []          // khung 2: đầu thu gửi
    @Published var mac: [Line] = []          // khung 3: macOS thấy
    @Published var granted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    @Published var moves = 0
    @Published var apps: [String] = []

    private let mice = IOHIDManagerCreate(kCFAllocatorDefault, 0)   // tìm chuột (phần 1/2)
    private let all = IOHIDManagerCreate(kCFAllocatorDefault, 0)    // mọi phần của các chuột đó (cùng mã), không đụng bàn phím thật
    private var ids: Set<Int> = []
    private var names: [UInt64: String] = [:]
    private var mouseParts: Set<UInt64> = []   // phần chuột chính (1/2): không hiện gói thô (di chuyển báo liên tục)
    private var lastKey: [UInt64: [UInt8]] = [:]
    private var bufs: [UInt64: UnsafeMutablePointer<UInt8>] = [:]
    private var opened = false
    private var timer: Timer?
    private var monitors: [Any] = []
    private let t0 = Date()
    /// Bài test nghe tín hiệu: (từ đầu thu?, tín hiệu, mô tả)
    var sink: ((Bool, Sig, String) -> Void)?
    private(set) var log: [String] = []       // mọi dòng (ghi vào file kết quả)

    func start() {
        IOHIDManagerSetDeviceMatching(mice, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse] as CFDictionary)
        IOHIDManagerSetDeviceMatchingMultiple(all, [] as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let changed: IOHIDDeviceCallback = { ctx, _, _, _ in
            let me = Unmanaged<Watcher>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { me.refresh() }
        }
        IOHIDManagerRegisterDeviceMatchingCallback(mice, changed, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mice, changed, ctx)
        IOHIDManagerRegisterDeviceMatchingCallback(all, changed, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(all, changed, ctx)
        IOHIDManagerRegisterInputValueCallback(all, { ctx, _, sender, value in
            guard let sender else { return }
            let me = Unmanaged<Watcher>.fromOpaque(ctx!).takeUnretainedValue()
            me.value(Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue(), value)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mice, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerScheduleWithRunLoop(all, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        if !granted && !CommandLine.arguments.contains("--khong-hoi-quyen") { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }   // cờ chỉ dùng khi Duck thử ngầm
        open()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        watchMac()
        scanApps()
    }

    private func tick() {
        let g = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if g != granted { granted = g }
        if g && !opened { open() }
        scanApps()
    }

    private func open() {
        guard !opened else { return }
        opened = IOHIDManagerOpen(mice, 0) == kIOReturnSuccess
        refresh()
    }

    /// Cập nhật danh sách: chuột nào đang nối → nghe mọi phần cùng mã của nó
    private func refresh() {
        let m = (IOHIDManagerCopyDevices(mice) as? Set<IOHIDDevice>) ?? []
        let newIDs = Set(m.compactMap { d -> Int? in
            let tr = Self.str(d, kIOHIDTransportKey), p = Self.str(d, kIOHIDProductKey)
            if ["FIFO", "SPI", "SPU", "AID"].contains(tr) || p.hasPrefix("Apple Internal") { return nil }   // bàn di chuột trong máy
            let v = Self.num(d, kIOHIDVendorIDKey), pid = Self.num(d, kIOHIDProductIDKey)
            return v == 0 ? nil : v << 16 | pid
        })
        if newIDs != ids {
            ids = newIDs
            IOHIDManagerSetDeviceMatchingMultiple(all, ids.map { [kIOHIDVendorIDKey: $0 >> 16, kIOHIDProductIDKey: $0 & 0xFFFF] } as CFArray)
            _ = IOHIDManagerOpen(all, 0)
        }
        let devs = ((IOHIDManagerCopyDevices(all) as? Set<IOHIDDevice>) ?? []).sorted { Self.rid($0) < Self.rid($1) }
        var list: [Part] = []
        for d in devs {
            let id = Self.rid(d)
            let pg = Self.num(d, kIOHIDPrimaryUsagePageKey), u = Self.num(d, kIOHIDPrimaryUsageKey)
            let kind = pg == 1 && u == 2 ? "chuột" : pg == 1 && u == 6 ? "bàn phím" : pg == 12 ? "phím đa phương tiện" : pg >= 0xFF00 ? "riêng của hãng" : "khác"
            let title = String(format: "%@ · %04X:%04X · %@", Self.str(d, kIOHIDProductKey), Self.num(d, kIOHIDVendorIDKey), Self.num(d, kIOHIDProductIDKey), Self.str(d, kIOHIDTransportKey))
            names[id] = "phần \(kind)"
            if pg == 1 && u == 2 { mouseParts.insert(id) }
            list.append(Part(id: id, title: title, kind: "Phần \(kind) (\(pg)/\(u))", declares: Self.declares(d)))
            if bufs[id] == nil {        // nghe gói thô (thấy cả tín hiệu phần riêng hãng không khai tên)
                let size = max(64, Self.num(d, kIOHIDMaxInputReportSizeKey))
                let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
                bufs[id] = buf
                IOHIDDeviceRegisterInputReportCallback(d, buf, size, { ctx, _, sender, _, rep, data, len in
                    guard let ctx, let sender else { return }
                    let me = Unmanaged<Watcher>.fromOpaque(ctx).takeUnretainedValue()
                    me.report(Watcher.rid(Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()), rep, Array(UnsafeBufferPointer(start: data, count: len)))
                }, Unmanaged.passUnretained(self).toOpaque())
            }
        }
        parts = list
    }

    /// Phần này khai những gì: nút chuột 1–5, lăn, phím…
    static func declares(_ d: IOHIDDevice) -> String {
        let els = (IOHIDDeviceCopyMatchingElements(d, nil, 0) as? [IOHIDElement]) ?? []
        var btn = Set<UInt32>(), out: [String] = [], cons = Set<UInt32>(), keys = 0, vendor = 0
        var wheel = false, pan = false, xy = false
        for e in els where IOHIDElementGetType(e) != kIOHIDElementTypeCollection {
            let pg = IOHIDElementGetUsagePage(e), u = IOHIDElementGetUsage(e)
            switch pg {
            case 9: if u > 0 { btn.insert(u) }
            case 1: if u == 0x38 { wheel = true } else if u == 0x30 || u == 0x31 { xy = true }
            case 7: keys += 1
            case 12: if u == 0x238 { pan = true } else if u > 0 { cons.insert(u) }
            default: if pg >= 0xFF00 { vendor += 1 }
            }
        }
        if xy { out.append("di chuyển") }
        if !btn.isEmpty { out.append("nút chuột " + (btn.count == Int(btn.max()!) ? "1–\(btn.max()!)" : btn.sorted().map(String.init).joined(separator: ","))) }
        if wheel { out.append("lăn dọc") }
        if pan { out.append("lăn ngang") }
        if keys > 0 { out.append("phím bàn phím") }
        if !cons.isEmpty { out.append("phím đa phương tiện (\(cons.count))") }
        if vendor > 0 { out.append("dữ liệu riêng hãng (\(vendor))") }
        return out.isEmpty ? "không khai gì" : out.joined(separator: " · ")
    }

    // MARK: tín hiệu
    private func value(_ d: IOHIDDevice, _ v: IOHIDValue) {
        let e = IOHIDValueGetElement(v)
        let pg = IOHIDElementGetUsagePage(e), u = IOHIDElementGetUsage(e), n = IOHIDValueGetIntegerValue(v)
        let part = names[Self.rid(d)] ?? "phần ?"
        if pg == 1 && (u == 0x30 || u == 0x31) { moves += 1; return }
        let hx = { (x: UInt32) in String(x, radix: 16, uppercase: true) }
        switch pg {
        case 9:
            add(&hid, "\(part) · NÚT CHUỘT \(u) · \(n != 0 ? "nhấn" : "nhả")", String(format: "trang 0x09 mục %d = %d", u, n), n != 0 ? C.mint : C.ink3)
            if n != 0 { sink?(true, .button(Int(u)), "\(part) · nút chuột \(u)") }
        case 1 where u == 0x38:
            guard n != 0 else { return }
            add(&hid, "\(part) · lăn \(n > 0 ? "lên" : "xuống")", "trang 0x01 mục 0x38", C.ink2)
            sink?(true, .wheel(n > 0 ? 1 : -1), "\(part) · lăn \(n > 0 ? "lên" : "xuống")")
        case 7:
            guard u >= 4 && u <= 0xE7 else { return }
            add(&hid, "\(part) · PHÍM 0x\(hx(u)) · \(n != 0 ? "nhấn" : "nhả")", "trang 0x07 (bàn phím)", C.warn)
            if n != 0 && u < 0xE0 { sink?(true, .other, "\(part) · gửi PHÍM bàn phím 0x\(hx(u))") }
        case 12:
            guard n != 0 || u != 0x238 else { return }
            add(&hid, "\(part) · PHÍM ĐA PHƯƠNG TIỆN 0x\(hx(u)) = \(n)", "trang 0x0C", C.warn)
            if n != 0 && u != 0x238 { sink?(true, .other, "\(part) · gửi PHÍM đa phương tiện 0x\(hx(u))") }
        default:
            add(&hid, "\(part) · trang 0x\(hx(pg)) mục 0x\(hx(u)) = \(n)", "", C.brand)
            if n != 0 { sink?(true, .other, "\(part) · trang 0x\(hx(pg)) mục 0x\(hx(u)) = \(n)") }
        }
    }

    /// Gói thô của các phần KHÔNG phải chuột chính (bàn phím, đa phương tiện, riêng hãng) – ít gửi, để thấy nút đi đường lạ.
    /// Phần chuột chính báo liên tục khi di chuyển → chỉ hiện dòng nút / lăn (04/11: bản đầu ngập dòng gói thô)
    private func report(_ id: UInt64, _ rep: UInt32, _ b: [UInt8]) {
        if mouseParts.contains(id) { return }
        if lastKey[id] == b { return }
        lastKey[id] = b
        let hex = b.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
        add(&hid, "\(names[id] ?? "phần ?") · gói thô #\(rep)", hex, C.ink3)
        if b.contains(where: { $0 != 0 }) && !(b.count > 1 && b.dropFirst().allSatisfy { $0 == 0 }) {
            sink?(true, .other, "\(names[id] ?? "phần ?") · gói thô #\(rep): \(hex)")
        }
    }

    /// Khung 3: macOS thấy nút chuột nào (mọi app), phím chỉ khi cửa sổ này đang mở phía trước (không đọc phím ở app khác)
    private func watchMac() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .otherMouseUp, .scrollWheel]
        let f: (NSEvent) -> Void = { [weak self] e in
            guard let self else { return }
            if e.type == .scrollWheel {
                guard e.scrollingDeltaY != 0, e.momentumPhase == [] else { return }
                // hướng lăn ở macOS bị đảo theo cài đặt «cuộn tự nhiên» / app cuộn mượt → không ghi hướng, hướng thật xem ở đầu thu
                self.add(&self.mac, "macOS: lăn", "", C.ink2, mono: false)
                self.sink?(false, .wheel(1), "macOS thấy lăn")
                return
            }
            let n = e.buttonNumber + 1
            if e.type != .otherMouseUp { self.sink?(false, .button(n), "macOS thấy nút chuột \(n)") }
            let up = e.type == .otherMouseUp
            if up && n < 3 { return }
            let what = [1: "nút trái", 2: "nút phải", 3: "nút giữa (nhấn bánh xe)", 4: "nút hông – Chrome hiểu là Quay lại", 5: "nút hông – Chrome hiểu là Đi tiếp"][n] ?? "nút thêm"
            self.add(&self.mac, "macOS: NÚT CHUỘT \(n) · \(up ? "nhả" : "nhấn")", what, up ? C.ink3 : C.mint, mono: false)
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: f) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask.union(.keyDown), handler: { [weak self] e in
            guard let self else { return e }
            if e.type == .keyDown {
                self.add(&self.mac, "macOS: PHÍM \(e.charactersIgnoringModifiers ?? "?") (mã \(e.keyCode))", Watcher.mods(e.modifierFlags), C.warn, mono: false)
                self.sink?(false, .other, "macOS thấy PHÍM \(Watcher.mods(e.modifierFlags))\(e.charactersIgnoringModifiers ?? "?") (mã \(e.keyCode))")
            } else { f(e) }
            return e
        }) { monitors.append(l) }
    }

    static func mods(_ m: NSEvent.ModifierFlags) -> String {
        [(m.contains(.control), "⌃"), (m.contains(.option), "⌥"), (m.contains(.shift), "⇧"), (m.contains(.command), "⌘")].filter(\.0).map(\.1).joined()
    }

    /// App có thể chặn / đổi nút chuột (phần mềm hãng, app gán nút)
    private func scanApps() {
        let keys = ["atk", "vxe", "vgn", "duckmouse", "karabiner", "bettertouchtool", "steermouse", "linearmouse", "logi options",
                    "logioptions", "razer synapse", "steelseries", "usb overdrive", "sensiblesidebuttons", "mac mouse fix"]
        let found = NSWorkspace.shared.runningApplications.compactMap { a -> String? in
            let n = (a.localizedName ?? "").lowercased(), b = (a.bundleIdentifier ?? "").lowercased()
            if a.processIdentifier == ProcessInfo.processInfo.processIdentifier || n.contains("dò nút") || b.contains("donut") { return nil }
            if b == "com.caldis.mos" { return "Mos" }
            return keys.contains { n.contains($0) || b.contains($0.replacingOccurrences(of: " ", with: "")) } ? (a.localizedName ?? b) : nil
        }
        let s = Array(Set(found)).sorted()
        if s != apps { apps = s }
    }

    private func add(_ list: inout [Line], _ text: String, _ detail: String, _ color: Color, mono: Bool = true) {
        let tt = String(format: "%.2f s", Date().timeIntervalSince(t0))
        if log.count < 3000 { log.append("\(tt)  \(text)" + (detail.isEmpty ? "" : "  [\(detail)]")) }
        if let f = list.first, f.text == text, f.detail == detail { list[0].count += 1; return }   // gộp dòng giống nhau
        list.insert(Line(time: String(format: "%.1f s", Date().timeIntervalSince(t0)), text: text, detail: detail, color: color, mono: mono), at: 0)
        if list.count > 40 { list.removeLast(list.count - 40) }
    }

    func clear() { hid = []; mac = []; moves = 0; lastKey = [:]; log = [] }

    static func rid(_ d: IOHIDDevice) -> UInt64 { var id: UInt64 = 0; IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(d), &id); return id }
    static func str(_ d: IOHIDDevice, _ k: String) -> String { IOHIDDeviceGetProperty(d, k as CFString) as? String ?? "" }
    static func num(_ d: IOHIDDevice, _ k: String) -> Int { IOHIDDeviceGetProperty(d, k as CFString) as? Int ?? 0 }
}

// MARK: - giao diện
struct Panel<Content: View>: View {
    let title: String, sub: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 15, weight: .heavy))
                Text(sub).font(.system(size: 12)).foregroundStyle(C.ink3)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(C.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(C.line))
    }
}

struct Lines: View {
    let lines: [Line]
    let empty: String
    var body: some View {
        if lines.isEmpty {
            Text(empty).font(.system(size: 13)).foregroundStyle(C.ink3).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines) { l in
                        HStack(alignment: .top, spacing: 8) {
                            Text(l.time).font(.system(size: 11, design: .monospaced)).foregroundStyle(C.ink3).frame(width: 50, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(l.text + (l.count > 1 ? "  ×\(l.count)" : "")).font(.system(size: 13, weight: .bold)).foregroundStyle(l.color)
                                if !l.detail.isEmpty { Text(l.detail).font(.system(size: 11.5, design: l.mono ? .monospaced : .default)).foregroundStyle(C.ink3) }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}


@main
struct DoNutApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    var body: some Scene {
        WindowGroup("DuckMouse Dò nút") { MainView() }.windowResizability(.contentMinSize)
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

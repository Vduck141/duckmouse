// Đọc chuột thật qua IOHID: danh sách chuột đang nối, tần số báo, nút, cuộn, quãng di chuyển (số đếm gốc của cảm biến)
import Foundation
import IOKit.hid
import CoreGraphics

struct MouseDevice: Identifiable, Hashable {
    let id: UInt64                  // registry ID, duy nhất cho mỗi lần cắm
    let product: String
    let manufacturer: String
    let transport: String           // "USB" / "Bluetooth Low Energy" / "Bluetooth"
    let vendorID: Int
    let productID: Int
    let version: Int
    let reportIntervalUS: Int       // khoảng báo tối thiểu cổng USB khai (µs), 0 = không có
    let declaredButtons: Int        // số nút chuột tự khai (có thể nhiều hơn nút thật)
    let declaresHScroll: Bool       // tự khai có lăn ngang (dongle MS01 khai có nhưng chuột thật không có)

    var displayName: String { MiceDB.shared.displayName(self) }
    var brand: String { MiceDB.shared.spec(for: self)?.brand ?? KnownMice.vendorName(vendorID) ?? (manufacturer.isEmpty ? "Không rõ" : manufacturer) }
    var connection: String {
        if transport.hasPrefix("Bluetooth") { return "Bluetooth" }
        if product.localizedCaseInsensitiveContains("receiver") || product.contains("2.4G") { return "Dongle 2.4G (USB)" }
        return transport == "USB" ? "Cáp USB" : transport
    }
    var codeText: String { String(format: "%04X:%04X", vendorID, productID) }
    var versionText: String { String(format: "%X.%02X", version >> 8, version & 0xFF) }
}

final class MouseHID: ObservableObject {
    static let shared = MouseHID()

    @Published private(set) var devices: [MouseDevice] = []
    @Published private(set) var liveHz: [UInt64: Double] = [:]     // trung vị các khoảng báo gần đây
    @Published private(set) var lastActive: UInt64?
    @Published private(set) var openError: String?

    // Người nghe (tab Test). Gọi trên main thread.
    var moveListeners: [UUID: (UInt64, Int, Int, Double) -> Void] = [:]     // id, dx, dy, thời điểm (ms)
    var buttonListeners: [UUID: (UInt64, Int, Bool, Double) -> Void] = [:]  // id, nút (1..), nhấn?, ms
    var wheelListeners: [UUID: (UInt64, Int) -> Void] = [:]
    var hwheelListeners: [UUID: (UInt64, Int) -> Void] = [:]                // lăn ngang / nghiêng bánh xe (âm = trái)
    var reportListeners: [UUID: (UInt64, Double) -> Void] = [:]             // id, khoảng giữa 2 gói (ms)
    var onDevicesChanged: (() -> Void)?
    /// Tín hiệu kiểu phím từ chuột (nút hông gửi phím Back/Forward…): (nút đã đổi thành – nil nếu chưa đổi được, mô tả)
    var signalListeners: [UUID: (Int?, String) -> Void] = [:]

    private let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    /// Bộ nghe thứ 2: mọi phần (bàn phím, phím đa phương tiện) của CHÍNH các con chuột đang nối – khớp theo mã hãng + mã chuột,
    /// không đụng bàn phím thật (04/11: VXE R1 gửi nút hông qua phần khác của đầu thu, bộ nghe chuột không thấy)
    private let extra = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var extraIDs: Set<Int> = []
    private var extraOpen = false
    private var mods: [UInt64: Set<UInt32>] = [:]          // phím bổ trợ đang giữ (⌘ ⌥ ⌃ ⇧) theo phần của chuột
    private var lastTS: [UInt64: UInt64] = [:]
    private var recent: [UInt64: [Double]] = [:]
    private var timebase = mach_timebase_info_data_t()
    private var hzTimer: Timer?

    private init() {
        mach_timebase_info(&timebase)
        IOHIDManagerSetDeviceMatching(mgr, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse] as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, _ in
            Unmanaged<MouseHID>.fromOpaque(ctx!).takeUnretainedValue().refreshDevices()
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, _ in
            Unmanaged<MouseHID>.fromOpaque(ctx!).takeUnretainedValue().refreshDevices()
        }, ctx)
        IOHIDManagerRegisterInputValueCallback(mgr, { ctx, _, sender, value in
            guard let sender else { return }
            let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            Unmanaged<MouseHID>.fromOpaque(ctx!).takeUnretainedValue().handle(dev, value)
        }, ctx)
        IOHIDManagerSetDeviceMatchingMultiple(extra, [] as CFArray)
        IOHIDManagerRegisterInputValueCallback(extra, { ctx, _, sender, value in
            guard let sender else { return }
            let dev = Unmanaged<IOHIDDevice>.fromOpaque(sender).takeUnretainedValue()
            Unmanaged<MouseHID>.fromOpaque(ctx!).takeUnretainedValue().handleExtra(dev, value)
        }, ctx)
    }

    @Published private(set) var listenGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    private var started = false
    private var isOpen = false

    func start() {
        if !started {
            started = true
            IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerScheduleWithRunLoop(extra, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            hzTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.publishHz() }
            // Đọc nút / di chuyển của chuột cần quyền "Theo dõi đầu vào" → macOS tự hỏi 1 lần
            if !listenGranted && !CommandLine.arguments.contains("--khong-hoi-quyen") { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }   // cờ chỉ dùng khi Duck thử ngầm
        }
        open()
    }

    /// Mở lại khi anh vừa cấp quyền (AppModel gọi định kỳ)
    func retryIfNeeded() {
        let g = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if g != listenGranted { listenGranted = g }
        if openError != nil && g { open() }
    }

    private func open() {
        // KHÔNG gọi IOHIDManagerClose trước khi mở: đo 03/11 – Close rồi Open thì mở "thành công" nhưng 0 gói dữ liệu
        guard !isOpen else { refreshDevices(); return }
        let r = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = r == kIOReturnSuccess
        openError = r == kIOReturnSuccess ? nil : "Cần quyền \"Theo dõi đầu vào\" để đo tần số, test nút, bánh xe."
        refreshDevices()
    }

    func device(_ id: UInt64?) -> MouseDevice? { devices.first { $0.id == id } }

    // MARK: - nội bộ

    private static func regID(_ d: IOHIDDevice) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(d), &id)
        return id
    }

    private func refreshDevices() {
        let set = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []
        func str(_ d: IOHIDDevice, _ k: String) -> String { IOHIDDeviceGetProperty(d, k as CFString) as? String ?? "" }
        func num(_ d: IOHIDDevice, _ k: String) -> Int { IOHIDDeviceGetProperty(d, k as CFString) as? Int ?? 0 }
        var list: [MouseDevice] = []
        for d in set {
            let tr = str(d, kIOHIDTransportKey), p = str(d, kIOHIDProductKey)
            // bỏ trackpad / thiết bị trong máy
            if ["FIFO", "SPI", "SPU", "AID"].contains(tr) || p.hasPrefix("Apple Internal") { continue }
            let vid = num(d, kIOHIDVendorIDKey), pid = num(d, kIOHIDProductIDKey)
            // đọc mô tả thiết bị (không đọc dữ liệu bấm): số nút + có lăn ngang không
            let els = (IOHIDDeviceCopyMatchingElements(d, nil, 0) as? [IOHIDElement]) ?? []
            var btns = Set<UInt32>(), pan = false
            for e in els {
                let pg = IOHIDElementGetUsagePage(e), u = IOHIDElementGetUsage(e)
                if pg == UInt32(kHIDPage_Button) && u > 0 { btns.insert(u) }
                if pg == UInt32(kHIDPage_Consumer) && u == 0x238 { pan = true }
            }
            list.append(MouseDevice(id: Self.regID(d), product: p, manufacturer: str(d, kIOHIDManufacturerKey),
                                    transport: tr, vendorID: vid, productID: pid, version: num(d, kIOHIDVersionNumberKey),
                                    reportIntervalUS: num(d, kIOHIDReportIntervalKey), declaredButtons: btns.count, declaresHScroll: pan))
        }
        list.sort { $0.product < $1.product }
        DispatchQueue.main.async {
            self.updateExtra(list)
            self.devices = list
            self.onDevicesChanged?()
        }
    }

    private func ms(_ t: UInt64) -> Double { Double(t) * Double(timebase.numer) / Double(timebase.denom) / 1e6 }

    private func handle(_ dev: IOHIDDevice, _ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(el), usage = IOHIDElementGetUsage(el)
        let v = IOHIDValueGetIntegerValue(value)
        let id = Self.regID(dev)
        let t = IOHIDValueGetTimeStamp(value)
        let tms = ms(t)

        if page == kHIDPage_GenericDesktop && (usage == kHIDUsage_GD_X || usage == kHIDUsage_GD_Y) {
            guard v != 0 else { return }
            if t != lastTS[id] {            // X và Y cùng 1 gói báo → chỉ tính 1 lần
                if let last = lastTS[id] {
                    let gap = ms(t &- last)
                    if gap > 0 && gap < 100 {   // >100 ms = ngừng tay, không tính
                        var r = recent[id] ?? []
                        r.append(gap); if r.count > 300 { r.removeFirst(r.count - 300) }
                        recent[id] = r
                        for l in reportListeners.values { l(id, gap) }
                    }
                }
                lastTS[id] = t
                if lastActive != id { lastActive = id }
            }
            let dx = usage == kHIDUsage_GD_X ? v : 0, dy = usage == kHIDUsage_GD_Y ? v : 0
            for l in moveListeners.values { l(id, dx, dy, tms) }
        } else if page == kHIDPage_Button {
            for l in buttonListeners.values { l(id, Int(usage), v != 0, tms) }
        } else if page == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Wheel {
            guard v != 0 else { return }
            for l in wheelListeners.values { l(id, v) }
        } else if page == kHIDPage_Consumer && usage == 0x238 {          // AC Pan = lăn ngang
            guard v != 0 else { return }
            for l in hwheelListeners.values { l(id, v) }
        }
    }

    // MARK: - nút hông gửi kiểu phím

    /// Nghe thêm mọi phần của các chuột đang nối (cùng mã hãng + mã chuột)
    private func updateExtra(_ list: [MouseDevice]) {
        guard isOpen else { return }
        let ids = Set(list.filter { $0.vendorID != 0 }.map { $0.vendorID << 16 | $0.productID })
        guard ids != extraIDs else { return }
        extraIDs = ids
        let match = ids.map { [kIOHIDVendorIDKey: $0 >> 16, kIOHIDProductIDKey: $0 & 0xFFFF] as [String: Any] }
        IOHIDManagerSetDeviceMatchingMultiple(extra, match as CFArray)
        if !extraOpen && !ids.isEmpty { extraOpen = IOHIDManagerOpen(extra, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess }
    }

    /// Phím đa phương tiện Back / Forward (AC Back 0x224, AC Forward 0x225) → nút hông 4 / 5
    static let consumerButtons: [UInt32: Int] = [0x224: 4, 0x225: 5]
    private var virtualDown: Int?

    private func handleExtra(_ dev: IOHIDDevice, _ value: IOHIDValue) {
        let el = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(el), usage = IOHIDElementGetUsage(el)
        let v = IOHIDValueGetIntegerValue(value)
        let id = Self.regID(dev)
        if page == kHIDPage_Consumer, Self.consumerButtons[usage] != nil {
            consumer(id, usage, down: v != 0, tms: ms(IOHIDValueGetTimeStamp(value)))
        } else if page == kHIDPage_KeyboardOrKeypad {
            guard usage >= 4 && usage <= 0xE7 else { return }
            if usage >= 0xE0 {                                  // ⌃ ⇧ ⌥ ⌘ (trái/phải)
                if v != 0 { mods[id, default: []].insert(usage % 4) } else { mods[id]?.remove(usage % 4) }
                return
            }
            guard v != 0, !signalListeners.isEmpty else { return }
            let m = mods[id] ?? []
            let name = [0: "⌃", 1: "⇧", 2: "⌥", 3: "⌘"].filter { m.contains($0.key) }.sorted { $0.key < $1.key }.map(\.value).joined()
                + Self.keyName(usage)
            if KeyButtons.button(hidUsage: usage, mods: m) != nil {
                // ⌘[ ⌘] ⌥← ⌥→: KeyButtons đổi thành nút 4/5 và tự báo; chỉ báo ở đây khi bộ đổi chưa chạy
                let vid = IOHIDDeviceGetProperty(dev, kIOHIDVendorIDKey as CFString) as? Int ?? 0
                let pid = IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int ?? 0
                if KeyButtons.shared.converts(vendor: vid, product: pid) { return }
                for l in signalListeners.values { l(nil, "phím bàn phím " + name + " – bật «Gán chức năng» + quyền Trợ năng để app đổi thành nút hông") }
                return
            }
            for l in signalListeners.values { l(nil, "phím bàn phím " + name) }
        } else if page == kHIDPage_Consumer, usage != 0x238, v != 0, !signalListeners.isEmpty {
            for l in signalListeners.values { l(nil, String(format: "phím đa phương tiện 0x%03X", usage)) }
        }
    }

    private func consumer(_ id: UInt64, _ usage: UInt32, down: Bool, tms: Double) {
        guard let b = Self.consumerButtons[usage] else { return }
        if down == (virtualDown == b) { return }            // báo lặp cùng trạng thái
        virtualDown = down ? b : nil
        if down { for l in signalListeners.values { l(b, usage == 0x224 ? "phím Back" : "phím Forward") } }
        for l in buttonListeners.values { l(id, b, down, tms) }       // ô test đếm như nút chuột
        ButtonEngine.shared.virtualButton(b, down: down)              // Gán chức năng + trả nút 4/5 cho app khác
    }

    /// Chỉ cho bản thử (mở app kèm --gia-lap): giả tín hiệu phím Back/Forward/⌥← như chuột VXE gửi, vì máy Duck không có chuột đó
    func enableSimulation() {
        DistributedNotificationCenter.default().addObserver(forName: .init("vn.vduck.DuckMouse.gialap"), object: nil, queue: .main) { [weak self] n in
            guard let self else { return }
            let t = Double(DispatchTime.now().uptimeNanoseconds) / 1e6
            switch n.object as? String {
            case "back", "forward":
                let u: UInt32 = n.object as? String == "back" ? 0x224 : 0x225
                self.consumer(0, u, down: true, tms: t)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.consumer(0, u, down: false, tms: t + 80) }
            case "cmd[", "cmd]", "alt<":                          // chuột Ugreen chế độ Mac / chuột kiểu Windows
                let (code, f): (Int64, CGEventFlags) = n.object as? String == "cmd[" ? (33, .maskCommand)
                    : n.object as? String == "cmd]" ? (30, .maskCommand) : (123, .maskAlternate)
                KeyButtons.shared.simulate(code, flags: f, down: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { KeyButtons.shared.simulate(code, flags: f, down: false) }
            default:
                for l in self.signalListeners.values { l(nil, "phím bàn phím ⌥←") }
            }
        }
    }

    /// KeyButtons báo: chuột vừa gửi phím đã đổi thành nút b → tab Test đếm như nút chuột + ghi dòng giải thích
    func emitVirtual(_ b: Int, down: Bool, text: String?) {
        if down, let text { for l in signalListeners.values { l(b, text) } }
        let t = Double(DispatchTime.now().uptimeNanoseconds) / 1e6
        for l in buttonListeners.values { l(0, b, down, t) }
    }

    static func keyName(_ u: UInt32) -> String {
        if u >= 4 && u <= 0x1D { return String(UnicodeScalar(UInt8(u - 4) + 65)) }       // A–Z
        if u >= 0x1E && u <= 0x27 { return String((u - 0x1E + 1) % 10) }                 // 1–0
        if u >= 0x3A && u <= 0x45 { return "F\(u - 0x39)" }
        return [0x28: "Enter", 0x29: "Esc", 0x2A: "Xoá", 0x2B: "Tab", 0x2C: "Space", 0x2F: "[", 0x30: "]",
                0x4F: "→", 0x50: "←", 0x51: "↓", 0x52: "↑", 0x4A: "Home", 0x4D: "End"][u] ?? String(format: "0x%02X", u)
    }

    private func publishHz() {
        var out: [UInt64: Double] = [:]
        for (id, r) in recent where r.count >= 30 {
            let s = r.sorted()
            out[id] = 1000 / s[s.count / 2]
        }
        if out != liveHz { liveHz = out }
    }
}

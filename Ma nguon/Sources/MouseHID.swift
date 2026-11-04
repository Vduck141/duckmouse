// Đọc chuột thật qua IOHID: danh sách chuột đang nối, tần số báo, nút, cuộn, quãng di chuyển (số đếm gốc của cảm biến)
import Foundation
import IOKit.hid

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

    private let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
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
    }

    @Published private(set) var listenGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    private var started = false
    private var isOpen = false

    func start() {
        if !started {
            started = true
            IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            hzTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.publishHz() }
            // Đọc nút / di chuyển của chuột cần quyền "Theo dõi đầu vào" → macOS tự hỏi 1 lần
            if !listenGranted { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
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

    private func publishHz() {
        var out: [UInt64: Double] = [:]
        for (id, r) in recent where r.count >= 30 {
            let s = r.sorted()
            out[id] = 1000 / s[s.count / 2]
        }
        if out != liveHz { liveHz = out }
    }
}

// Nhật ký DuckMouse: ~/Library/Logs/DuckMouse/nhat-ky.txt (quá 1 MB → đổi thành nhat-ky.1.txt, ghi file mới).
// Luôn ghi việc lớn: mở app, quyền, bộ bắt, chuột cắm / rút, lỗi. «Chế độ dò lỗi» (tự tắt sau 10 phút) ghi thêm từng lần bấm nút:
// tín hiệu thô từ chuột → app đổi / bỏ qua vì sao → chạy chức năng gì. KHÔNG ghi chữ gõ từ bàn phím.
// Cài đặt → «Xuất nhật ký ra Tải về» = tóm tắt máy + nhật ký → 1 file .txt để người dùng gửi Duck.
import AppKit
import IOKit.hid

enum Log {
    /// Thư mục nhật ký (bản thử đặt DUCKMOUSE_LOG_DIR để không ghi lẫn vào nhật ký thật)
    static let dir: URL = ProcessInfo.processInfo.environment["DUCKMOUSE_LOG_DIR"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DuckMouse")
    static var file: URL { dir.appendingPathComponent("nhat-ky.txt") }
    static var oldFile: URL { dir.appendingPathComponent("nhat-ky.1.txt") }
    static let maxSize = 1_000_000

    private static let q = DispatchQueue(label: "vn.vduck.DuckMouse.log")
    private static var handle: FileHandle?
    private static var perSecond = 0, secondStart = Date(), dropped = 0
    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd/MM/yyyy HH:mm:ss"; return f }()

    // MARK: chế độ dò lỗi

    private static var until: Date? = UserDefaults.standard.object(forKey: "debugUntil") as? Date
    /// Thời điểm tự tắt chế độ dò lỗi (nil = đang tắt)
    static var debugUntil: Date? { until.flatMap { $0 > Date() ? $0 : nil } }
    static var debugOn: Bool { if let u = until { return u > Date() }; return false }
    /// Đã quá 10 phút mà chưa ghi «tự tắt»
    static var debugExpired: Bool { if let u = until { return u <= Date() }; return false }
    static func setDebug(_ on: Bool, minutes: Double = 10) {
        until = on ? Date().addingTimeInterval(minutes * 60) : nil
        UserDefaults.standard.set(until, forKey: "debugUntil")
        info("DÒ LỖI", on ? "BẬT chế độ dò lỗi \(Int(minutes)) phút – ghi chi tiết từng lần bấm nút" : "TẮT chế độ dò lỗi")
        if on { MouseHID.shared.registerRaw() }
    }

    // MARK: ghi

    /// Việc lớn – luôn ghi
    static func info(_ tag: String, _ msg: String) { write(tag, msg) }
    /// Chi tiết từng lần bấm – chỉ ghi khi bật chế độ dò lỗi (chuỗi chỉ tạo khi cần)
    static func detail(_ tag: String, _ msg: @autoclosure () -> String) { if debugOn { write(tag, msg()) } }

    static func session() {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        write("", "", raw: "\n=== DuckMouse \(v) mở lúc \(dayFmt.string(from: Date())) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(model()) ===\n")
    }

    private static func write(_ tag: String, _ msg: String, raw: String? = nil) {
        let now = Date()
        q.async {
            // chuột lỗi báo liên tục → tối đa 200 dòng / giây, không làm đầy ổ
            if now.timeIntervalSince(secondStart) >= 1 {
                if dropped > 0 { append("\(timeFmt.string(from: now)) GHI   … bỏ \(dropped) dòng (quá 200 dòng/giây)\n") }
                secondStart = now; perSecond = 0; dropped = 0
            }
            perSecond += 1
            if perSecond > 200 { dropped += 1; return }
            append(raw ?? "\(timeFmt.string(from: now)) \(tag.padding(toLength: 6, withPad: " ", startingAt: 0)) \(msg)\n")
        }
    }

    private static func append(_ s: String) {
        if handle == nil {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
            handle = try? FileHandle(forWritingTo: file)
            _ = try? handle?.seekToEnd()
        }
        guard let h = handle, let d = s.data(using: .utf8) else { return }
        try? h.write(contentsOf: d)
        if let size = try? h.offset(), size > UInt64(maxSize) {           // cắt file: giữ 1 bản cũ
            try? h.close(); handle = nil
            try? FileManager.default.removeItem(at: oldFile)
            try? FileManager.default.moveItem(at: file, to: oldFile)
        }
    }

    /// Chờ ghi xong mọi dòng đang xếp hàng (trước khi xuất / thoát)
    static func flush() { q.sync { try? handle?.synchronize() } }

    // MARK: xuất

    /// Tóm tắt máy + nhật ký (bản cũ + bản mới, tối đa ~600 KB cuối) → Tải về. Gọi trên luồng chính.
    static func export(to folder: URL? = nil) -> URL? {
        info("XUẤT", "xuất nhật ký ra Tải về")
        let head = summary()
        flush()
        var body = ""
        for f in [oldFile, file] { if let s = try? String(contentsOf: f, encoding: .utf8) { body += s } }
        if body.utf8.count > 600_000 { body = "… (bỏ phần đầu)\n" + String(body.suffix(600_000)) }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let name = "DuckMouse-nhat-ky-\(f.string(from: Date())).txt"
        let text = head + "\n== Nhật ký ==\n" + body
        let dl = (folder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!).appendingPathComponent(name)
        if (try? text.write(to: dl, atomically: true, encoding: .utf8)) != nil { return dl }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        return (try? text.write(to: tmp, atomically: true, encoding: .utf8)) != nil ? tmp : nil
    }

    /// Phần đầu file xuất: bản app, máy, quyền, bộ bắt, chuột + các phần đầu thu, ô đã gán
    static func summary() -> String {
        let m = AppModel.shared, h = MouseHID.shared, s = Settings.shared
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        func yn(_ b: Bool) -> String { b ? "CÓ" : "KHÔNG" }
        func run(_ b: Bool) -> String { b ? "chạy" : "TẮT" }
        var t: [String] = []
        t.append("=== DuckMouse \(v) – tóm tắt lúc \(dayFmt.string(from: Date())) ===")
        t.append("macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · máy \(model())")
        t.append("Quyền: Trợ năng \(yn(m.trusted)) · Theo dõi đầu vào \(yn(h.listenGranted))")
        t.append("Bộ bắt: nút \(run(ButtonEngine.shared.running)) · phím từ chuột \(run(KeyButtons.shared.running)) · cuộn \(run(ScrollEngine.shared.running))")
        t.append("Cài đặt: Gán chức năng \(s.buttonsEnabled ? "bật" : "TẮT") · Cuộn mượt \(s.scrollEnabled ? "bật" : "TẮT") · chữ báo \(s.hud ? "bật" : "tắt")")
        t.append("Mos: \(m.mosRunning ? "ĐANG CHẠY (DuckMouse nghỉ cuộn/nút)" : "không") · App chuột khác: \(m.otherMouseApps.isEmpty ? "không" : m.otherMouseApps.joined(separator: ", "))")
        t.append("Chế độ dò lỗi: " + (debugUntil.map { "bật tới \(timeFmt.string(from: $0).prefix(5))" } ?? "tắt (nhật ký chỉ có việc lớn)"))
        t.append("Chuột đang nối:")
        if h.devices.isEmpty { t.append("  (không thấy chuột nào)") }
        for d in h.devices {
            t.append("  • \(d.product.isEmpty ? "?" : d.product) · \(d.codeText) · \(d.transport) · khai \(d.declaredButtons) nút · nhận là: \(d.displayName)")
        }
        let parts = h.partsDescription()
        if !parts.isEmpty { t.append("Các phần của đầu thu / chuột:"); t += parts.map { "  - " + $0 } }
        let kb = KeyButtons.shared.keyboardDongles
        if !kb.isEmpty { t.append("Đầu thu có bàn phím (không đổi ⌘[ / ⌥← thành nút): " + kb.map { String(format: "%04X:%04X", $0 >> 16, $0 & 0xFFFF) }.joined(separator: ", ")) }
        let set = s.slots.filter { $0.value.action != .macDinh }.sorted { $0.key < $1.key }
        t.append("Đã gán: " + (set.isEmpty ? "chưa gán gì" : set.map { "\($0.key)=\($0.value.action.title)" }.joined(separator: " · ")))
        t.append("Giữ bao lâu: " + s.waits.sorted { $0.key < $1.key }.map { "nút \($0.key) \($0.value)s" }.joined(separator: ", ") + " · kéo \(Int(s.dragDistance)) px")
        return t.joined(separator: "\n") + "\n"
    }

    static func model() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var b = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &b, &size, nil, 0)
        return String(cString: b)
    }
}

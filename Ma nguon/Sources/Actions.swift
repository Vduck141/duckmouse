// 34 chức năng gán cho nút / cử chỉ chuột + chạy chức năng + ô chữ báo giữa màn hình
import AppKit
import CoreGraphics

enum ButtonAction: String, CaseIterable, Identifiable, Codable {
    case macDinh, khongGi
    // bộ nhớ tạm
    case copy, dan, cat, chonHet, hoanTac, lamLai
    // màn hình & cửa sổ
    case missionControl, manTrai, manPhai, appExpose, manHinhNen, ungDung, chuyenApp, anApp, thuNho, phongTo
    // trình duyệt
    case quayLai, diTiep, tabMoi, dongTab, moLaiTab, taiLai, tabTruoc, tabSau
    // hệ thống
    case chupVung, spotlight, khoaMan, phatDung, tangAm, giamAm
    // mở…
    case moThuMuc, moApp, moWeb, phimTat

    var id: String { rawValue }
    var title: String {
        switch self {
        case .macDinh: return "Giữ mặc định"
        case .khongGi: return "Không làm gì"
        case .copy: return "Copy ⌘C"
        case .dan: return "Dán ⌘V"
        case .cat: return "Cắt ⌘X"
        case .chonHet: return "Chọn hết ⌘A"
        case .hoanTac: return "Hoàn tác ⌘Z"
        case .lamLai: return "Làm lại ⌘⇧Z"
        case .missionControl: return "Mission Control"
        case .manTrai: return "Sang màn trái ⌃←"
        case .manPhai: return "Sang màn phải ⌃→"
        case .appExpose: return "Cửa sổ của app đang dùng"
        case .manHinhNen: return "Hiện màn hình nền"
        case .ungDung: return "Mở Ứng dụng (Apps)"
        case .chuyenApp: return "Chuyển app ⌘Tab"
        case .anApp: return "Ẩn app ⌘H"
        case .thuNho: return "Thu nhỏ cửa sổ ⌘M"
        case .phongTo: return "Toàn màn hình ⌃⌘F"
        case .quayLai: return "Quay lại ⌘["
        case .diTiep: return "Đi tiếp ⌘]"
        case .tabMoi: return "Tab mới ⌘T"
        case .dongTab: return "Đóng tab ⌘W"
        case .moLaiTab: return "Mở lại tab vừa đóng ⌘⇧T"
        case .taiLai: return "Tải lại trang ⌘R"
        case .tabTruoc: return "Tab trước ⌃⇧Tab"
        case .tabSau: return "Tab sau ⌃Tab"
        case .chupVung: return "Chụp vùng màn hình ⌘⇧4"
        case .spotlight: return "Spotlight ⌘Space"
        case .khoaMan: return "Khoá màn hình ⌃⌘Q"
        case .phatDung: return "Phát / dừng nhạc"
        case .tangAm: return "Tăng âm lượng"
        case .giamAm: return "Giảm âm lượng"
        case .moThuMuc: return "Mở thư mục…"
        case .moApp: return "Mở app…"
        case .moWeb: return "Mở trang web…"
        case .phimTat: return "Phím tắt tự chọn…"
        }
    }
    /// Tên ngắn cho ô gán
    var short: String { title.components(separatedBy: " ⌘").first!.components(separatedBy: " ⌃").first!.replacingOccurrences(of: "…", with: "") }
    var needsParam: Bool { [.moThuMuc, .moApp, .moWeb, .phimTat].contains(self) }
    /// Phím tắt tác dụng lên app đang mở phía trước (bấm «Thử» trong DuckMouse thì phải gửi sang app khác mới thấy)
    var targetsApp: Bool {
        [.copy, .dan, .cat, .chonHet, .hoanTac, .lamLai, .anApp, .thuNho, .phongTo,
         .quayLai, .diTiep, .tabMoi, .dongTab, .moLaiTab, .taiLai, .tabTruoc, .tabSau, .phimTat].contains(self)
    }

    static let groups: [(String, [ButtonAction])] = [
        ("Bộ nhớ tạm", [.copy, .dan, .cat, .chonHet, .hoanTac, .lamLai]),
        ("Màn hình & cửa sổ", [.missionControl, .manTrai, .manPhai, .appExpose, .manHinhNen, .ungDung, .chuyenApp, .anApp, .thuNho, .phongTo]),
        ("Trình duyệt", [.quayLai, .diTiep, .tabMoi, .dongTab, .moLaiTab, .taiLai, .tabTruoc, .tabSau]),
        ("Hệ thống", [.chupVung, .spotlight, .khoaMan, .phatDung, .tangAm, .giamAm]),
        ("Mở…", [.moThuMuc, .moApp, .moWeb, .phimTat]),
    ]
}

/// 1 ô gán: chức năng + tham số (đường dẫn thư mục / app, địa chỉ web, phím tắt "mã|cờ")
struct Slot: Codable, Equatable {
    var action: ButtonAction
    var param: String = ""
    static let none = Slot(action: .macDinh)

    var label: String { action == .macDinh ? "Chưa gán" : action.short }
    var detail: String {
        switch action {
        case .moThuMuc, .moApp: return param.isEmpty ? "chưa chọn" : (param as NSString).lastPathComponent
        case .moWeb: return param.isEmpty ? "chưa nhập" : param.replacingOccurrences(of: "https://", with: "")
        case .phimTat: return param.isEmpty ? "chưa ghi" : Shortcut(param)?.text ?? "?"
        default:
            let t = action.title
            if let r = t.range(of: " ⌘") ?? t.range(of: " ⌃") { return String(t[r.upperBound...]).isEmpty ? "" : String(t[t.index(after: r.lowerBound)...]) }
            return ""
        }
    }
}

/// Phím tắt tự chọn: "mãPhím|cờ"
struct Shortcut {
    let code: CGKeyCode, flags: CGEventFlags
    init(code: CGKeyCode, flags: CGEventFlags) { self.code = code; self.flags = flags }
    init?(_ s: String) {
        let p = s.split(separator: "|")
        guard p.count == 2, let c = UInt16(p[0]), let f = UInt64(p[1]) else { return nil }
        code = c; flags = CGEventFlags(rawValue: f)
    }
    var param: String { "\(code)|\(flags.rawValue)" }
    var text: String {
        var t = ""
        if flags.contains(.maskControl) { t += "⌃" }
        if flags.contains(.maskAlternate) { t += "⌥" }
        if flags.contains(.maskShift) { t += "⇧" }
        if flags.contains(.maskCommand) { t += "⌘" }
        return t + (Self.names[code] ?? "#\(code)")
    }
    static let names: [CGKeyCode: String] = {
        var m: [CGKeyCode: String] = [36: "↩", 48: "Tab", 49: "Space", 51: "⌫", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑",
                                      122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        let letters = "ASDFHGZXCV BQWERYT123465=97-80]OU[IP LJ'K;\\,/NM."
        for (i, ch) in letters.enumerated() where ch != " " { m[CGKeyCode(i)] = String(ch) }
        return m
    }()
}

enum Actions {
    static func perform(_ s: Slot) {
        if s.action != .macDinh && s.action != .khongGi { Log.detail("CHẠY", s.action == .phimTat ? "phím tắt \(Shortcut(s.param)?.text ?? "?")" : s.action.title) }
        switch s.action {
        case .macDinh, .khongGi: return
        case .copy: key(8, .maskCommand)
        case .dan: key(9, .maskCommand)
        case .cat: key(7, .maskCommand)
        case .chonHet: key(0, .maskCommand)
        case .hoanTac: key(6, .maskCommand)
        case .lamLai: key(6, [.maskCommand, .maskShift])
        case .missionControl: openApp("/System/Applications/Mission Control.app")
        // Phím mũi tên mang cờ fn – đúng như phím tắt mặc định macOS (⌃← / ⌃→ / ⌃↓)
        case .manTrai: key(123, [.maskControl, .maskSecondaryFn])
        case .manPhai: key(124, [.maskControl, .maskSecondaryFn])
        case .appExpose: key(125, [.maskControl, .maskSecondaryFn])
        case .manHinhNen: key(103, [.maskSecondaryFn])             // F11
        case .ungDung: openApp("/System/Applications/Apps.app")
        case .chuyenApp: key(48, .maskCommand)
        case .anApp: key(4, .maskCommand)
        case .thuNho: key(46, .maskCommand)
        case .phongTo: key(3, [.maskControl, .maskCommand])
        case .quayLai: key(33, .maskCommand)
        case .diTiep: key(30, .maskCommand)
        case .tabMoi: key(17, .maskCommand)
        case .dongTab: key(13, .maskCommand)
        case .moLaiTab: key(17, [.maskCommand, .maskShift])
        case .taiLai: key(15, .maskCommand)
        case .tabTruoc: key(48, [.maskControl, .maskShift])
        case .tabSau: key(48, .maskControl)
        case .chupVung: key(21, [.maskCommand, .maskShift])
        case .spotlight: key(49, .maskCommand)
        case .khoaMan: key(12, [.maskControl, .maskCommand])
        case .phatDung: media(16)
        case .tangAm: media(0)
        case .giamAm: media(1)
        case .moThuMuc: openFolder(s.param)
        case .moApp: openApp(s.param)
        case .moWeb:
            var u = s.param.trimmingCharacters(in: .whitespaces)
            if !u.isEmpty && !u.contains("://") { u = "https://" + u }
            if let url = URL(string: u), !u.isEmpty { NSWorkspace.shared.open(url) } else { Log.info("CHẠY", "địa chỉ web không hợp lệ: \(s.param)"); NSSound.beep() }
        case .phimTat:
            if let k = Shortcut(s.param) { key(k.code, k.flags) } else { Log.info("CHẠY", "phím tắt tự chọn chưa ghi"); NSSound.beep() }
        }
        if Settings.shared.hud { HUD.show(s.action == .phimTat ? (Shortcut(s.param)?.text ?? "Phím tắt") : s.action.title) }
    }

    static func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: ScrollEngine.marker)
            e.post(tap: .cghidEventTap)
        }
    }

    /// Phím đa phương tiện (NX_KEYTYPE: 0 tăng âm, 1 giảm âm, 16 phát/dừng)
    static func media(_ k: Int) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (k << 16) | ((down ? 0xA : 0xB) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                               context: nil, subtype: 8, data1: data1, data2: -1)?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static func openApp(_ path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { Log.info("CHẠY", "không thấy app: \(path.isEmpty ? "(chưa chọn)" : path)"); NSSound.beep(); return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }

    /// Mở thư mục ở luồng phụ: NSWorkspace.open ổ ngoài từng treo cả app (03/11)
    static func openFolder(_ path: String) {
        DispatchQueue.global().async {
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
                Log.info("CHẠY", "không thấy thư mục: \(path.isEmpty ? "(chưa chọn)" : path) – ổ chưa cắm?")
                DispatchQueue.main.async { NSSound.beep() }   // ổ chưa cắm
                return
            }
            // Nhờ Finder mở bằng đường dẫn dạng CHỮ (HFS "TênỔ:thư mục:…"). Đưa POSIX file / mở trực tiếp thì macOS
            // đòi cấp quyền sandbox cho ổ ngoài và kẹt mãi (03/11)
            var hfs: String
            if path.hasPrefix("/Volumes/") { hfs = String(path.dropFirst("/Volumes/".count)) }
            else { hfs = FileManager.default.displayName(atPath: "/") + path }
            hfs = hfs.replacingOccurrences(of: ":", with: "\u{0}").replacingOccurrences(of: "/", with: ":")
                .replacingOccurrences(of: "\u{0}", with: "/")
            if !hfs.contains(":") { hfs += ":" }
            let esc = hfs.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", "tell application \"Finder\"", "-e", "activate", "-e", "open item \"\(esc)\"", "-e", "end tell"]
            try? p.run()
        }
    }
}

/// Ô chữ nhỏ giữa màn hình khi chức năng chạy, tự tắt sau 0,6 giây
enum HUD {
    private static var panel: NSPanel?
    private static var label: NSTextField?
    private static var work: DispatchWorkItem?

    static func show(_ text: String) {
        DispatchQueue.main.async {
            if panel == nil {
                let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 52), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
                p.level = .statusBar; p.isOpaque = false; p.backgroundColor = .clear; p.ignoresMouseEvents = true
                p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
                let v = NSVisualEffectView(frame: p.contentView!.bounds)
                v.material = .hudWindow; v.state = .active; v.wantsLayer = true; v.layer?.cornerRadius = 16; v.autoresizingMask = [.width, .height]
                let l = NSTextField(labelWithString: "")
                l.font = .systemFont(ofSize: 17, weight: .bold); l.textColor = .labelColor; l.alignment = .center
                l.frame = v.bounds.insetBy(dx: 12, dy: 14); l.autoresizingMask = [.width, .height]
                v.addSubview(l); p.contentView = v
                panel = p; label = l
            }
            guard let p = panel, let l = label else { return }
            l.stringValue = text
            let w = max(160, l.intrinsicContentSize.width + 48)
            let scr = NSScreen.main?.frame ?? .zero
            p.setFrame(NSRect(x: scr.midX - w / 2, y: scr.minY + scr.height * 0.22, width: w, height: 52), display: true)
            p.alphaValue = 1; p.orderFrontRegardless()
            work?.cancel()
            let wk = DispatchWorkItem { NSAnimationContext.runAnimationGroup { $0.duration = 0.2; p.animator().alphaValue = 0 } completionHandler: { p.orderOut(nil) } }
            work = wk
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: wk)
        }
    }
}

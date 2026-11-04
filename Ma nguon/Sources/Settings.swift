// Cài đặt của DuckMouse (lưu UserDefaults vn.vduck.DuckMouse)
import Foundation
import SwiftUI

struct TestResult: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var mouse: String
    var connection: String
    var hz: Double
    var avgMS: Double
    var jitterMS: Double
    var p95MS: Double
    var gaps: Int
    var samples: Int
    // thêm 04/11 (bản cũ không có → nil)
    var buttonsOK: Int? = nil
    var buttonsTotal: Int? = nil
    var chatter: Int? = nil
    var wheelUp: Int? = nil
    var wheelDown: Int? = nil
    var wrongDir: Int? = nil
}

/// Hướng cử chỉ: click = ấn nhả; còn lại = giữ rồi kéo
enum Dir: String, CaseIterable { case click, trai, phai, len, xuong
    var title: String { ["click": "Click", "trai": "← Kéo trái", "phai": "→ Kéo phải", "len": "↑ Kéo lên", "xuong": "↓ Kéo xuống"][rawValue]! }
}

final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    // Cuộn mượt (mặc định giống Mos)
    @Published var scrollEnabled: Bool { didSet { d.set(scrollEnabled, forKey: "scrollEnabled") } }
    @Published var smooth: Bool { didSet { d.set(smooth, forKey: "smooth") } }
    @Published var reverse: Bool { didSet { d.set(reverse, forKey: "reverse") } }
    @Published var step: Double { didSet { d.set(step, forKey: "step") } }
    @Published var speed: Double { didSet { d.set(speed, forKey: "speed") } }
    @Published var duration: Double { didSet { d.set(duration, forKey: "duration") } }

    // Gán chức năng: khoá "3-click", "4-trai"… (3 = giữa, 4 = hông sau, 5 = hông trước, 6+ = nút anh thêm)
    @Published var buttonsEnabled: Bool { didSet { d.set(buttonsEnabled, forKey: "buttonsEnabled") } }
    @Published var slots: [String: Slot] { didSet { saveJSON(slots, "slots") } }
    @Published var waits: [String: Double] { didSet { saveJSON(waits, "waits") } }     // giữ bao lâu rồi mới tính kéo, theo nút
    @Published var dragDistance: Double { didSet { d.set(dragDistance, forKey: "dragDistance") } }
    @Published var extraButtons: [String: String] { didSet { saveJSON(extraButtons, "extraButtons") } }   // nút 6+ anh thêm → tên
    @Published var hud: Bool { didSet { d.set(hud, forKey: "hud") } }
    @Published var welcomeShown: Bool { didSet { d.set(welcomeShown, forKey: "welcomeShown") } }

    @Published var testHistory: [TestResult] { didSet { saveJSON(testHistory, "testHistory") } }

    static let defaultStep = 33.6, defaultSpeed = 2.7, defaultDuration = 4.35
    static let baseButtons: [(Int, String)] = [(3, "Bánh xe"), (4, "Hông sau"), (5, "Hông trước")]

    private init() {
        d.register(defaults: ["scrollEnabled": true, "smooth": true, "reverse": false, "step": Self.defaultStep,
                              "speed": Self.defaultSpeed, "duration": Self.defaultDuration, "buttonsEnabled": true,
                              "dragDistance": 80.0, "hud": true, "welcomeShown": false])
        scrollEnabled = d.bool(forKey: "scrollEnabled")
        smooth = d.bool(forKey: "smooth")
        reverse = d.bool(forKey: "reverse")
        step = d.double(forKey: "step")
        speed = d.double(forKey: "speed")
        duration = d.double(forKey: "duration")
        buttonsEnabled = d.bool(forKey: "buttonsEnabled")
        dragDistance = d.double(forKey: "dragDistance")
        hud = d.bool(forKey: "hud")
        welcomeShown = d.bool(forKey: "welcomeShown")
        waits = Self.loadJSON(d, "waits") ?? ["3": 0.2, "4": 0.1, "5": 0.1]
        extraButtons = Self.loadJSON(d, "extraButtons") ?? [:]
        testHistory = Self.loadJSON(d, "testHistory") ?? []
        slots = Self.loadJSON(d, "slots") ?? Self.migrate(d)
        if d.data(forKey: "slots") == nil { saveJSON(slots, "slots") }       // ghi ngay bản chuyển đổi, lần sau không tính lại
    }

    /// Chuyển cài đặt cũ (trước 04/11: buttonMap / gestureMap / backGestureMap) sang 15 ô; máy mới dùng bộ gợi ý mặc định
    private static func migrate(_ d: UserDefaults) -> [String: Slot] {
        // máy đã dùng bản cũ thì lấy thư mục / app cũ; người dùng mới: thư mục Tải về + mở Ứng dụng
        let folder = d.string(forKey: "dragLeftFolder") ?? (NSHomeDirectory() + "/Downloads")
        let app = d.string(forKey: "quickApp")
        func slot(_ raw: String) -> Slot? {
            guard let a = ButtonAction(rawValue: raw) else { return nil }
            return Slot(action: a, param: a == .moThuMuc ? folder : a == .moApp ? (app ?? "") : "")
        }
        var s: [String: Slot] = [
            "3-click": Slot(action: .missionControl),
            "3-trai": Slot(action: .manTrai), "3-phai": Slot(action: .manPhai),
            "3-len": Slot(action: .moThuMuc, param: folder), "3-xuong": app.map { Slot(action: .moApp, param: $0) } ?? Slot(action: .ungDung),
            "4-trai": Slot(action: .copy), "4-phai": Slot(action: .dan), "4-len": Slot(action: .chonHet), "4-xuong": Slot(action: .cat),
            "5-trai": Slot(action: .hoanTac), "5-phai": Slot(action: .lamLai), "5-len": Slot(action: .chupVung), "5-xuong": Slot(action: .dongTab),
        ]
        if let old: [[String]] = loadJSON(d, "buttonMap") {
            for p in old where p.count == 2 { if let v = slot(p[1]) { s[p[0] + "-click"] = v } }
        }
        for (b, key) in [("3", "gestureMap"), ("4", "backGestureMap")] {
            if let g: [String: String] = loadJSON(d, key) { for (dir, raw) in g { if let v = slot(raw) { s[b + "-" + dir] = v } } }
        }
        return s
    }

    func slot(_ b: Int, _ dir: Dir) -> Slot { slots["\(b)-\(dir.rawValue)"] ?? .none }
    func setSlot(_ b: Int, _ dir: Dir, _ s: Slot) { slots["\(b)-\(dir.rawValue)"] = s }
    func wait(_ b: Int) -> Double { waits[String(b)] ?? 0.15 }
    func hasGesture(_ b: Int) -> Bool { [Dir.trai, .phai, .len, .xuong].contains { slot(b, $0).action != .macDinh } }
    /// Nút gán được: 3 nút gốc + nút anh thêm
    var mappableButtons: [(Int, String)] {
        Self.baseButtons + extraButtons.compactMap { k, v in Int(k).map { ($0, v) } }.sorted { $0.0 < $1.0 }
    }
    func buttonName(_ b: Int) -> String { mappableButtons.first { $0.0 == b }?.1 ?? "Nút \(b)" }

    func resetScroll() { step = Self.defaultStep; speed = Self.defaultSpeed; duration = Self.defaultDuration }

    var firstLaunchDone: Bool {
        get { d.bool(forKey: "firstLaunchDone") }
        set { d.set(newValue, forKey: "firstLaunchDone") }
    }

    private func saveJSON<T: Encodable>(_ v: T, _ key: String) {
        if let data = try? JSONEncoder().encode(v) { d.set(data, forKey: key) }
    }
    private static func loadJSON<T: Decodable>(_ d: UserDefaults, _ key: String) -> T? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

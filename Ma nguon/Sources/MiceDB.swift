// Danh sách thông số chuột (300 mẫu tra 04/11/2026, file mice.json trong app) + chuột anh tự chọn / nhập tay.
// Nhận chuột 3 bước: khớp mã (Bluetooth / USB) → khớp tên → hỏi người dùng chọn.
import Foundation

struct SpecButton: Hashable {
    let name: String, kind: String, signal: String     // signal: hid / none / software / keyboard / touch / unknown
    var sends: Bool { signal == "hid" }
}

struct MouseSpec: Identifiable, Hashable {
    var id: String { brand + " " + model }
    var brand = "", model = "", group = "", dpi = "", weight = "", connection = "", battery = ""
    var buttons = "", sensor = "", polling = "", source = "", note = ""
    var silent = false
    var layout: [SpecButton] = []
    var btNames: [String] = [], btIds: [String] = []
    var usb: [(id: String, shared: Bool)] = []
    var userMade = false

    static func == (a: MouseSpec, b: MouseSpec) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
    var name: String { brand + " " + model }
    /// Nút gửi được sang máy (ngoài trái/phải)
    var mappable: [SpecButton] { layout.filter { $0.sends && !["left", "right"].contains($0.kind) } }

    init() {}
    init(_ d: [String: Any], userMade: Bool = false) {
        func s(_ k: String) -> String {
            switch d[k] {
            case let v as String: return v
            case let v as NSNumber: return v.stringValue.replacingOccurrences(of: ".", with: ",")
            case let v as [Any]: return v.map { "\($0)" }.joined(separator: " · ")
            default: return "hãng không công bố"
            }
        }
        brand = s("brand"); model = s("model"); group = s("group"); dpi = s("dpi"); connection = s("connection")
        battery = s("battery"); sensor = s("sensor"); polling = s("polling_hz"); note = d["note"] as? String ?? ""
        let w = s("weight_g"); weight = d["weight_g"] is NSNumber ? w + " g" : w
        buttons = s("buttons"); silent = d["silent"] as? Bool ?? false
        source = (d["sources"] as? [String: Any])?["specs"] as? String ?? ""
        let lay = (d["layout"] as? [String: Any])?["buttons"] as? [[String: Any]] ?? []
        layout = lay.map { SpecButton(name: $0["name"] as? String ?? "?", kind: $0["kind"] as? String ?? "other", signal: $0["signal"] as? String ?? "unknown") }
        let m = d["match"] as? [String: Any] ?? [:]
        btNames = m["bt_names"] as? [String] ?? []
        btIds = (m["bt_ids"] as? [String] ?? []).map { $0.uppercased() }
        usb = (m["usb_ids"] as? [[String: Any]] ?? []).compactMap { u in
            (u["id"] as? String).map { ($0.uppercased(), u["shared"] as? Bool ?? false) } }
        self.userMade = userMade
    }
    var dict: [String: Any] {
        ["brand": brand, "model": model, "group": group, "dpi": dpi, "weight_g": weight, "connection": connection,
         "battery": battery, "buttons": buttons, "sensor": sensor, "polling_hz": polling, "silent": silent, "note": note,
         "layout": ["buttons": layout.map { ["name": $0.name, "kind": $0.kind, "signal": $0.signal] }],
         "match": ["bt_names": btNames, "bt_ids": btIds, "usb_ids": usb.map { ["id": $0.id, "shared": $0.shared] }]]
    }
}

enum MouseMatch: Equatable {
    case exact(MouseSpec, how: String)          // how: "mã Bluetooth" / "mã USB" / "tên" / "lựa chọn của bạn"
    case candidates([MouseSpec])                // mã dùng chung nhiều chuột → hỏi
    case unknown
    var spec: MouseSpec? { if case .exact(let s, _) = self { return s }; return nil }
}

final class MiceDB: ObservableObject {
    static let shared = MiceDB()
    private(set) var builtIn: [MouseSpec] = []
    @Published private(set) var custom: [MouseSpec] = []
    @Published private(set) var picks: [String: String] = [:]      // khoá thiết bị → id thông số
    @Published private(set) var names: [String: String] = [:]      // khoá thiết bị → tên anh đặt

    var all: [MouseSpec] { custom + builtIn }
    private let file: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DuckMouse")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("chuot-cua-toi.json")
    }()

    private init() {
        if let u = Bundle.main.url(forResource: "mice", withExtension: "json"), let d = try? Data(contentsOf: u),
           let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            builtIn = arr.map { MouseSpec($0) }
        }
        if let d = try? Data(contentsOf: file), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            custom = (o["custom"] as? [[String: Any]] ?? []).map { MouseSpec($0, userMade: true) }
            picks = o["picks"] as? [String: String] ?? [:]
            names = o["names"] as? [String: String] ?? [:]
        }
    }

    private func save() {
        let o: [String: Any] = ["custom": custom.map(\.dict), "picks": picks, "names": names]
        if let d = try? JSONSerialization.data(withJSONObject: o, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: file) }
    }

    static func key(_ d: MouseDevice) -> String { d.codeText + "|" + d.product }
    static func norm(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    func match(_ d: MouseDevice) -> MouseMatch {
        if let id = picks[Self.key(d)], let s = all.first(where: { $0.id == id }) { return .exact(s, how: "lựa chọn của bạn") }
        let code = d.codeText
        if d.transport.hasPrefix("Bluetooth") {
            let hit = all.filter { $0.btIds.contains(code) }
            if hit.count == 1 { return .exact(hit[0], how: "mã Bluetooth") }
            if hit.count > 1 { return .candidates(hit) }
        } else {
            let hit = all.filter { $0.usb.contains { $0.id == code } }
            if let s = hit.first(where: { $0.usb.contains { $0.id == code && !$0.shared } }) { return .exact(s, how: "mã USB") }
            if !hit.isEmpty {
                if let n = nameMatch(d.product), hit.contains(n) { return .exact(n, how: "mã USB + tên") }
                // dongle chung mã: chuột Bluetooth đang nối cùng lúc là 1 mẫu trong số này → cùng con chuột
                let others = MouseHID.shared.devices.filter { $0.id != d.id && $0.transport.hasPrefix("Bluetooth") }
                if let same = hit.first(where: { sp in others.contains { o in sp.btIds.contains(o.codeText) || picks[Self.key(o)] == sp.id } }) {
                    return .exact(same, how: "cùng chuột đang nối Bluetooth")
                }
                return .candidates(hit)
            }
        }
        if let s = nameMatch(d.product) { return .exact(s, how: "tên") }
        return .unknown
    }

    /// Khớp theo tên (chuột Bluetooth thường báo đúng tên mẫu)
    func nameMatch(_ product: String) -> MouseSpec? {
        let p = Self.norm(product)
        guard p.count >= 4, !["usbreceiver", "24greceiver", "usbopticalmouse", "wirelessmouse", "bt50mouse", "usbmouse", "mouse"].contains(p) else { return nil }
        let hits = all.filter { s in
            (s.btNames.map(Self.norm) + [Self.norm(s.model), Self.norm(s.name)]).contains { n in n.count >= 4 && (n == p || p.contains(n) || n.contains(p)) }
        }
        return hits.count == 1 ? hits[0] : hits.first { Self.norm($0.name) == p || $0.btNames.map(Self.norm).contains(p) }
    }

    func spec(for d: MouseDevice) -> MouseSpec? { match(d).spec }

    /// Chuột chính: vừa rê; chưa rê thì ưu tiên chuột nhận chắc chắn (Bluetooth trước dongle) – dùng chung mọi màn
    func activeDevice() -> MouseDevice? {
        let h = MouseHID.shared
        if let d = h.devices.first(where: { $0.id == h.lastActive }) { return d }
        return h.devices.sorted { a, b in
            let ea = match(a).spec != nil, eb = match(b).spec != nil
            if ea != eb { return ea }
            return a.transport.hasPrefix("Bluetooth") && !b.transport.hasPrefix("Bluetooth")
        }.first
    }
    func displayName(_ d: MouseDevice) -> String { names[Self.key(d)] ?? spec(for: d)?.name ?? (d.product.isEmpty ? "Chuột không tên" : d.product) }

    func pick(_ s: MouseSpec, for d: MouseDevice) { picks[Self.key(d)] = s.id; save() }
    func forget(_ d: MouseDevice) { picks[Self.key(d)] = nil; names[Self.key(d)] = nil; save() }
    func rename(_ d: MouseDevice, _ n: String) { names[Self.key(d)] = n.isEmpty ? nil : n; save() }

    /// Thêm / sửa chuột nhập tay; ghi luôn mã thật của thiết bị để lần sau tự nhận
    func saveCustom(_ s: MouseSpec, for d: MouseDevice?) {
        var s = s; s.userMade = true
        if let d {
            if d.transport.hasPrefix("Bluetooth") { if !s.btIds.contains(d.codeText) { s.btIds.append(d.codeText) } }
            else if !s.usb.contains(where: { $0.id == d.codeText }) { s.usb.append((d.codeText, false)) }
            if !d.product.isEmpty && !s.btNames.contains(d.product) { s.btNames.append(d.product) }
        }
        custom.removeAll { $0.id == s.id }
        custom.insert(s, at: 0)
        if let d { picks[Self.key(d)] = s.id }
        save()
    }

    func search(_ q: String) -> [MouseSpec] {
        let n = Self.norm(q)
        return n.isEmpty ? all : all.filter { Self.norm($0.name).contains(n) }
    }
}

/// Chuột Bluetooth đã từng ghép với máy (kể cả đang tắt) – đọc từ system_profiler, không cần thêm quyền
final class PairedMice: ObservableObject {
    static let shared = PairedMice()
    struct Item: Identifiable, Hashable { let name: String, address: String, connected: Bool; var id: String { address } }
    @Published private(set) var items: [Item] = []
    @Published private(set) var scanning = false

    func refresh() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global().async {
            let p = Process(), pipe = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPBluetoothDataType", "-json"]
            p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            var out: [Item] = []
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let root = (o["SPBluetoothDataType"] as? [[String: Any]])?.first {
                    for (k, conn) in [("device_connected", true), ("device_not_connected", false)] {
                        for entry in root[k] as? [[String: Any]] ?? [] {
                            for (name, v) in entry {
                                guard let v = v as? [String: Any], (v["device_minorType"] as? String ?? "").contains("Mouse") else { continue }
                                out.append(Item(name: name, address: v["device_address"] as? String ?? name, connected: conn))
                            }
                        }
                    }
                }
            }
            DispatchQueue.main.async { self.items = out; self.scanning = false }
        }
    }
}

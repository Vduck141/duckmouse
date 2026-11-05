// Tab "Chuột của tôi": chuột đang nối + đã từng ghép, nhận chuột từ danh sách 300 mẫu, chọn / nhập tay chuột lạ
import SwiftUI
import AppKit

/// Ảnh chuột minh hoạ (tab Gán chức năng)
enum MouseArt {
    static let image: NSImage? = Bundle.main.url(forResource: "chuot", withExtension: "png").flatMap { NSImage(contentsOf: $0) }
}

struct MyMouseView: View {
    @EnvironmentObject var hid: MouseHID
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var db: MiceDB
    @EnvironmentObject var paired: PairedMice
    @State private var pickFor: MouseDevice?
    @State private var editFor: EditTarget?

    var active: MouseDevice? { _ = hid.devices; return db.activeDevice() }

    var body: some View {
        Screen(title: "Chuột của tôi", sub: "App tự nhận chuột vừa nối – cáp, dongle hay Bluetooth.") {
            if let err = hid.openError { Banner(icon: "hand.raised", color: T.warn, text: err, button: "Cấp quyền") { model.requestListen() } }
            if let d = active { hero(d) } else {
                DMCard(title: "Chưa thấy chuột") {
                    Text("Cắm dongle hoặc bật Bluetooth của chuột. App tự nhận khi chuột nối vào.").foregroundStyle(T.ink3)
                }
            }
            radarCard
            if let d = active {
                switch db.match(d) {
                case .exact(let s, _): specCards(d, s)
                case .candidates(let list): askCard(d, list)
                case .unknown: unknownCard(d)
                }
            }
        }
        .onAppear { paired.refresh() }
        .sheet(item: $pickFor) { d in PickSheet(device: d) }
        .sheet(item: $editFor) { t in EditSheet(target: t) }
    }

    // MARK: thẻ đầu
    private func hero(_ d: MouseDevice) -> some View {
        let m = db.match(d), s = m.spec
        let same = hid.devices.filter { $0.id != d.id && db.spec(for: $0) != nil && db.spec(for: $0) == s }
        return DMCard {
            HStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Chip(text: "● Đang dùng", kind: .ok)
                        switch m {
                        case .exact(_, let how): Chip(text: "Nhận theo \(how)", kind: .brand)
                        case .candidates: Chip(text: "Cần bạn chọn", kind: .warn)
                        case .unknown: Chip(text: "Chưa có trong danh sách", kind: .warn)
                        }
                    }
                    Text(d.displayName).font(.system(size: 24, weight: .heavy)).tracking(-1)
                    Text(same.isEmpty ? "\(d.connection) · \(d.codeText)" : "Đang nối 2 đường: \(d.connection) + \(same[0].connection) – gộp thành 1 con chuột")
                        .font(.system(size: 13)).foregroundStyle(T.ink3)
                    HStack(spacing: 10) {
                        Tile(label: "Kết nối", value: d.connection)
                        Tile(label: "Nút gửi được", value: s.map { "\($0.layout.filter(\.sends).count) nút" } ?? (d.declaredButtons > 0 ? "\(d.declaredButtons) nút" : "—"),
                             foot: s == nil ? "theo chuột tự khai" : "theo thông số hãng")
                        Tile(label: "Tần số đo", value: hid.liveHz[d.id].map { "\(Int($0.rounded())) Hz" } ?? "— Hz", foot: "rê chuột để đo")
                    }
                    .padding(.top, 6)
                }
            }
        }
    }

    // MARK: radar dò chuột (mẫu 186)
    private var radarCard: some View {
        DMCard(title: "Dò chuột", sub: "· chuột đang nối và đã từng ghép Bluetooth") {
            HStack(alignment: .center, spacing: 20) {
                Radar(dots: radarDots, scanning: paired.scanning)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(hid.devices) { d in DeviceRow(device: d) }
                    ForEach(pairedOff) { p in
                        HStack(spacing: 12) {
                            Image(systemName: "computermouse").frame(width: 34, height: 34).background(T.surface, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.line))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(db.nameMatch(p.name)?.name ?? p.name).font(.system(size: 13.5, weight: .bold))
                                Text("Đã ghép Bluetooth · đang tắt hoặc ở xa").font(.system(size: 12)).foregroundStyle(T.ink3)
                            }
                            Spacer()
                            Chip(text: "Chưa nối")
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(T.s2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    HStack(spacing: 10) {
                        Button(paired.scanning ? "Đang dò…" : "Dò lại") { paired.refresh() }.buttonStyle(DMButton(kind: .ink)).disabled(paired.scanning)
                        Text("Mã chuột tự khai đôi khi không đúng (dongle MS01 khai có lăn ngang) – kết quả Test là chuẩn.")
                            .font(.system(size: 12)).foregroundStyle(T.ink3)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    private var pairedOff: [PairedMice.Item] {
        paired.items.filter { p in !p.connected && !hid.devices.contains { $0.product == p.name } }
    }
    private var radarDots: [Radar.Dot] {
        hid.devices.map { Radar.Dot(id: "\($0.id)", label: short($0), on: true, icon: $0.transport.hasPrefix("Bluetooth") ? "computermouse.fill" : "cable.connector") }
        + pairedOff.map { Radar.Dot(id: $0.address, label: String((db.nameMatch($0.name)?.model ?? $0.name.components(separatedBy: " ").last ?? $0.name).prefix(10)), on: false, icon: "computermouse") }
    }
    private func short(_ d: MouseDevice) -> String {
        let base = d.transport.hasPrefix("Bluetooth") ? (db.spec(for: d)?.model.components(separatedBy: " ").last ?? d.product) : "Dongle"
        return String(base.prefix(10))
    }

    // MARK: thông số
    private func specCards(_ d: MouseDevice, _ s: MouseSpec) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                DMCard(title: "Máy tự đọc được") {
                    VStack(spacing: 0) {
                        KV(k: "Tên thiết bị", v: d.product.isEmpty ? "—" : d.product)
                        KV(k: "Mã hãng : sản phẩm", v: d.codeText)
                        KV(k: "Nút khai báo", v: d.declaredButtons > 0 ? "\(d.declaredButtons) nút" : "chưa đọc được (cần quyền Theo dõi đầu vào)")
                        KV(k: "Lăn ngang khai báo", v: d.declaresHScroll ? "Có" : "Không")
                        KV(k: "Phiên bản", v: d.versionText)
                    }
                }
                DMCard(title: "Thông số hãng", sub: s.userMade ? "· bạn nhập" : nil) {
                    VStack(spacing: 0) {
                        KV(k: "DPI", v: s.dpi)
                        KV(k: "Cân nặng", v: s.weight)
                        KV(k: "Kết nối", v: s.connection)
                        KV(k: "Pin", v: s.battery)
                        KV(k: "Cảm biến", v: s.sensor)
                        KV(k: "Bấm êm (silent)", v: s.silent ? "Có" : "Không")
                    }
                }
            }
            DMCard(title: "Các nút", sub: "· \(s.layout.count) nút vật lý") {
                FlowRows(items: s.layout.map { b in (b.name, b.sends ? "" : signalText(b.signal), b.sends) })
                HStack(spacing: 8) {
                    if !s.source.isEmpty, let u = URL(string: s.source) { Link("Nguồn thông số", destination: u).font(.system(size: 12.5, weight: .semibold)) }
                    Spacer()
                    Button("Không phải chuột này?") { pickFor = d }.buttonStyle(DMButton(kind: .ghost))
                    Button("Sửa thông số") { editFor = EditTarget(device: d, spec: s) }.buttonStyle(DMButton(kind: .ghost))
                }
            }
        }
    }

    private func askCard(_ d: MouseDevice, _ list: [MouseSpec]) -> some View {
        DMCard(title: "Chuột của bạn là con nào?") {
            Text("Mã \(d.codeText) (\(d.connection)) dùng chung cho \(list.count) mẫu chuột, app không tự biết đúng con nào. Chọn 1 lần, app nhớ cho lần sau.")
                .font(.system(size: 13)).foregroundStyle(T.ink2)
            ForEach(list) { s in
                Button { db.pick(s, for: d) } label: {
                    HStack { Text(s.name).font(.system(size: 13.5, weight: .bold)); Spacer(); Text(s.group).font(.system(size: 12)).foregroundStyle(T.ink3) }
                        .padding(12).background(T.s2, in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack { Button("Không có trong đây – tìm trong \(db.all.count) mẫu") { pickFor = d }.buttonStyle(DMButton(kind: .ghost))
                Button("Nhập tay") { editFor = EditTarget(device: d, spec: nil) }.buttonStyle(DMButton(kind: .ghost)) }
        }
    }

    private func unknownCard(_ d: MouseDevice) -> some View {
        DMCard(title: "Chuột lạ") {
            DeviceRow(device: d)
            Text("Chuột chưa có trong danh sách – máy chỉ đọc được tên, mã, số nút. DPI, cân nặng, pin… chuột không gửi sang máy.")
                .font(.system(size: 13)).foregroundStyle(T.ink3)
            HStack(spacing: 8) {
                Button("Chọn trong \(db.all.count) mẫu") { pickFor = d }.buttonStyle(DMButton(kind: .brand))
                Button("Nhập tay") { editFor = EditTarget(device: d, spec: nil) }.buttonStyle(DMButton(kind: .ghost))
            }
        }
    }
}

func signalText(_ s: String) -> String {
    ["hid": "gửi được", "none": "chuột tự xử lý", "software": "cần phần mềm hãng", "keyboard": "gửi phím bàn phím", "touch": "cảm ứng", "unknown": "chưa rõ"][s] ?? s
}

/// Hàng chip nút (tự xuống dòng)
struct FlowRows: View {
    let items: [(String, String, Bool)]   // tên, chữ phụ (trống = không hiện), gửi sang máy?
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Circle().fill(items[i].2 ? T.mint : T.line2).frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(items[i].0).font(.system(size: 13, weight: .bold))
                        if !items[i].1.isEmpty { Text(items[i].1).font(.system(size: 11.5)).foregroundStyle(items[i].2 ? T.mint : T.ink3) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(10).background(T.s2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

/// 1 dòng chuột đang nối
struct DeviceRow: View {
    let device: MouseDevice
    @EnvironmentObject var db: MiceDB
    var body: some View {
        let m = db.match(device)
        HStack(spacing: 12) {
            Image(systemName: device.transport.hasPrefix("Bluetooth") ? "computermouse.fill" : "cable.connector")
                .frame(width: 34, height: 34).background(T.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(T.line))
            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName).font(.system(size: 13.5, weight: .bold))
                Text("\(device.connection) · \(device.codeText)" + (device.declaredButtons > 0 ? " · \(device.declaredButtons) nút khai báo" : "")).font(.system(size: 12)).foregroundStyle(T.ink3)
            }
            Spacer()
            switch m {
            case .exact: Chip(text: "Đã biết", kind: .ok)
            case .candidates: Chip(text: "Cần chọn", kind: .warn)
            case .unknown: Chip(text: "Chuột lạ", kind: .warn)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(T.s2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Radar xanh: tia quét 1,6 giây/vòng, sóng lan, chấm thiết bị bật lên khi tia đi qua (mẫu 186)
struct Radar: View {
    struct Dot: Identifiable { let id: String, label: String, on: Bool, icon: String }
    let dots: [Dot]
    let scanning: Bool
    @State private var start = Date()
    @State private var sweep = true

    var body: some View {
        TimelineView(.animation(paused: !sweep)) { tl in
            let t = tl.date.timeIntervalSince(start)
            let angle = (t / 1.6).truncatingRemainder(dividingBy: 1) * 360
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 0.07, green: 0.21, blue: 0.17), Color(red: 0.03, green: 0.10, blue: 0.08)], center: .center, startRadius: 0, endRadius: 100))
                ForEach([0.3, 0.6, 0.99], id: \.self) { r in Circle().stroke(Color(red: 0.55, green: 0.91, blue: 0.6).opacity(r > 0.9 ? 0.28 : 0.16), lineWidth: 1).scaleEffect(r) }
                Rectangle().fill(Color(red: 0.55, green: 0.91, blue: 0.6).opacity(0.12)).frame(width: 1)
                Rectangle().fill(Color(red: 0.55, green: 0.91, blue: 0.6).opacity(0.12)).frame(height: 1)
                if sweep {
                    Circle().fill(AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.69),
                                                          .init(color: Color(red: 0.32, green: 0.81, blue: 0.4).opacity(0.38), location: 0.99),
                                                          .init(color: Color(red: 0.7, green: 0.95, blue: 0.73), location: 1)], center: .center))
                        .rotationEffect(.degrees(angle - 90))
                    ForEach(0..<2) { i in
                        let p = ((t + Double(i) * 0.9) / 1.8).truncatingRemainder(dividingBy: 1)
                        Circle().stroke(Color(red: 0.55, green: 0.91, blue: 0.6).opacity(0.6 * (1 - p)), lineWidth: 1.5).frame(width: 34 + 150 * p)
                    }
                }
                RoundedRectangle(cornerRadius: 11).fill(Color(white: 0.97)).frame(width: 36, height: 36)
                    .overlay(Image(systemName: "laptopcomputer").foregroundStyle(.black))
                ForEach(Array(dots.enumerated()), id: \.1.id) { i, d in
                    let a = Double(i) * 2.2 + 0.6, r = 54.0
                    let seen = !sweep || t > 0.35 + Double(i) * 0.5
                    VStack(spacing: 2) {
                        Image(systemName: d.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(d.on ? Color(red: 0.32, green: 0.81, blue: 0.4) : Color(white: 0.53)))
                            .shadow(color: d.on ? Color(red: 0.32, green: 0.81, blue: 0.4).opacity(0.6) : .clear, radius: 9)
                        Text(d.label).font(.system(size: 9.5, weight: .bold)).lineLimit(1).foregroundStyle(Color(red: 0.76, green: 0.98, blue: 0.91))
                    }
                    .offset(x: cos(a) * r, y: sin(a) * r + 6)
                    .scaleEffect(seen ? 1 : 0.3).opacity(seen ? 1 : 0)
                    .animation(.spring(response: 0.45, dampingFraction: 0.55), value: seen)
                }
            }
        }
        .frame(width: 200, height: 200)
        .clipShape(Circle())
        .shadow(color: Color(red: 0.03, green: 0.1, blue: 0.08).opacity(0.6), radius: 16, y: 12)
        .onAppear { restart() }
        .onChange(of: scanning) { _, s in if s { restart() } }
    }
    private func restart() {
        start = Date(); sweep = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { sweep = false }
    }
}

// MARK: chọn chuột trong danh sách

struct PickSheet: View {
    let device: MouseDevice
    @EnvironmentObject var db: MiceDB
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chọn chuột của bạn").font(.system(size: 20, weight: .heavy))
            Text("\(device.product) · \(device.codeText) · \(device.connection)").font(.system(size: 12.5)).foregroundStyle(T.ink3)
            TextField("Tìm tên chuột, ví dụ «M650», «G102»", text: $q).textFieldStyle(.roundedBorder)
            List(db.search(q)) { s in
                Button {
                    db.pick(s, for: device); dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) { Text(s.name).font(.system(size: 13.5, weight: .bold)); Text("\(s.group) · \(s.connection)").font(.system(size: 11.5)).foregroundStyle(T.ink3) }
                        Spacer()
                        if s.userMade { Chip(text: "bạn nhập") }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 320)
            HStack {
                if db.picks[MiceDB.key(device)] != nil { Button("Bỏ chọn (để app tự nhận)") { db.forget(device); dismiss() }.buttonStyle(DMButton(kind: .ghost)) }
                Spacer()
                Button("Đóng") { dismiss() }.buttonStyle(DMButton(kind: .ink))
            }
        }
        .padding(22).frame(width: 520, height: 560)
    }
}

struct EditTarget: Identifiable {
    let device: MouseDevice?
    let spec: MouseSpec?
    var id: String { (device.map(MiceDB.key) ?? "") + (spec?.id ?? "") }
}

/// Nhập tay / sửa thông số – lưu vào danh sách riêng của anh, kèm mã thật của chuột đang nối
struct EditSheet: View {
    let target: EditTarget
    @EnvironmentObject var db: MiceDB
    @Environment(\.dismiss) private var dismiss
    @State private var s = MouseSpec()
    @State private var btnCount = 5
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(target.spec == nil ? "Nhập thông số chuột" : "Sửa thông số").font(.system(size: 20, weight: .heavy))
            Form {
                TextField("Hãng", text: $s.brand)
                TextField("Tên mẫu", text: $s.model)
                TextField("DPI", text: $s.dpi)
                TextField("Cân nặng", text: $s.weight)
                TextField("Kết nối", text: $s.connection)
                TextField("Pin", text: $s.battery)
                TextField("Cảm biến", text: $s.sensor)
                Toggle("Bấm êm (silent)", isOn: $s.silent)
                Stepper("Số nút gửi sang máy: \(btnCount)", value: $btnCount, in: 2...12)
            }
            Text("Lưu xong, lần sau cắm chuột này app tự nhận (app ghi kèm mã \(target.device?.codeText ?? "—")).")
                .font(.system(size: 12)).foregroundStyle(T.ink3)
            HStack {
                Spacer()
                Button("Huỷ") { dismiss() }.buttonStyle(DMButton(kind: .ghost))
                Button("Lưu") {
                    if target.spec == nil || s.layout.filter(\.sends).count != btnCount {
                        let base: [(String, String)] = [("Trái", "left"), ("Phải", "right"), ("Bánh xe (nhấn)", "middle"), ("Hông sau", "back"), ("Hông trước", "forward")]
                        s.layout = (0..<btnCount).map { i in i < base.count ? SpecButton(name: base[i].0, kind: base[i].1, signal: "hid") : SpecButton(name: "Nút \(i + 1)", kind: "extra", signal: "hid") }
                    }
                    s.buttons = "\(btnCount)"
                    if s.brand.isEmpty { s.brand = target.device?.brand ?? "" }
                    if s.model.isEmpty { s.model = target.device?.product ?? "Chuột" }
                    db.saveCustom(s, for: target.device); dismiss()
                }
                .buttonStyle(DMButton(kind: .ink)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 480)
        .onAppear {
            if let sp = target.spec { s = sp; btnCount = max(2, sp.layout.filter(\.sends).count) }
            else { s.brand = target.device?.brand ?? ""; s.model = target.device?.product ?? ""; btnCount = min(12, max(3, target.device?.declaredButtons ?? 5)) }
        }
    }
}

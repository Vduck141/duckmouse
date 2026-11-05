// Tab "Test chuột": 3 bước – rê 10 giây (vòng đo, mẫu 081) → ô thử nút (khoá chức năng, chỉ ghi nhận) → kết quả bằng lời
import SwiftUI
import AppKit

/// 1 nút trong ô thử
struct TestKey: Identifiable, Equatable {
    let id: String          // "b3" (nút IOHID 3) / "wu" "wd" lăn dọc / "wl" "wr" lăn ngang
    var name: String
    var sub: String
    var mapButton: Int?     // nút gán được → số nút
    var expected: Bool      // chuột này phải có (theo danh sách)
    var isNew = false
}

final class TestSession: ObservableObject {
    static let shared = TestSession()
    // bước 1
    @Published var running = false
    @Published var progress = 0.0
    @Published var rate: TestResult?
    @Published var liveHz = 0.0
    @Published var liveGaps = 0
    @Published var livePackets = 0
    private var gaps: [Double] = []
    private var moved = 0.0
    private var device: UInt64?
    // bước 2
    @Published var keys: [TestKey] = []
    @Published var counts: [String: Int] = [:]
    @Published var chatter: [String: Int] = [:]
    @Published var flash: String?
    @Published var lastGesture: String?
    @Published var wrongDir = 0
    @Published var lastSignal: String?          // chuột gửi kiểu phím: "Hông sau ← phím Back (app đã đổi thành nút chuột)"
    private var lastDown: [Int: Double] = [:]
    private var lastWheel: (dir: Int, t: Date)?
    private let key = UUID()
    static let duration = 10_000.0          // 10 giây rê chuột thực tế

    // MARK: bước 1
    func startRate() {
        gaps = []; moved = 0; progress = 0; rate = nil; device = nil; running = true; liveGaps = 0; livePackets = 0
        MouseHID.shared.reportListeners[key] = { [weak self] id, gap in
            guard let self, self.running else { return }
            if self.device == nil { self.device = id }
            guard id == self.device else { return }
            self.gaps.append(gap); self.moved += gap; self.livePackets += 1
            if gap > 30 { self.liveGaps += 1 }
            if self.gaps.count % 20 == 0 { let s = self.gaps.suffix(60).sorted(); self.liveHz = 1000 / s[s.count / 2] }
            self.progress = min(1, self.moved / Self.duration)
            if self.moved >= Self.duration { self.finishRate() }
        }
    }
    func cancelRate() { running = false; MouseHID.shared.reportListeners[key] = nil }
    private func finishRate() {
        cancelRate()
        guard gaps.count >= 20 else { return }
        let s = gaps.sorted(), n = Double(gaps.count)
        let avg = gaps.reduce(0, +) / n
        let sd = (gaps.reduce(0) { $0 + ($1 - avg) * ($1 - avg) } / n).squareRoot()
        let dev = MouseHID.shared.device(device)
        rate = TestResult(mouse: dev?.displayName ?? "?", connection: dev?.connection ?? "?",
                          hz: 1000 / s[s.count / 2], avgMS: avg, jitterMS: sd, p95MS: s[Int(n * 0.95)],
                          gaps: gaps.filter { $0 > 30 }.count, samples: gaps.count)
        liveHz = rate!.hz
    }

    // MARK: bước 2
    /// Dựng danh sách nút theo chuột đang dùng (danh sách 300 mẫu) + nút anh đã thêm
    func buildKeys(for d: MouseDevice?) {
        let spec = d.flatMap { MiceDB.shared.spec(for: $0) }
        let has: (String) -> Bool = { k in spec?.layout.contains { $0.kind == k && $0.sends } ?? false }
        let s = Settings.shared
        var k: [TestKey] = [
            TestKey(id: "b1", name: "Trái", sub: "không gán (giữ click)", mapButton: nil, expected: true),
            TestKey(id: "b2", name: "Phải", sub: "không gán (giữ click)", mapButton: nil, expected: true),
            TestKey(id: "b3", name: "Bánh xe (nhấn)", sub: "giữa", mapButton: 3, expected: spec == nil || has("middle")),
            TestKey(id: "b4", name: "Hông sau", sub: "quay lại", mapButton: 4, expected: spec == nil ? (d?.declaredButtons ?? 5) >= 4 : has("back")),
            TestKey(id: "b5", name: "Hông trước", sub: "chuyển tiếp", mapButton: 5, expected: spec == nil ? (d?.declaredButtons ?? 5) >= 5 : has("forward")),
            TestKey(id: "wu", name: "Lăn lên", sub: "lăn 10 nấc", mapButton: nil, expected: true),
            TestKey(id: "wd", name: "Lăn xuống", sub: "lăn 10 nấc", mapButton: nil, expected: true),
        ]
        let tilt = has("tilt_left") || has("hscroll")
        k.append(TestKey(id: "wl", name: "Lăn ngang trái", sub: tilt ? "nghiêng / bánh ngang" : "chuột này không có", mapButton: nil, expected: tilt))
        k.append(TestKey(id: "wr", name: "Lăn ngang phải", sub: tilt ? "nghiêng / bánh ngang" : "chuột này không có", mapButton: nil, expected: tilt))
        for (b, name) in s.mappableButtons where b > 5 {
            k.append(TestKey(id: "b\(b)", name: name, sub: "nút bạn thêm", mapButton: b, expected: true))
        }
        if let spec {   // nút chuột tự xử lý / cần phần mềm → hiện xám, không cần test
            for b in spec.layout where !b.sends {
                k.append(TestKey(id: "x-" + b.name, name: b.name, sub: signalText(b.signal) + " – không cần test", mapButton: nil, expected: false))
            }
        }
        keys = k
    }

    func attach() {
        let h = MouseHID.shared
        h.buttonListeners[key] = { [weak self] _, b, down, t in
            guard let self, down else { return }
            if let l = self.lastDown[b], t - l < 60 { self.chatter["b\(b)", default: 0] += 1 }   // <60 ms = nhảy đúp
            self.lastDown[b] = t
            self.hit("b\(b)", button: b)
        }
        h.wheelListeners[key] = { [weak self] _, v in
            guard let self else { return }
            let dir = v > 0 ? 1 : -1, now = Date()
            if let l = self.lastWheel, l.dir != dir, now.timeIntervalSince(l.t) < 0.08 { self.wrongDir += 1 }   // nhảy ngược chiều giữa 1 lần lăn
            self.lastWheel = (dir, now)
            for _ in 0..<abs(v) { self.hit(v > 0 ? "wu" : "wd") }
        }
        h.hwheelListeners[key] = { [weak self] _, v in self?.hit(v < 0 ? "wl" : "wr") }
        h.signalListeners[key] = { [weak self] b, text in
            guard let self else { return }
            if let b {
                self.lastSignal = "\(Settings.shared.buttonName(b)): chuột gửi \(text) → app đã đổi thành nút chuột, gán chức năng được"
            } else {
                self.lastSignal = "Chuột gửi \(text) – app chưa tự đổi được kiểu này. Chụp màn hình gửi Duck."
            }
        }
        ButtonEngine.onTest = { [weak self] b, dir in
            guard let self else { return }
            let name = Settings.shared.buttonName(b)
            if dir == .click { self.lastGesture = "Nhận: click \(name.lowercased())"; return }
            let s = Settings.shared.slot(b, dir)
            self.lastGesture = "Nhận: giữ \(name.lowercased()) \(dir.title.lowercased())" + (s.action == .macDinh ? " · chưa gán" : " · sẽ chạy: \(s.action.title)")
        }
    }
    func detach() {
        let h = MouseHID.shared
        h.buttonListeners[key] = nil; h.wheelListeners[key] = nil; h.hwheelListeners[key] = nil; h.signalListeners[key] = nil
        ButtonEngine.onTest = nil; ButtonEngine.testLock = false
    }

    private func hit(_ id: String, button: Int? = nil) {
        if !keys.contains(where: { $0.id == id }), let b = button, b > 5 {        // nút lạ → tự thêm + có thẻ bên Gán chức năng
            Settings.shared.extraButtons[String(b)] = "Nút \(b)"
            keys.insert(TestKey(id: id, name: "Nút \(b)", sub: "mới nhận – đổi tên ở Gán chức năng", mapButton: b, expected: true, isNew: true), at: min(keys.count, 9))
            AppModel.shared.show("Nhận nút mới: Nút \(b) · đã thêm vào Gán chức năng")
        }
        counts[id, default: 0] += 1
        flash = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if self.flash == id { self.flash = nil } }
    }

    func resetKeys() { counts = [:]; chatter = [:]; wrongDir = 0; lastGesture = nil; lastSignal = nil }

    // MARK: kết quả
    var expectedButtons: [TestKey] { keys.filter { $0.id.hasPrefix("b") && $0.expected } }
    var okButtons: Int { expectedButtons.filter { (counts[$0.id] ?? 0) > 0 }.count }
    var totalChatter: Int { chatter.values.reduce(0, +) }
}

struct TestView: View {
    @EnvironmentObject var hid: MouseHID
    @EnvironmentObject var nav: Nav
    @StateObject private var t = TestSession.shared

    var device: MouseDevice? { _ = hid.devices; return MiceDB.shared.activeDevice() }

    var body: some View {
        Screen(title: "Test chuột", sub: "3 bước, khoảng 1 phút. Xong có kết luận bằng lời.") {
            if let err = hid.openError { Banner(icon: "hand.raised", color: T.warn, text: err, button: "Cấp quyền") { AppModel.shared.requestListen() } }
            PillSegment(items: [(0, "1 · Rê chuột" + (t.rate != nil ? " ✓" : "")), (1, "2 · Nút & bánh xe" + (t.okButtons > 0 && t.okButtons == t.expectedButtons.count ? " ✓" : "")), (2, "3 · Kết quả")],
                        selection: $nav.testStep)
            switch nav.testStep {
            case 0: RateStep(t: t, next: { withAnimation(T.spring) { nav.testStep = 1 } })
            case 1: ButtonStep(t: t)
            default: ResultStep(t: t, device: device)
            }
        }
        .onAppear { t.buildKeys(for: device); t.attach() }
        .onDisappear { t.detach() }
        .onChange(of: device?.id) { _, _ in t.buildKeys(for: device) }
    }
}

// MARK: bước 1 – vòng đo

struct RateStep: View {
    @ObservedObject var t: TestSession
    let next: () -> Void
    var body: some View {
        DMCard {
            HStack(spacing: 26) {
                ZStack {
                    Circle().stroke(T.s3, lineWidth: 9)
                    Circle().trim(from: 0, to: t.progress).stroke(t.rate != nil ? T.mint : T.ink, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90)).animation(.linear(duration: 0.2), value: t.progress)
                    if t.rate != nil {
                        Image(systemName: "checkmark").font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 64, height: 64).background(Circle().fill(T.mint))
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        VStack(spacing: 0) {
                            Text("\(Int(t.liveHz.rounded()))").font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            Text("lần / giây").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(T.ink3)
                        }
                    }
                }
                .frame(width: 150, height: 150)
                .animation(T.spring, value: t.rate != nil)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rê chuột liên tục 10 giây").font(.system(size: 18, weight: .heavy))
                    Text("Bấm Bắt đầu rồi vẽ vòng tròn, đưa qua lại. Vòng chạy hết là xong.").foregroundStyle(T.ink2)
                    HStack(spacing: 10) {
                        Tile(label: "Đã rê", value: (t.progress * 10).vn() + " giây")
                        Tile(label: "Khựng", value: "\(t.rate?.gaps ?? t.liveGaps) lần")
                        Tile(label: "Gói tín hiệu", value: "\(t.rate?.samples ?? t.livePackets)")
                    }
                    HStack(spacing: 8) {
                        Button(t.running ? "Đang đo…" : t.rate == nil ? "Bắt đầu đo" : "Đo lại") { t.startRate() }
                            .buttonStyle(DMButton(kind: .ink)).disabled(t.running).accessibilityLabel("Bắt đầu đo tần số")
                        if t.running { Button("Huỷ") { t.cancelRate() }.buttonStyle(DMButton(kind: .ghost)) }
                        if t.rate != nil { Button("Sang bước 2 →", action: next).buttonStyle(DMButton(kind: .brand)) }
                    }
                }
            }
        }
    }
}

// MARK: bước 2 – ô thử nút

struct ButtonStep: View {
    @ObservedObject var t: TestSession
    @EnvironmentObject var nav: Nav
    @State private var inside = false
    var body: some View {
        DMCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Đưa con trỏ vào ô này rồi bấm từng nút").font(.system(size: 16, weight: .heavy))
                        Text("Trong ô chỉ ghi nhận: nút giữa không mở Mission Control, nút hông không lùi trang, giữ + kéo không chạy Copy/Dán, lăn không cuộn trang. Lăn lên 10, xuống 10 nấc.")
                            .font(.system(size: 12.5)).foregroundStyle(T.ink3).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Chip(text: inside ? "🔒 Đang khoá chức năng nút" : "Chưa khoá – đưa con trỏ vào ô", kind: inside ? .brand : .plain)
                }
                if let g = t.lastGesture { Text(g).font(.system(size: 13, weight: .bold)).foregroundStyle(T.ink).transition(.opacity) }
                if let sg = t.lastSignal {
                    Label(sg, systemImage: "keyboard").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(T.warn)
                        .fixedSize(horizontal: false, vertical: true).transition(.opacity)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 8)], spacing: 8) {
                    ForEach(t.keys) { k in keyCell(k) }
                }
            }
            .padding(18)
            .background(inside ? T.brand.opacity(0.07) : T.s2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(inside ? T.brand : T.line2, lineWidth: 2))
            .contentShape(Rectangle())
            .onHover { h in inside = h; ButtonEngine.testLock = h }
            .onDisappear { ButtonEngine.testLock = false }
            .animation(T.ease, value: inside)
            HStack(spacing: 10) {
                Button("Đặt lại") { t.resetKeys() }.buttonStyle(DMButton(kind: .ghost))
                Text("Bấm một nút lạ (nút 6, 7…) trong ô → tự thêm dòng mới và có ngay thẻ bên «Gán chức năng».")
                    .font(.system(size: 12)).foregroundStyle(T.ink3)
                Spacer()
                Button("Xem kết quả →") { withAnimation(T.spring) { nav.testStep = 2 } }.buttonStyle(DMButton(kind: .brand))
            }
        }
    }

    private func keyCell(_ k: TestKey) -> some View {
        let n = t.counts[k.id] ?? 0, isTest = k.id.hasPrefix("b") || k.id.hasPrefix("w")
        let now = t.flash == k.id
        return HStack(spacing: 10) {
            Circle().fill(n > 0 ? T.mint : T.line2).frame(width: 10, height: 10).scaleEffect(now ? 1.6 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(k.name).font(.system(size: 13, weight: .bold))
                Text(k.sub).font(.system(size: 11.5)).foregroundStyle(T.ink3).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                if isTest { Text(k.id.hasPrefix("w") ? "\(n) nấc" : "\(n) lần").font(.system(size: 12, weight: .heavy)).monospacedDigit().foregroundStyle(T.ink3) }
                if let c = t.chatter[k.id], c > 0 { Text("nhảy đúp \(c)").font(.system(size: 11, weight: .bold)).foregroundStyle(T.danger) }
                if let b = k.mapButton {
                    Button("Gán chức năng →") { nav.ganButton = b; withAnimation(T.spring) { nav.tab = .gan } }
                        .buttonStyle(.plain).font(.system(size: 11.5, weight: .heavy)).lineLimit(1).fixedSize()
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(T.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(now ? T.mint : k.isNew ? T.brand : T.line, lineWidth: now || k.isNew ? 2 : 1))
        .scaleEffect(now ? 1.04 : 1)
        .opacity(!k.expected && n == 0 ? 0.45 : 1)
        .animation(T.spring, value: now)
    }
}

// MARK: bước 3 – kết quả bằng lời

struct ResultStep: View {
    @ObservedObject var t: TestSession
    let device: MouseDevice?
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: Nav
    @State private var saved = false

    enum Lv { case g, y, r }
    struct Item { let lv: Lv, title: String, sub: String, value: String, bar: Double?, scale: String, why: String, todo: String? }

    var items: [Item] {
        var out: [Item] = []
        let bt = (t.rate?.connection ?? device?.connection ?? "").hasPrefix("Bluetooth")
        if let r = t.rate {
            let lo = 60.0, good = bt ? 80.0 : 120.0
            let lv: Lv = r.hz >= good ? .g : r.hz >= lo ? .y : .r
            out.append(Item(lv: lv, title: "Độ mượt con trỏ", sub: "Tần số báo", value: "\(Int(r.hz.rounded())) lần/s", bar: min(1, r.hz / (bt ? 133 : 1000)),
                            scale: bt ? "chuẩn Bluetooth 60–133" : "chuẩn dongle / cáp 125–1000",
                            why: "Chuột báo vị trí \(Int(r.hz.rounded())) lần mỗi giây. Càng cao con trỏ càng mượt; dưới 60 sẽ thấy giật.",
                            todo: lv == .g ? nil : "Sạc pin, để chuột gần máy" + (bt ? ", hoặc dùng dongle (thường nhanh gấp đôi Bluetooth)." : ", cắm dongle cổng khác (tránh hub USB 3).")))
            let jOK = bt ? 4.0 : 2.0
            let jl: Lv = r.jitterMS < jOK ? .g : r.jitterMS < jOK * 2.5 ? .y : .r
            out.append(Item(lv: jl, title: "Độ đều", sub: "Độ lệch nhịp", value: r.jitterMS.vn() + " ms", bar: max(0.05, 1 - r.jitterMS / (jOK * 3)),
                            scale: "tốt: dưới \(jOK.vn(0)) ms", why: "Các lần báo cách nhau có đều không. Đều thì kéo thẳng không răng cưa.",
                            todo: jl == .g ? nil : "Tắt bớt thiết bị không dây gần đó, thử kết nối khác."))
            let gl: Lv = r.gaps <= 3 ? .g : r.gaps <= 10 ? .y : .r
            out.append(Item(lv: gl, title: "Khựng", sub: "mất tín hiệu >30 ms", value: "\(r.gaps) lần", bar: max(0.05, 1 - Double(r.gaps) / 15),
                            scale: "lỗi khi trên 10", why: r.gaps == 0 ? "Không lần nào con trỏ đứng hình." : "Có \(r.gaps) lúc con trỏ đứng hình rất ngắn trong 10 giây.",
                            todo: gl == .g ? nil : "Để chuột gần máy, tắt bớt thiết bị Bluetooth khác, hoặc dùng dongle."))
        }
        let exp = t.expectedButtons
        if !exp.isEmpty && t.counts.keys.contains(where: { $0.hasPrefix("b") }) {      // chưa bấm nút nào → chưa có số đo nút
            let miss = exp.filter { (t.counts[$0.id] ?? 0) == 0 }.map(\.name)
            let lv: Lv = !miss.isEmpty ? .r : t.totalChatter > 0 ? .y : .g
            out.append(Item(lv: lv, title: "Nút bấm", sub: "\(exp.count) nút", value: "\(t.okButtons)/\(exp.count)", bar: nil, scale: "\(t.totalChatter) lần nhảy đúp",
                            why: miss.isEmpty ? "Bấm 1 lần máy nhận đúng 1. «Nhảy đúp» (bấm 1 nhận 2) là dấu hiệu nút sắp hỏng."
                                : "Chưa nhận: \(miss.joined(separator: ", ")).",
                            todo: !miss.isEmpty ? "Bấm lại các nút chưa nhận trong ô thử. Vẫn không nhận → nút hỏng hoặc chuột không gửi nút này."
                                : t.totalChatter > 0 ? "Nút nhảy đúp: vệ sinh nút / bảo hành nếu còn hạn." : nil))
        }
        let up = t.counts["wu"] ?? 0, down = t.counts["wd"] ?? 0
        if up + down > 0 {
            let lv: Lv = t.wrongDir == 0 ? .g : t.wrongDir <= 2 ? .y : .r
            out.append(Item(lv: lv, title: "Bánh xe", sub: "lăn lên · lăn xuống", value: "\(up) / \(down)", bar: nil, scale: "\(t.wrongDir) lần sai chiều",
                            why: "Lăn bao nhiêu nhận bấy nhiêu (lăn 10 thì phải ra 10). Nhảy ngược chiều = bánh xe bẩn hoặc mòn.",
                            todo: lv == .g ? nil : "Thổi bụi khe bánh xe; nhảy chiều nhiều → bảo hành."))
        }
        if let r = t.rate, let prev = settings.testHistory.first(where: { $0.mouse == r.mouse }) {
            let drop = r.hz < prev.hz * 0.7 && r.connection == prev.connection
            out.append(Item(lv: drop ? .y : .g, title: "So với lần trước", sub: prev.date.formatted(date: .abbreviated, time: .omitted) + " · " + prev.connection,
                            value: drop ? "Giảm" : "Không đổi", bar: nil, scale: "",
                            why: "Lần trước \(Int(prev.hz.rounded())) lần/s, \(prev.gaps) khựng." + (r.connection != prev.connection ? " Khác kết nối nên chênh là bình thường." : ""),
                            todo: drop ? "Cùng kết nối mà giảm mạnh: sạc pin / kiểm tra lại." : nil))
        }
        return out
    }

    var body: some View {
        let list = items
        let bad = list.filter { $0.lv == .r }.count, warn = list.filter { $0.lv == .y }.count
        VStack(alignment: .leading, spacing: 16) {
            if list.isEmpty {
                DMCard(title: "Chưa có số đo") {
                    Text("Làm bước 1 (rê chuột) và bước 2 (bấm nút) trước.").foregroundStyle(T.ink3)
                    Button("Về bước 1") { withAnimation(T.spring) { nav.testStep = 0 } }.buttonStyle(DMButton(kind: .ink))
                }
            } else {
                let color: Color = bad > 0 ? T.danger : warn > 0 ? T.warn : T.mint
                HStack(spacing: 16) {
                    Image(systemName: bad > 0 ? "exclamationmark" : "checkmark").font(.system(size: 26, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 58, height: 58).background(Circle().fill(color))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bad > 0 ? "Chuột có vấn đề · \(bad) mục cần xử lý" : warn > 0 ? "Chuột hoạt động tốt · \(warn) điểm nên chú ý" : "Chuột hoạt động tốt")
                            .font(.system(size: 19, weight: .heavy)).tracking(-0.6)
                        Text("\(t.rate?.mouse ?? device?.displayName ?? "") · \(t.rate?.connection ?? device?.connection ?? "") · \(Date().formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 13)).foregroundStyle(T.ink2)
                    }
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(color.opacity(0.25)))
                DMCard {
                    VStack(spacing: 0) { ForEach(list.indices, id: \.self) { i in row(list[i]) } }
                }
                HStack(spacing: 8) {
                    Button(saved ? "Đã lưu ✓" : "Lưu kết quả") { save() }.buttonStyle(DMButton(kind: .ink)).disabled(saved || t.rate == nil)
                    Button("Test lại") { t.resetKeys(); saved = false; withAnimation(T.spring) { nav.testStep = 0 } }.buttonStyle(DMButton(kind: .ghost))
                    Button("Chép kết quả · gửi bảo hành") { copy(list) }.buttonStyle(DMButton(kind: .ghost))
                }
            }
            HistoryCard()
        }
    }

    private func row(_ it: Item) -> some View {
        let c: Color = it.lv == .g ? T.mint : it.lv == .y ? T.warn : T.danger
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: it.lv == .g ? "checkmark" : "exclamationmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Circle().fill(c))
            VStack(alignment: .leading, spacing: 1) {
                Text(it.title).font(.system(size: 14, weight: .heavy))
                Text(it.sub).font(.system(size: 12)).foregroundStyle(T.ink3)
            }
            .frame(width: 160, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(it.value).font(.system(size: 18, weight: .heavy)).monospacedDigit()
                if let b = it.bar {
                    GeometryReader { g in
                        Capsule().fill(T.s3).overlay(alignment: .leading) { Capsule().fill(c).frame(width: g.size.width * b) }
                    }.frame(height: 6)
                }
                if !it.scale.isEmpty { Text(it.scale).font(.system(size: 11.5)).foregroundStyle(T.ink3) }
            }
            .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(it.why).font(.system(size: 13)).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
                if let todo = it.todo {
                    (Text("Nên làm: ").bold() + Text(todo)).font(.system(size: 13))
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(T.s2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(T.line).frame(height: 1) }
    }

    private func save() {
        guard var r = t.rate else { return }
        r.date = Date(); r.buttonsOK = t.okButtons; r.buttonsTotal = t.expectedButtons.count; r.chatter = t.totalChatter
        r.wheelUp = t.counts["wu"]; r.wheelDown = t.counts["wd"]; r.wrongDir = t.wrongDir
        settings.testHistory.insert(r, at: 0); saved = true
        AppModel.shared.show("Đã lưu kết quả test")
    }

    private func copy(_ list: [Item]) {
        var s = "Kết quả test chuột – DuckMouse\n\(t.rate?.mouse ?? device?.displayName ?? "") · \(t.rate?.connection ?? device?.connection ?? "") · \(Date().formatted(date: .abbreviated, time: .shortened))\n"
        for it in list { s += "• \(it.title): \(it.value)\(it.scale.isEmpty ? "" : " (\(it.scale))") – \(it.why)\n" }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
        AppModel.shared.show("Đã chép kết quả")
    }
}

struct HistoryCard: View {
    @EnvironmentObject var settings: Settings
    @State private var confirm = false
    var body: some View {
        DMCard(title: "Lịch sử test") {
            if settings.testHistory.isEmpty {
                Text("Chưa có lần test nào.").foregroundStyle(T.ink3)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("Lúc"); Text("Chuột"); Text("Kết nối"); Text("Lần/s"); Text("Lệch"); Text("Khựng"); Text("Nút"); Text("")
                    }.font(.system(size: 12, weight: .bold)).foregroundStyle(T.ink3)
                    ForEach(settings.testHistory.prefix(12)) { r in
                        GridRow {
                            Text(r.date.formatted(date: .abbreviated, time: .shortened))
                            Text(r.mouse).lineLimit(1)
                            Text(r.connection)
                            Text("\(Int(r.hz.rounded()))")
                            Text(r.jitterMS.vn() + " ms")
                            Text("\(r.gaps)")
                            Text(r.buttonsOK.map { "\($0)/\(r.buttonsTotal ?? 0)" } ?? "—")
                            Button { settings.testHistory.removeAll { $0.id == r.id } } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).accessibilityLabel("Xoá lần test")
                        }
                        .font(.system(size: 13))
                    }
                }
                Button("Xoá hết lịch sử") { confirm = true }.buttonStyle(DMButton(kind: .ghost))
                    .confirmationDialog("Xoá hết \(settings.testHistory.count) lần test?", isPresented: $confirm) {
                        Button("Xoá hết", role: .destructive) { settings.testHistory = [] }
                    }
            }
        }
    }
}

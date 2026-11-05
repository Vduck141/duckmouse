// Bài test 1 phút có hướng dẫn: app bảo bấm từng nút → ghi đầu thu gửi gì / macOS thấy gì → bảng kết quả + file.
import SwiftUI
import AppKit

struct Step: Identifiable {
    let id: Int
    let title: String       // "HÔNG SAU"
    let hint: String
    let expect: Sig
    var hid: [String] = []
    var mac: [String] = []
    var skipped = false
}

enum Verdict { case ok, blocked, vendor, hidden, none }

extension Step {
    var verdict: Verdict {
        switch (!hid.isEmpty, !mac.isEmpty) {
        case (true, true): return .ok
        case (true, false):
            // đầu thu không gửi «nút chuột» mà gửi phím / tín hiệu riêng hãng → macOS không coi là nút, không phải app chặn (05/11 VXE R1)
            return hid.contains { $0.contains("nút chuột") || $0.contains("lăn") } ? .blocked : .vendor
        case (false, true): return .hidden
        default: return .none
        }
    }
    var verdictText: String {
        switch verdict {
        case .ok: return "Bình thường"
        case .blocked: return "Đầu thu có gửi nhưng macOS không thấy → có app đang giữ / đổi nút (DuckMouse đang gán chức năng cho nút này cũng vậy – bình thường)"
        case .vendor: return "Chuột gửi PHÍM / tín hiệu riêng của hãng thay cho nút chuột → macOS không coi là nút (không phải do app chặn)"
        case .hidden: return "macOS thấy nhưng không đọc được ở đầu thu → nút đi đường lạ (cần file kết quả)"
        case .none: return "Không nhận – nút hỏng, hoặc chuột không gửi nút này"
        }
    }
    var mark: String { [Verdict.ok: "✓", .blocked: "⚠︎", .vendor: "⚠︎", .hidden: "⚠︎", .none: "✗"][verdict]! }
    var color: Color { [Verdict.ok: C.mint, .blocked: C.warn, .vendor: C.warn, .hidden: C.warn, .none: C.danger][verdict]! }
}

final class TestRun: ObservableObject {
    static let plan: [Step] = [
        Step(id: 0, title: "TRÁI", hint: "Bấm nút trái 1 lần", expect: .button(1)),
        Step(id: 1, title: "PHẢI", hint: "Bấm nút phải 1 lần", expect: .button(2)),
        Step(id: 2, title: "NHẤN BÁNH XE", hint: "Ấn bánh xe xuống (không lăn)", expect: .button(3)),
        Step(id: 3, title: "HÔNG SAU", hint: "Nút bên hông, gần cổ tay", expect: .button(4)),
        Step(id: 4, title: "HÔNG TRƯỚC", hint: "Nút bên hông, gần đầu ngón tay", expect: .button(5)),
        Step(id: 5, title: "LĂN LÊN", hint: "Lăn bánh xe ra phía trước vài nấc", expect: .wheel(1)),
        Step(id: 6, title: "LĂN XUỐNG", hint: "Lăn bánh xe về phía mình vài nấc", expect: .wheel(-1)),
    ]
    @Published var steps = TestRun.plan
    @Published var index = -1                 // -1 chưa bắt đầu, = steps.count là xong
    @Published var waited = 0                 // số giây đã chờ ở bước hiện tại
    @Published var savedFile: URL?
    private var armedAt = Date.distantFuture
    private var advancing = false
    private var timer: Timer?
    var running: Bool { index >= 0 && index < steps.count }
    var done: Bool { index >= steps.count }

    func start() {
        steps = Self.plan; savedFile = nil
        go(0)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.running else { return }
            self.waited += 1
        }
    }

    private func go(_ i: Int) {
        index = i; waited = 0; advancing = false
        armedAt = Date().addingTimeInterval(0.5)        // bỏ cú click vừa bấm nút trên màn hình
        if done { timer?.invalidate() }
    }

    func skip() {
        guard running else { return }
        steps[index].skipped = true
        go(index + 1)
    }

    /// Nhận tín hiệu từ Watcher
    func receive(_ fromHID: Bool, _ sig: Sig, _ text: String) {
        guard running, Date() >= armedAt else { return }
        let st = steps[index]
        switch (st.expect, sig) {
        case (.button(let want), .button(let got)):
            if got == 1 && want != 1 { return }           // click trái (bấm nút trên màn hình) không tính ở các bước khác
            if got == 2 && want != 2 && !fromHID { return }
        case (.wheel, .wheel): break
        case (.button, .wheel): return                    // lỡ tay lăn khi đang test nút
        case (.wheel, .button(let got)): if got <= 2 { return }
        default: break                                    // .other (phím, gói lạ) → luôn ghi lại
        }
        if fromHID { if !steps[index].hid.contains(text) { steps[index].hid.append(text) } }
        else if !steps[index].mac.contains(text) { steps[index].mac.append(text) }
        if !advancing {                                   // chờ thêm chút để nhận đủ cả 2 phía rồi sang bước sau
            advancing = true
            let i = index
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self, self.index == i else { return }
                self.go(i + 1)
            }
        }
    }

    var summary: String {
        let side = steps.filter { $0.id == 3 || $0.id == 4 }
        if side.allSatisfy({ $0.verdict == .ok }) {
            return "2 nút hông: chuột gửi bình thường, macOS cũng thấy. Nếu DuckMouse vẫn không nhận → lỗi ở DuckMouse, gửi kết quả này cho Duck."
        }
        if side.contains(where: { $0.verdict == .vendor }) {
            return "Nút hông: chuột gửi PHÍM / tín hiệu riêng của hãng (không phải nút chuột) – không phải do app chặn. Nếu bạn đã gán nút hông trong phần mềm hãng (âm lượng, phím tắt…) thì đặt lại «Quay lại / Chuyển tiếp» rồi test lại. Chuột tự gửi ⌘[ / ⌘] (Ugreen chế độ Mac) thì DuckMouse 1.1.1+ tự đổi được."
        }
        if side.contains(where: { $0.verdict == .blocked }) {
            return "Nút hông: chuột có gửi nhưng macOS không thấy → đang có app chặn nút (xem dòng app bên dưới). Tắt hẳn app đó rồi test lại."
        }
        if side.contains(where: { $0.verdict == .hidden }) {
            return "Nút hông: macOS thấy nhưng app không đọc được ở đầu thu → chuột gửi theo đường lạ. Bấm «Lưu file kết quả» và gửi file cho Duck."
        }
        return "Nút hông không nhận ở cả đầu thu lẫn macOS → kiểm phần mềm hãng (nút có bị gán sang chức năng khác / tắt không) hoặc nút hỏng."
    }

    func save(_ w: Watcher) {
        var t: [String] = ["DuckMouse Dò nút – kết quả bài test", "\(Date()) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", ""]
        t.append("== Đầu thu ==")
        t += w.parts.map { "• \($0.kind): \($0.declares) · \($0.title)" }
        t.append("App đang chạy có thể chặn nút: " + (w.apps.isEmpty ? "không có" : w.apps.joined(separator: ", ")))
        t.append("Quyền Giám sát đầu vào: \(w.granted ? "có" : "KHÔNG")")
        t.append(""); t.append("== Kết quả ==")
        for s in steps {
            t.append("\(s.mark) \(s.title): \(s.verdictText)" + (s.skipped ? " (bấm Bỏ qua)" : ""))
            t.append("    đầu thu gửi: " + (s.hid.isEmpty ? "—" : s.hid.joined(separator: " | ")))
            t.append("    macOS thấy:  " + (s.mac.isEmpty ? "—" : s.mac.joined(separator: " | ")))
        }
        t.append(""); t.append("Kết luận: " + summary)
        t.append(""); t.append("== Nhật ký tín hiệu ==")
        t += w.log
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let name = "DuckMouse-Do-nut-ket-qua-\(f.string(from: Date())).txt"
        let text = t.joined(separator: "\n")
        let dl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent(name)
        if (try? text.write(to: dl, atomically: true, encoding: .utf8)) != nil { savedFile = dl; return }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        try? text.write(to: tmp, atomically: true, encoding: .utf8)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        savedFile = tmp
    }
}

// MARK: - giao diện

struct MainView: View {
    @StateObject var w = Watcher()
    @StateObject var t = TestRun()
    @State private var showTech = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DuckMouse Dò nút").font(.system(size: 22, weight: .heavy))
                Text("Bài test 1 phút: làm theo chữ trên màn hình. Xong chụp màn hình bảng kết quả gửi Duck.")
                    .font(.system(size: 13)).foregroundStyle(C.ink2)
            }
            if !w.granted { permissionBanner }
            Panel(title: "Chuột đang cắm", sub: "mỗi dòng là 1 phần của đầu thu") { partsList }
                .fixedSize(horizontal: false, vertical: true)
            Panel(title: t.done ? "Kết quả" : t.running ? "Bước \(t.index + 1) / \(t.steps.count)" : "Bài test", sub: "") {
                if t.done { result } else if t.running { stepView } else { intro }
            }
            DisclosureGroup(isExpanded: $showTech) {
                HStack(spacing: 12) {
                    Panel(title: "Đầu thu gửi", sub: "di chuyển: \(w.moves) gói") { Lines(lines: w.hid, empty: "—") }
                    Panel(title: "macOS thấy", sub: "") { Lines(lines: w.mac, empty: "—") }
                }
                .frame(height: 220)
            } label: { Text("Chi tiết kỹ thuật (cho Duck)").font(.system(size: 12, weight: .semibold)).foregroundStyle(C.ink3) }
            Text("macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · Dò nút 1.3 · © 2026 by Vduck")
                .font(.system(size: 11)).foregroundStyle(C.ink3)
        }
        .padding(20)
        .frame(minWidth: 900, minHeight: 680)
        .background(C.page)
        .foregroundStyle(C.ink)
        .preferredColorScheme(.dark)
        .onAppear {
            w.sink = { [weak t] h, s, x in t?.receive(h, s, x) }
            w.start()
        }
    }

    private var permissionBanner: some View {
        HStack {
            Text("⚠︎ Chưa có quyền «Giám sát đầu vào». Vào Cài đặt → Quyền riêng tư & Bảo mật → Giám sát đầu vào → bật «DuckMouse Dò nút» (không thấy thì bấm + để thêm) → tắt app, mở lại.")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(C.warn)
            Spacer()
            Button("Mở Cài đặt") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }.buttonStyle(.borderedProminent)
        }
        .padding(12).background(C.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var partsList: some View {
        Group {
            if w.parts.isEmpty {
                Text(w.granted ? "Chưa thấy chuột ngoài nào – cắm đầu thu / bật Bluetooth chuột." : "Cần quyền để đọc.").foregroundStyle(C.ink3)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(w.parts) { p in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(p.kind).font(.system(size: 13, weight: .bold)).frame(width: 230, alignment: .leading)
                            Text(w.granted ? p.declares : "cần quyền để đọc").font(.system(size: 12.5)).foregroundStyle(C.ink2)
                            Spacer()
                            Text(p.title).font(.system(size: 11.5)).foregroundStyle(C.ink3).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var appsLine: some View {
        Text("App đang chạy có thể đổi / chặn nút: " + (w.apps.isEmpty ? "không có" : w.apps.joined(separator: ", ")))
            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(w.apps.isEmpty ? C.ink3 : C.warn)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App sẽ bảo bạn bấm lần lượt 7 thao tác:").font(.system(size: 15, weight: .semibold))
            Text(TestRun.plan.map(\.title).joined(separator: "  →  ")).font(.system(size: 14, weight: .bold)).foregroundStyle(C.brand)
            Text("Bấm đúng nút được hỏi, app nhận là tự sang bước sau. Nút nào bấm mãi không nhận → bấm «Bỏ qua».")
                .font(.system(size: 13)).foregroundStyle(C.ink2)
            appsLine
            Button { t.start() } label: { Text("Bắt đầu test").font(.system(size: 16, weight: .heavy)).padding(.horizontal, 26).padding(.vertical, 8) }
                .buttonStyle(.borderedProminent).tint(C.brand).foregroundStyle(.black).disabled(!w.granted)
            Spacer(minLength: 0)
        }
    }

    private var stepView: some View {
        let st = t.steps[t.index]
        return VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(t.steps) { s in
                    Circle().fill(s.id < t.index ? (s.skipped ? C.danger : C.mint) : s.id == t.index ? C.brand : C.s2).frame(width: 12, height: 12)
                }
            }
            Text("Bấm").font(.system(size: 18, weight: .semibold)).foregroundStyle(C.ink2)
            Text(st.title).font(.system(size: 54, weight: .heavy)).foregroundStyle(C.brand)
            Text(st.hint).font(.system(size: 15)).foregroundStyle(C.ink2)
            if let last = (st.hid + st.mac).last {
                Text("Vừa nhận: " + last).font(.system(size: 13, weight: .semibold)).foregroundStyle(C.mint)
            }
            Spacer(minLength: 0)
            HStack {
                Text(t.waited >= 8 ? "Bấm mãi không nhận? Bấm «Bỏ qua» để sang bước sau." : " ")
                    .font(.system(size: 13)).foregroundStyle(C.warn)
                Spacer()
                Button("Bỏ qua – nút này không nhận") { t.skip() }.buttonStyle(.bordered).controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    Text("Thao tác"); Text("Đầu thu gửi"); Text("macOS thấy"); Text("Kết luận")
                }
                .font(.system(size: 11.5, weight: .bold)).foregroundStyle(C.ink3)
                ForEach(t.steps) { s in
                    GridRow {
                        Text("\(s.mark) \(s.title)").font(.system(size: 13, weight: .heavy)).foregroundStyle(s.color)
                        Text(s.hid.isEmpty ? "—" : s.hid.joined(separator: "\n")).font(.system(size: 12))
                        Text(s.mac.isEmpty ? "—" : s.mac.joined(separator: "\n")).font(.system(size: 12))
                        Text(s.verdictText).font(.system(size: 12, weight: .semibold)).foregroundStyle(s.color)
                    }
                }
            }
            Divider().overlay(C.line)
            Text("Kết luận: " + t.summary).font(.system(size: 14, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            appsLine
            HStack(spacing: 10) {
                Button("Lưu file kết quả") { t.save(w) }.buttonStyle(.borderedProminent).tint(C.brand).foregroundStyle(.black)
                if let f = t.savedFile {
                    Text("Đã lưu \(f.lastPathComponent) vào " + (f.path.contains("/Downloads/") ? "Tải về" : "thư mục tạm (đã chép vào bộ nhớ tạm)"))
                        .font(.system(size: 12)).foregroundStyle(C.mint)
                    Button("Mở thư mục") { NSWorkspace.shared.activateFileViewerSelecting([f]) }.buttonStyle(.bordered)
                }
                Spacer()
                Button("Test lại") { w.clear(); t.start() }.buttonStyle(.bordered)
            }
            Text("Gửi Duck: chụp màn hình cửa sổ này (Cmd+Shift+4 rồi bấm Space, bấm vào cửa sổ). Nếu có file kết quả thì gửi kèm.")
                .font(.system(size: 12)).foregroundStyle(C.ink3)
        }
    }
}

// Tab "Gán chức năng": mỗi nút 5 ô (click + giữ rồi kéo 4 hướng), hình động chuột, chọn 1 trong 34 chức năng
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GanView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: Nav
    @State private var focus: Dir?
    @State private var editing: Dir?

    var b: Int { settings.mappableButtons.contains { $0.0 == nav.ganButton } ? nav.ganButton : 3 }

    var body: some View {
        Screen(title: "Gán chức năng", sub: "Giữ nút một chút rồi kéo 1 hướng. Ô giữa = click.") {
            HStack(spacing: 10) {
                PillSegment(items: settings.mappableButtons.map { ($0.0, $0.1) }, selection: $nav.ganButton)
                Button("+ Nút") { nav.testStep = 1; withAnimation(T.spring) { nav.tab = .test }; AppModel.shared.show("Bấm nút muốn thêm trong ô thử") }
                    .buttonStyle(DMButton(kind: .ghost))
                Spacer()
                Toggle("Bật gán chức năng", isOn: $settings.buttonsEnabled).toggleStyle(DMSwitch()).fixedSize()
            }
            HStack(alignment: .top, spacing: 16) {
                MouseStage(button: b, focus: focus).frame(width: 270)
                VStack(spacing: 12) {
                    DMCard(padding: 14) {
                        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                            GridRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]); cell(.len); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                            GridRow { cell(.trai); cell(.click); cell(.phai) }
                            GridRow { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]); cell(.xuong); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                        }
                    }
                    .onHover { if !$0 { focus = nil } }
                    DMCard(padding: 16) {
                        DMSlider(title: "Giữ bao lâu rồi mới kéo", value: Binding(get: { settings.wait(b) }, set: { settings.waits[String(b)] = $0 }),
                                 range: 0.05...0.6, step: 0.05) { $0.vn(2) + " s" }
                        DMSlider(title: "Kéo bao xa thì tính", value: $settings.dragDistance, range: 40...150, step: 5) { "\(Int($0)) px" }
                        if b > 5 {
                            HStack {
                                Text("Tên nút").font(.system(size: 13.5, weight: .semibold)).frame(width: 220, alignment: .leading)
                                TextField("Tên", text: Binding(get: { settings.extraButtons[String(b)] ?? "" }, set: { settings.extraButtons[String(b)] = $0 }))
                                    .textFieldStyle(.roundedBorder)
                                Button("Bỏ nút này") { settings.extraButtons[String(b)] = nil; nav.ganButton = 3 }.buttonStyle(DMButton(kind: .ghost))
                            }
                        }
                    }
                    Text(b == 3 ? "Click bánh xe giữ mặc định → để app tự xử lý (Chrome mở link tab mới)."
                         : b == 4 || b == 5 ? "Click «Giữ mặc định» → Chrome / Safari tự hiểu Quay lại / Chuyển tiếp. Finder cần chọn «Quay lại ⌘[» / «Đi tiếp ⌘]»."
                         : "Nút bạn thêm: phần gán giữ lại kể cả khi bỏ nút, thêm lại là có ngay.")
                        .font(.system(size: 12)).foregroundStyle(T.ink3).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .disabled(!settings.buttonsEnabled)
            .opacity(settings.buttonsEnabled ? 1 : 0.5)
        }
        .sheet(item: $editing) { d in SlotSheet(button: b, dir: d) }
    }

    private func cell(_ d: Dir) -> some View {
        let s = settings.slot(b, d), mid = d == .click
        let empty = s.action == .macDinh && !mid
        return Button { editing = d } label: {
            VStack(spacing: 3) {
                Text(mid ? "Click" : d.title).font(.system(size: 11.5, weight: .bold)).opacity(0.6)
                Text(mid && s.action == .macDinh ? "Giữ mặc định" : s.label).font(.system(size: 14, weight: .heavy)).tracking(-0.3)
                    .multilineTextAlignment(.center).lineLimit(2).opacity(empty ? 0.5 : 1)
                Text(mid && s.action == .macDinh ? (b == 4 ? "quay lại" : b == 5 ? "chuyển tiếp" : "app tự xử lý") : s.detail)
                    .font(.system(size: 11.5)).opacity(0.6).lineLimit(1)
            }
            .foregroundStyle(mid ? T.page : T.ink)
            .padding(10).frame(maxWidth: .infinity, minHeight: 92)
            .background(mid ? T.ink : T.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(focus == d && !mid ? T.ink : T.line, lineWidth: focus == d && !mid ? 1.5 : 1))
            .offset(y: focus == d ? -2 : 0)
            .animation(T.spring, value: focus)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { focus = d } }
        .accessibilityLabel("\(d.title): \(s.label)")
    }
}

extension Dir: Identifiable { var id: String { rawValue } }

/// Hình động: nút sáng vàng → chuột trượt theo hướng + mũi tên → hiện tên chức năng
struct MouseStage: View {
    let button: Int
    let focus: Dir?
    @EnvironmentObject var settings: Settings
    @State private var step = 0
    @State private var lit = false
    @State private var moved = false
    @State private var showAct = false
    @State private var actText = ""          // chữ chỉ đổi khi ô đang ẩn → không đè chữ cũ
    @State private var timer: Timer?
    private let order: [Dir] = [.click, .trai, .phai, .len, .xuong]
    var dir: Dir { focus ?? order[step % 5] }

    // vị trí nút trên ảnh 706×1008 (ảnh nét anh chọn 04/11, đã tô màu + lật ngang)
    static let imgW: CGFloat = 706, imgH: CGFloat = 1008
    static let spots: [Int: CGRect] = [3: CGRect(x: 304, y: 104, width: 68, height: 141),
                                       5: CGRect(x: 74, y: 328, width: 22, height: 131),
                                       4: CGRect(x: 80, y: 468, width: 22, height: 141)]
    var vec: CGSize { [Dir.trai: CGSize(width: -26, height: 0), .phai: CGSize(width: 26, height: 0), .len: CGSize(width: 0, height: -22), .xuong: CGSize(width: 0, height: 22)][dir] ?? .zero }

    var body: some View {
        let sc: CGFloat = 250 / Self.imgH
        VStack(spacing: 8) {
            ZStack {
                Group {
                    if let img = MouseArt.image { Image(nsImage: img).resizable().interpolation(.high).antialiased(true).frame(width: Self.imgW * sc, height: 250) }
                    if let r = Self.spots[button] {
                        RoundedRectangle(cornerRadius: 4).fill(T.brand.opacity(lit ? 0.85 : 0))
                            .shadow(color: T.brand.opacity(lit ? 0.8 : 0), radius: 6)
                            .frame(width: r.width * sc + 4, height: r.height * sc + 4)
                            .position(x: (r.midX) * sc, y: (r.midY) * sc)
                    }
                }
                .frame(width: Self.imgW * sc, height: 250)
                .offset(moved ? vec : .zero)
                if moved && dir != .click {
                    Arrow(vec: vec).stroke(T.brand, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: Self.imgW * sc, height: 250).transition(.opacity)
                }
                if Self.spots[button] == nil {
                    Text(settings.buttonName(button)).font(.system(size: 12, weight: .heavy)).padding(.horizontal, 10).padding(.vertical, 5)
                        .background(lit ? T.brand : T.s2, in: Capsule()).offset(y: -140)
                }
            }
            .frame(height: 300)
            .animation(T.spring, value: moved)
            .animation(.easeInOut(duration: 0.25), value: lit)
            Text("\(settings.buttonName(button)) · " + (dir == .click ? "click" : "giữ \(settings.wait(button).vn(1))s → \(dir.title)"))
                .font(.system(size: 12)).foregroundStyle(T.ink3)
            Text(actText)
                .font(.system(size: 14, weight: .heavy)).foregroundStyle(T.page)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(T.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(showAct ? 1 : 0).offset(y: showAct ? 0 : 6)
                .animation(T.spring, value: showAct)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RadialGradient(colors: [T.brandSoft, .clear], center: .center, startRadius: 0, endRadius: 170), in: RoundedRectangle(cornerRadius: 24))
        .background(T.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(T.line))
        .onAppear { play() }
        .onDisappear { timer?.invalidate() }
        .onChange(of: focus) { _, _ in play() }
        .onChange(of: button) { _, _ in step = 0; play() }
    }

    private func play() {
        timer?.invalidate()
        lit = false; moved = false
        var tr = Transaction(); tr.disablesAnimations = true
        withTransaction(tr) { showAct = false }                 // ẩn ngay, không mờ dần
        let d = dir
        let sl = settings.slot(button, d)
        actText = d == .click && sl.action == .macDinh ? "Giữ mặc định" : sl.action == .macDinh ? "Chưa gán" : sl.action.title
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { lit = true }
        if d == .click {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { lit = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { lit = true; showAct = true }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { moved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { showAct = true }
        }
        let t = Timer(timeInterval: 2.3, repeats: false) { _ in
            DispatchQueue.main.async { if focus == nil { step += 1 }; play() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

struct Arrow: Shape {
    let vec: CGSize
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY + 10)
        let e = CGPoint(x: c.x + vec.width * 3.2, y: c.y + vec.height * 3.2)
        p.move(to: c); p.addLine(to: e)
        let a = atan2(e.y - c.y, e.x - c.x), l: CGFloat = 10
        p.move(to: CGPoint(x: e.x - l * cos(a - .pi / 6), y: e.y - l * sin(a - .pi / 6))); p.addLine(to: e)
        p.addLine(to: CGPoint(x: e.x - l * cos(a + .pi / 6), y: e.y - l * sin(a + .pi / 6)))
        return p
    }
}

/// Chọn chức năng cho 1 ô
struct SlotSheet: View {
    let button: Int, dir: Dir
    @EnvironmentObject var settings: Settings
    @Environment(\.dismiss) private var dismiss
    @State private var s = Slot.none

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(settings.buttonName(button)) · \(dir == .click ? "Click" : dir.title)").font(.system(size: 20, weight: .heavy))
            Picker("Chức năng", selection: $s.action) {
                Text(dir == .click ? "Giữ mặc định (app tự xử lý)" : "Không dùng").tag(ButtonAction.macDinh)
                Text("Không làm gì (tắt nút)").tag(ButtonAction.khongGi)
                ForEach(ButtonAction.groups, id: \.0) { g, list in
                    Section(g) { ForEach(list) { Text($0.title).tag($0) } }
                }
            }
            .labelsHidden()
            .accessibilityLabel("Chức năng")
            switch s.action {
            case .moThuMuc:
                HStack { Text(s.param.isEmpty ? "Chưa chọn thư mục" : s.param).lineLimit(1).truncationMode(.middle).foregroundStyle(T.ink2); Spacer()
                    Button("Chọn thư mục…") { if let p = choose(dir: true) { s.param = p } }.buttonStyle(DMButton(kind: .ghost)) }
            case .moApp:
                HStack { Text(s.param.isEmpty ? "Chưa chọn app" : (s.param as NSString).lastPathComponent).foregroundStyle(T.ink2); Spacer()
                    Button("Chọn app…") { if let p = choose(dir: false) { s.param = p } }.buttonStyle(DMButton(kind: .ghost)) }
            case .moWeb:
                TextField("Địa chỉ web, ví dụ facebook.com", text: $s.param).textFieldStyle(.roundedBorder)
            case .phimTat:
                ShortcutRecorder(param: $s.param)
            default: EmptyView()
            }
            HStack {
                Button("Thử") { Actions.perform(s) }.buttonStyle(DMButton(kind: .ghost)).disabled(s.action == .macDinh || s.action == .khongGi)
                Spacer()
                Button("Huỷ") { dismiss() }.buttonStyle(DMButton(kind: .ghost))
                Button("Lưu") { settings.setSlot(button, dir, s); dismiss() }.buttonStyle(DMButton(kind: .ink)).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 440)
        .onAppear { s = settings.slot(button, dir) }
    }

    private func choose(dir: Bool) -> String? {
        let p = NSOpenPanel()
        p.canChooseDirectories = dir; p.canChooseFiles = !dir; p.prompt = "Chọn"
        if !dir { p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowedContentTypes = [.application] }
        return p.runModal() == .OK ? p.url?.path : nil
    }
}

/// Ô ghi phím tắt (mẫu 141): bấm «Ghi» rồi bấm tổ hợp phím – chỉ ghi phím tắt, không ghi chữ gõ
struct ShortcutRecorder: View {
    @Binding var param: String
    @State private var recording = false
    @State private var monitor: Any?
    var body: some View {
        HStack(spacing: 10) {
            Text(recording ? "Bấm tổ hợp phím…" : Shortcut(param)?.text ?? "Chưa ghi")
                .font(.system(size: 16, weight: .heavy)).monospaced()
                .padding(.horizontal, 14).frame(height: 40).frame(minWidth: 160)
                .background(recording ? T.brandSoft : T.s2, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(recording ? T.brand : T.line, lineWidth: recording ? 2 : 1))
            Button(recording ? "Huỷ" : "Ghi phím tắt") { recording ? stop() : start() }.buttonStyle(DMButton(kind: .ghost))
        }
        .onDisappear { stop() }
    }
    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            var f: CGEventFlags = []
            if e.modifierFlags.contains(.command) { f.insert(.maskCommand) }
            if e.modifierFlags.contains(.shift) { f.insert(.maskShift) }
            if e.modifierFlags.contains(.option) { f.insert(.maskAlternate) }
            if e.modifierFlags.contains(.control) { f.insert(.maskControl) }
            if e.keyCode == 53 && f.isEmpty { stop(); return nil }          // Esc = huỷ
            param = Shortcut(code: e.keyCode, flags: f).param
            stop()
            return nil
        }
    }
    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

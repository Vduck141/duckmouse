// La bàn (1.1.6): giữ nút có cử chỉ 0,5 giây → ô chữ thập cạnh con trỏ ghi 4 hướng + click, kéo hướng nào sáng hướng đó.
// Chỉ tạo cửa sổ ở lần giữ đầu tiên, sau đó ẩn/hiện lại – lúc không bấm không tốn gì.
import AppKit
import SwiftUI

final class CompassState: ObservableObject {
    @Published var button = 3
    @Published var lit: Dir?
}

enum Compass {
    static let delay = 0.5
    private static var panel: NSPanel?
    private static let state = CompassState()
    private static var hideWork: DispatchWorkItem?
    static var visible: Bool { panel?.isVisible == true }
    static let size = NSSize(width: 300, height: 300)

    /// Hiện la bàn của nút b, tâm đặt tại vị trí con trỏ (toạ độ CGEvent: gốc góc trên-trái màn chính)
    static func show(_ b: Int, at cg: CGPoint) {
        hideWork?.cancel()
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
            p.level = .statusBar; p.isOpaque = false; p.backgroundColor = .clear; p.ignoresMouseEvents = true; p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            p.contentView = NSHostingView(rootView: CompassView(st: state))
            panel = p
        }
        state.button = b; state.lit = nil
        let mainH = NSScreen.screens.first?.frame.height ?? 0
        let pt = NSPoint(x: cg.x, y: mainH - cg.y)
        let scr = NSScreen.screens.first { NSMouseInRect(pt, $0.frame, false) } ?? NSScreen.main
        var r = NSRect(x: pt.x - size.width / 2, y: pt.y - size.height / 2, width: size.width, height: size.height)
        if let vf = scr?.visibleFrame {
            r.origin.x = min(max(r.minX, vf.minX + 4), vf.maxX - r.width - 4)
            r.origin.y = min(max(r.minY, vf.minY + 4), vf.maxY - r.height - 4)
        }
        panel?.setFrame(r, display: false)
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel?.animator().alphaValue = 1 }
        Log.detail("LA BÀN", "hiện nút \(b)")
    }

    /// Đang kéo về hướng d (chưa đủ quãng) → sáng ô đó
    static func lean(_ d: Dir?) { if visible && state.lit != d { state.lit = d } }

    /// Ẩn; fired = vừa chạy chức năng → giữ ô sáng thêm 0,25 giây cho mắt kịp thấy
    static func hide(fired d: Dir? = nil) {
        guard let p = panel, p.isVisible else { return }
        if let d { state.lit = d }
        hideWork?.cancel()
        let w = DispatchWorkItem { p.orderOut(nil); state.lit = nil }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + (d == nil ? 0 : 0.25), execute: w)
    }
}

extension Compass {
    /// Bản thử: hiện la bàn thật (góc dưới phải) lần lượt nút 3/4/5, ghi vùng chụp ra file
    static func demo(to dir: String) {
        guard let scr = NSScreen.screens.first else { return }
        let mainH = scr.frame.height, vf = scr.visibleFrame
        let cg = CGPoint(x: vf.maxX - 190, y: mainH - (vf.minY + 190))
        let steps: [(Int, Dir?)] = [(3, .len), (4, .trai), (5, nil)]
        for (i, st) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(i) * 2) {
                show(st.0, at: cg); lean(st.1)
                if let f = panel?.frame {
                    let r = "\(Int(f.minX)),\(Int(mainH - f.maxY)),\(Int(f.width)),\(Int(f.height))"
                    try? r.write(toFile: dir + "/vung.txt", atomically: true, encoding: .utf8)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) { hide() }
    }
    /// Vẽ la bàn nút 3/4/5 (nút 3 sáng ↑) ra PNG để kiểm – không mở cửa sổ
    @MainActor static func snapshot(to dir: String) {
        for b in [3, 4, 5] {
            let st = CompassState(); st.button = b; st.lit = b == 3 ? .len : b == 4 ? .trai : nil
            let r = ImageRenderer(content: CompassView(st: st)); r.scale = 2
            if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("la-ban-\(b).png"))
            }
        }
    }
}

/// Vòng tròn kính mờ (Liquid Glass) chia 4 múi (↑ → ↓ ←) + nút tròn giữa = click
struct CompassView: View {
    @ObservedObject var st: CompassState
    @ObservedObject private var settings = Settings.shared
    private let R: CGFloat = 138, r: CGFloat = 50          // bán kính ngoài / lõi giữa
    private let gold = Color(red: 1, green: 0.80, blue: 0.28)

    var body: some View {
        ZStack {
            glass(Circle(), tint: Color.black.opacity(0.10)).frame(width: R * 2 + 12, height: R * 2 + 12)
            ForEach([Dir.len, .phai, .xuong, .trai], id: \.self) { d in wedge(d) }
            center
        }
        .frame(width: Compass.size.width, height: Compass.size.height)
        .animation(.easeOut(duration: 0.12), value: st.lit)
    }

    /// Kính mờ macOS 26+; máy cũ dùng vật liệu mờ
    @ViewBuilder private func glass<S: Shape>(_ shape: S, tint: Color) -> some View {
        if #available(macOS 26, *) {
            Color.clear.glassEffect(.regular.tint(tint), in: shape)
        } else {
            shape.fill(.ultraThinMaterial).overlay(shape.fill(tint))
        }
    }

    private func angle(_ d: Dir) -> Double { ["len": -90, "phai": 0, "xuong": 90, "trai": 180][d.rawValue] ?? 0 }

    private func wedge(_ d: Dir) -> some View {
        let s = settings.slot(st.button, d), none = s.action == .macDinh, on = st.lit == d
        let a = angle(d) * .pi / 180, mid = (R + r) / 2 + 4
        let arrow = ["len": "↑", "phai": "→", "xuong": "↓", "trai": "←"][d.rawValue]!
        let shape = Sector(start: angle(d) - 43, end: angle(d) + 43, inner: r + 6, outer: R)
        return ZStack {
            shape.fill(on ? AnyShapeStyle(LinearGradient(colors: [gold, Color(red: 1, green: 0.66, blue: 0.18)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.black.opacity(0.08)))
            shape.stroke(Color.white.opacity(on ? 0.5 : 0.16), lineWidth: 1)
            VStack(spacing: 2) {
                Text(arrow).font(.system(size: 13, weight: .heavy))
                Text(none ? "—" : s.label).font(.system(size: 13, weight: .bold))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                if !none, !s.detail.isEmpty { Text(s.detail).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).opacity(0.85) }
            }
            .frame(width: d == .len || d == .xuong ? 118 : 84)
            .foregroundStyle(on ? Color.black : Color.white.opacity(none ? 0.5 : 1))
            .shadow(color: .black.opacity(on ? 0 : 0.75), radius: 2, y: 0.5)
            .offset(x: cos(a) * mid, y: sin(a) * mid)
        }
    }

    private var center: some View {
        let s = settings.slot(st.button, .click), none = s.action == .macDinh
        return ZStack {
            Circle().fill(Color.black.opacity(0.18)).frame(width: r * 2, height: r * 2)
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
            VStack(spacing: 1) {
                Text("Click").font(.system(size: 10, weight: .semibold)).opacity(0.8)
                Text(none ? "Mặc định" : s.label).font(.system(size: 12, weight: .bold))
                    .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.75)
            }
            .frame(width: r * 2 - 14).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.75), radius: 2, y: 0.5)
        }
    }
}

/// Múi vành khăn từ góc start → end (độ, 0 = bên phải, chiều kim đồng hồ), 4 góc bo tròn
private struct Sector: Shape {
    var start: Double, end: Double, inner: CGFloat, outer: CGFloat
    var co: CGFloat = 14, ci: CGFloat = 9                 // bán kính bo góc ngoài / trong
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        func pt(_ rad: CGFloat, _ deg: Double) -> CGPoint {
            CGPoint(x: c.x + rad * cos(deg * .pi / 180), y: c.y + rad * sin(deg * .pi / 180))
        }
        let dO = asin(co / (outer - co)) * 180 / .pi, dI = asin(ci / (inner + ci)) * 180 / .pi
        var p = Path()
        p.move(to: pt((outer - co) * cos(dO * .pi / 180), start))
        p.addArc(center: pt(outer - co, start + dO), radius: co, startAngle: .degrees(start - 90), endAngle: .degrees(start + dO), clockwise: false)
        p.addArc(center: c, radius: outer, startAngle: .degrees(start + dO), endAngle: .degrees(end - dO), clockwise: false)
        p.addArc(center: pt(outer - co, end - dO), radius: co, startAngle: .degrees(end - dO), endAngle: .degrees(end + 90), clockwise: false)
        p.addArc(center: pt(inner + ci, end - dI), radius: ci, startAngle: .degrees(end + 90), endAngle: .degrees(end + 180 - dI), clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: .degrees(end - dI), endAngle: .degrees(start + dI), clockwise: true)
        p.addArc(center: pt(inner + ci, start + dI), radius: ci, startAngle: .degrees(start + 180 + dI), endAngle: .degrees(start + 270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

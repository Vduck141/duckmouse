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
    static let size = NSSize(width: 340, height: 176)

    /// Hiện la bàn của nút b, tâm đặt tại vị trí con trỏ (toạ độ CGEvent: gốc góc trên-trái màn chính)
    static func show(_ b: Int, at cg: CGPoint) {
        hideWork?.cancel()
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
            p.level = .statusBar; p.isOpaque = false; p.backgroundColor = .clear; p.ignoresMouseEvents = true; p.hasShadow = true
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
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
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
    /// Vẽ la bàn nút 3/4/5 (nút 3 sáng ↑) ra PNG để kiểm – không mở cửa sổ
    @MainActor static func snapshot(to dir: String) {
        for b in [3, 4, 5] {
            let st = CompassState(); st.button = b; st.lit = b == 3 ? .len : nil
            let r = ImageRenderer(content: CompassView(st: st)); r.scale = 2
            if let img = r.nsImage, let t = img.tiffRepresentation, let rep = NSBitmapImageRep(data: t),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("la-ban-\(b).png"))
            }
        }
    }
}

struct CompassView: View {
    @ObservedObject var st: CompassState
    @ObservedObject private var settings = Settings.shared
    var body: some View {
        VStack(spacing: 6) {
            cell(.len)
            HStack(spacing: 6) { cell(.trai); cell(.click); cell(.phai) }
            cell(.xuong)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12)))
        .frame(width: Compass.size.width, height: Compass.size.height)
    }
    private func cell(_ d: Dir) -> some View {
        let s = settings.slot(st.button, d)
        let none = s.action == .macDinh
        let on = st.lit == d
        let arrow = ["click": "●", "trai": "←", "phai": "→", "len": "↑", "xuong": "↓"][d.rawValue]!
        return VStack(spacing: 1) {
            Text("\(arrow)  \(none ? (d == .click ? "Mặc định" : "—") : s.label)")
                .font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
            if !none, !s.detail.isEmpty {
                Text(s.detail).font(.system(size: 10)).lineLimit(1).opacity(0.7)
            }
        }
        .foregroundStyle(on ? Color.black : Color.white.opacity(none ? 0.4 : 0.95))
        .frame(width: 104, height: 46)
        .background(RoundedRectangle(cornerRadius: 11).fill(on ? Color(red: 1, green: 0.82, blue: 0.3) : Color.white.opacity(d == .click ? 0.14 : 0.07)))
    }
}

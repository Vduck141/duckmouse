// Giao diện chung: màu, bo góc, hiệu ứng theo Lucian UX/UI Prompt
// (MIT License (c) 2026 Seokwoooo · https://lucianlabs.dev/uxui-prompt/ – mẫu 013, 039, 042, 081, 186). Màu nhấn = vàng logo DuckMouse.
import AppKit
import SwiftUI

enum T {
    private static func c(_ light: UInt32, _ dark: UInt32, _ la: CGFloat = 1, _ da: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            let dk = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let v = dk ? dark : light, a = dk ? da : la
            return NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: a)
        })
    }
    static let page = c(0xF4F2EE, 0x07080D)
    static let surface = c(0xFFFFFF, 0x13141C)
    static let s2 = c(0xF5F3EF, 0x1A1B25)
    static let s3 = c(0xEAE7E1, 0x252632)
    static let ink = c(0x16151B, 0xF4F0E8)
    static let ink2 = c(0x57535F, 0xF4F0E8, 1, 0.68)
    static let ink3 = c(0x8E8A97, 0xF4F0E8, 1, 0.42)
    static let line = c(0x16151B, 0xFFFFFF, 0.09, 0.08)
    static let line2 = c(0x16151B, 0xFFFFFF, 0.17, 0.16)
    static let brand = c(0xF5B800, 0xFFC933)
    static let brandSoft = c(0xF5B800, 0xFFC933, 0.16, 0.15)
    static let mint = c(0x119C72, 0x7EE8C0)
    static let warn = c(0xD6731E, 0xFFB26B)
    static let danger = c(0xD93A55, 0xFF7D8C)
    static let shadow = c(0x281E50, 0x000000, 0.22, 0.6)
    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.68)
    static let ease = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.4)
}

/// Thẻ trắng bo 24
struct DMCard<Content: View>: View {
    var title: String? = nil
    var sub: String? = nil
    var padding: CGFloat = 20
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 15, weight: .heavy)).tracking(-0.2)
                    if let sub { Text(sub).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.ink3) }
                }
            }
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(T.line))
        .shadow(color: T.shadow.opacity(0.35), radius: 22, y: 16)
    }
}

/// Tiêu đề màn
struct ScreenHeader: View {
    let title: String, sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 26, weight: .heavy)).tracking(-1)
            Text(sub).font(.system(size: 14)).foregroundStyle(T.ink3)
        }
        .padding(.bottom, 6)
    }
}

enum ChipKind { case plain, ok, warn, bad, brand }
struct Chip: View {
    let text: String
    var kind: ChipKind = .plain
    var body: some View {
        let fg: Color = [ChipKind.ok: T.mint, .warn: T.warn, .bad: T.danger, .brand: T.ink][kind] ?? T.ink2
        let bg: Color = kind == .brand ? T.brandSoft : kind == .plain ? T.s2 : fg.opacity(0.14)
        Text(text).font(.system(size: 12, weight: .bold)).foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(bg, in: Capsule())
    }
}

/// Nút đen / xám / vàng, nảy khi bấm
struct DMButton: ButtonStyle {
    enum Kind { case ink, ghost, brand }
    var kind: Kind = .ink
    func makeBody(configuration c: Configuration) -> some View {
        c.label.font(.system(size: 13.5, weight: .bold))
            .padding(.horizontal, 16).frame(height: 38)
            .foregroundStyle(kind == .ink ? T.page : T.ink)
            .background(kind == .ink ? T.ink : kind == .brand ? T.brand : T.s2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(c.isPressed ? 0.95 : 1)
            .animation(T.spring, value: c.isPressed)
            .contentShape(Rectangle())
    }
}

/// Nút gạt co giãn (mẫu 013)
struct DMSwitch: ToggleStyle {
    func makeBody(configuration c: Configuration) -> some View {
        HStack(spacing: 14) {
            c.label.frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: c.isOn ? .trailing : .leading) {
                Capsule().fill(c.isOn ? T.ink : T.s3).frame(width: 52, height: 30)
                Capsule().fill(c.isOn ? T.page : Color.white).frame(width: 24, height: 24).padding(3)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            }
            .animation(T.spring, value: c.isOn)
            .onTapGesture { c.isOn.toggle() }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { c.isOn.toggle() }
        }
    }
}

/// Dòng cài đặt: tên đậm + mô tả + nút gạt
struct SettingRow: View {
    let title: String, sub: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(sub).font(.system(size: 12.5)).foregroundStyle(T.ink3)
            }
        }
        .toggleStyle(DMSwitch())
        .padding(.vertical, 8)
        .accessibilityLabel(title)
    }
}

/// Thanh chọn viên thuốc: viên đen trượt mềm (mẫu 039)
struct PillSegment<V: Hashable>: View {
    let items: [(V, String)]
    @Binding var selection: V
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { v, title in
                Button { withAnimation(T.spring) { selection = v } } label: {
                    Text(title).font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(selection == v ? T.page : T.ink2)
                        .padding(.horizontal, 16).frame(height: 36)
                        .background {
                            if selection == v { Capsule().fill(T.ink).matchedGeometryEffect(id: "pill", in: ns) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
            }
        }
        .padding(5)
        .background(T.surface, in: Capsule())
        .overlay(Capsule().stroke(T.line))
    }
}

/// Ô số liệu nhỏ
struct Tile: View {
    let label: String, value: String
    var foot: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.ink3)
            Text(value).font(.system(size: 16, weight: .heavy)).tracking(-0.3).lineLimit(1).minimumScaleFactor(0.7)
            if let foot { Text(foot).font(.system(size: 11.5)).foregroundStyle(T.ink3) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.s2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Dòng nhãn – giá trị
struct KV: View {
    let k: String, v: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(k).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(T.ink3)
            Spacer(minLength: 8)
            Text(v).font(.system(size: 13.5, weight: .semibold)).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(T.line).frame(height: 1) }
    }
}

/// Thanh trượt có tên + số
struct DMSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    let format: (Double) -> String
    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 13.5, weight: .semibold)).frame(width: 220, alignment: .leading)
            Group {
                if let step { Slider(value: $value, in: range, step: step) } else { Slider(value: $value, in: range) }
            }
            .tint(T.ink).accessibilityLabel(title)
            Text(format(value)).font(.system(size: 13.5, weight: .heavy)).monospacedDigit().frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

extension Double {
    /// 0.25 → "0,25"
    func vn(_ digits: Int = 1) -> String { String(format: "%.\(digits)f", self).replacingOccurrences(of: ".", with: ",") }
}

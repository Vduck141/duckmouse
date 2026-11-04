// DuckMouse – app chuột tiếng Việt của anh Duck: chuột của tôi, test, cuộn mượt, gán chức năng
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { AppModel.shared.start() }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
}

enum Tab: String, CaseIterable, Identifiable {
    case chuot = "Chuột của tôi", test = "Test chuột", cuon = "Cuộn mượt", gan = "Gán chức năng", caiDat = "Cài đặt"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .chuot: return "computermouse"
        case .test: return "waveform.path.ecg"
        case .cuon: return "arrow.up.and.down"
        case .gan: return "plus.viewfinder"
        case .caiDat: return "gearshape"
        }
    }
}

/// Điều hướng chung (để nút «Gán chức năng →» trong tab Test nhảy đúng thẻ)
final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var tab: Tab = .chuot
    @Published var ganButton = 3
    @Published var testStep = 0
    @Published var showWelcome = false
}

@main
struct DuckMouseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    @StateObject private var hid = MouseHID.shared
    @StateObject private var settings = Settings.shared
    @StateObject private var nav = Nav.shared
    @StateObject private var db = MiceDB.shared
    @StateObject private var paired = PairedMice.shared

    var body: some Scene {
        Window("DuckMouse", id: "main") {
            MainView()
                .environmentObject(model).environmentObject(hid).environmentObject(settings)
                .environmentObject(nav).environmentObject(db).environmentObject(paired)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1080, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Giới thiệu DuckMouse") { Nav.shared.tab = .caiDat }
            }
        }

        MenuBarExtra {
            MenuContent()
                .environmentObject(model).environmentObject(hid).environmentObject(settings)
        } label: {
            Image(systemName: "computermouse")
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var hid: MouseHID
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: Settings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let d = hid.devices.first(where: { $0.id == hid.lastActive }) ?? hid.devices.first {
            Text("\(d.displayName) · \(d.connection)")
        } else {
            Text("Chưa thấy chuột ngoài nào")
        }
        Divider()
        Toggle("Cuộn mượt", isOn: $settings.scrollEnabled)
        Toggle("Gán chức năng nút chuột", isOn: $settings.buttonsEnabled)
        if model.mosRunning { Text("⚠️ Mos đang chạy – cuộn/nút của DuckMouse tạm nghỉ") }
        Divider()
        Button("Mở DuckMouse") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Giới thiệu DuckMouse") { Nav.shared.tab = .caiDat; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Thoát DuckMouse") { NSApp.terminate(nil) }
    }
}

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var settings: Settings
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                Banners()
                Group {
                    switch nav.tab {
                    case .chuot: MyMouseView()
                    case .test: TestView()
                    case .cuon: ScrollSettingsView()
                    case .gan: GanView()
                    case .caiDat: GeneralView()
                    }
                }
                .id(nav.tab)
                .transaction { $0.animation = nil }       // đổi màn ngay, không trượt (trượt làm dải mép cuộn nháy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(T.s2)
            .overlay(alignment: .top) {
                if let t = model.toast {
                    Text(t).font(.system(size: 14, weight: .bold)).foregroundStyle(T.page)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(T.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.top, 14).transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(T.spring, value: model.toast)
        }
        .overlay { if nav.showWelcome { WelcomeView().transition(.opacity) } }
        .background(WindowSetup())
        .onAppear { if !settings.welcomeShown { nav.showWelcome = true } }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                Text("DuckMouse").font(.system(size: 16, weight: .heavy)).tracking(-0.5)
            }
            .padding(.horizontal, 6).padding(.bottom, 16).padding(.top, 8)
            ForEach(Tab.allCases) { t in
                Button { withAnimation(T.spring) { nav.tab = t } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: t.icon).frame(width: 18)
                        Text(t.rawValue).lineLimit(1)
                        Spacer(minLength: 4)
                        if t == .gan {
                            Text("\(settings.mappableButtons.count * 5)").font(.system(size: 10, weight: .heavy))
                                .padding(.horizontal, 6).padding(.vertical, 2).background(T.brand, in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(Color.black)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(nav.tab == t ? T.page : T.ink2)
                    .padding(.horizontal, 12).frame(height: 40)
                    .background {
                        if nav.tab == t {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.ink).matchedGeometryEffect(id: "nav", in: ns)
                                .shadow(color: T.shadow, radius: 8, y: 6)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.rawValue)
            }
            Spacer()
            StatusFoot()
        }
        .padding(12)
        .frame(width: 232)
        .background(T.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(T.line).frame(width: 1) }
    }
}

/// Chân thanh bên: đang chạy gì
struct StatusFoot: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: Settings
    var body: some View {
        let ok = model.trusted && !model.mosRunning
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(ok ? T.mint : T.warn).frame(width: 8, height: 8)
                    .background(Circle().fill((ok ? T.mint : T.warn).opacity(0.25)).frame(width: 14, height: 14))
                Text(ok ? "Đang chạy" : model.mosRunning ? "Tạm nghỉ (Mos)" : "Thiếu quyền").font(.system(size: 12.5, weight: .bold))
            }
            Text([settings.scrollEnabled ? "Cuộn mượt" : nil, settings.buttonsEnabled ? "gán nút" : nil].compactMap { $0 }.joined(separator: " + ") + " bật")
                .font(.system(size: 12)).foregroundStyle(T.ink2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(T.s2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Cảnh báo dùng chung: thiếu quyền Trợ năng, Mos đang chạy
struct Banners: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 6) {
            if !model.trusted {
                Banner(icon: "lock.shield", color: T.warn, text: "Cần quyền Trợ năng để cuộn mượt và gán nút chuột.", button: "Cấp quyền") { model.requestTrust() }
            }
            if model.mosRunning {
                Banner(icon: "exclamationmark.triangle", color: T.warn,
                       text: "Mos đang chạy. Cuộn mượt và nút chuột của DuckMouse tạm nghỉ để không chạy 2 lần.", button: "Tắt Mos") { model.quitMos() }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, (model.trusted && !model.mosRunning) ? 0 : 14)
    }
}

struct Banner: View {
    let icon: String, color: Color, text: String, button: String
    let action: () -> Void
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(button, action: action).buttonStyle(DMButton(kind: .ink))
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Khung cuộn chung cho mỗi màn
struct Screen<Content: View>: View {
    let title: String, sub: String
    @ViewBuilder var content: Content
    var body: some View {
        let sv = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(title: title, sub: sub)
                content
            }
            .padding(.horizontal, 28).padding(.vertical, 24)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        // macOS 26+: tắt dải mờ ở mép vùng cuộn (nháy sọc ngang khi đổi tab – 04/11)
        if #available(macOS 26.0, *) { sv.scrollEdgeEffectHidden(true, for: .all) } else { sv }
    }
}

// MARK: Giới thiệu lần đầu (mẫu 042 – từng bước)

struct WelcomeView: View {
    @EnvironmentObject var nav: Nav
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hid: MouseHID
    @State private var page = 0

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Capsule().fill(T.s3).frame(height: 5).overlay(alignment: .leading) {
                            Capsule().fill(T.ink).scaleEffect(x: i <= page ? 1 : 0, anchor: .leading)
                        }
                    }
                }
                .animation(T.ease, value: page)
                .padding(.bottom, 22)
                Group {
                    switch page {
                    case 0: features
                    case 1: perms
                    default: found
                    }
                }
                .transition(.opacity.combined(with: .offset(x: 16)))
                .id(page)
                HStack {
                    Button("Bỏ qua") { close() }.buttonStyle(DMButton(kind: .ghost))
                    Spacer()
                    Button(page == 2 ? "Test chuột ngay" : "Tiếp") {
                        if page < 2 { withAnimation(T.ease) { page += 1 } } else { close(); nav.tab = .test }
                    }
                    .buttonStyle(DMButton(kind: .ink))
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 22)
            }
            .padding(28)
            .frame(width: 600)
            .background(T.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(T.line))
            .shadow(color: T.shadow, radius: 40, y: 30)
        }
    }

    private func close() { settings.welcomeShown = true; withAnimation(T.ease) { nav.showWelcome = false } }

    private var features: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chip(text: "Xin chào 👋", kind: .brand)
            Text("DuckMouse làm chuột trên Mac dễ chịu hơn").font(.system(size: 24, weight: .heavy)).tracking(-1)
            Text("4 việc app làm cho bạn:").foregroundStyle(T.ink2).padding(.bottom, 10)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    feat("computermouse", "Chuột của tôi", "Nhận tên, kết nối, thông số – kể cả chuột mới cắm.")
                    feat("waveform.path.ecg", "Test chuột", "Độ mượt, từng nút, bánh xe – kết luận bằng lời.")
                }
                GridRow {
                    feat("arrow.up.and.down", "Cuộn mượt", "Lăn chuột trôi êm như trackpad.")
                    feat("plus.viewfinder", "Gán chức năng", "Giữ nút + kéo 4 hướng = 15 phím tắt.")
                }
            }
        }
    }
    private func feat(_ icon: String, _ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).frame(width: 34, height: 34)
                .background(T.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(T.line))
                .padding(.bottom, 4)
            Text(t).font(.system(size: 14, weight: .heavy))
            Text(s).font(.system(size: 12.5)).foregroundStyle(T.ink3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(T.s2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var perms: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cấp 2 quyền").font(.system(size: 24, weight: .heavy)).tracking(-1)
            Text("macOS cần bạn cho phép một lần. App tự kiểm, bật xong là xanh.").foregroundStyle(T.ink2).padding(.bottom, 10)
            PermRow(title: "Trợ năng", sub: "Để cuộn mượt và gán nút", ok: model.trusted) { model.requestTrust() }
            PermRow(title: "Theo dõi đầu vào", sub: "Để đọc chuột và test", ok: hid.listenGranted) { model.requestListen() }
        }
    }

    private var found: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hid.devices.isEmpty ? "Chưa thấy chuột" : "Đã nhận chuột của bạn").font(.system(size: 24, weight: .heavy)).tracking(-1)
            Text(hid.devices.isEmpty ? "Cắm dongle hoặc bật Bluetooth của chuột – app tự nhận." : "Làm 1 lần test 1 phút để biết chuột đang tốt không?")
                .foregroundStyle(T.ink2).padding(.bottom, 10)
            ForEach(hid.devices.prefix(3)) { d in DeviceRow(device: d) }
        }
    }
}

struct PermRow: View {
    let title: String, sub: String, ok: Bool
    let fix: () -> Void
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(sub).font(.system(size: 12.5)).foregroundStyle(T.ink3)
            }
            Spacer()
            if ok { Chip(text: "Đã cấp", kind: .ok) } else { Button("Cấp quyền", action: fix).buttonStyle(DMButton(kind: .ink)) }
        }
        .padding(14)
        .background(T.s2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Cửa sổ chính: thu nhỏ xuống Dock, đổi cỡ, toàn màn hình được. Đang mở → app thường (Dock + thanh menu); đóng → chạy nền.
/// (04/11 anh: «không phóng to thu nhỏ được» – app chạy nền thì macOS không cho thu xuống Dock / toàn màn hình)
struct WindowSetup: NSViewRepresentable {
    final class V: NSView {
        private var closeObs: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            w.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable])
            w.collectionBehavior.remove(.fullScreenAuxiliary)
            w.collectionBehavior.insert([.fullScreenPrimary, .managed])
            if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
            closeObs = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
            }
        }
        deinit { if let closeObs { NotificationCenter.default.removeObserver(closeObs) } }
    }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ v: NSView, context: Context) {}
}

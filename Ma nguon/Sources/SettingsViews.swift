// Tab "Cuộn mượt", "Cài đặt"
import AppKit
import SwiftUI

struct ScrollSettingsView: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        Screen(title: "Cuộn mượt", sub: "Lăn chuột trôi êm như trackpad. Trackpad và Magic Mouse giữ nguyên.") {
            DMCard {
                VStack(spacing: 0) {
                    SettingRow(title: "Bật DuckMouse xử lý bánh xe", sub: "Tắt = bánh xe chạy như macOS gốc", isOn: $settings.scrollEnabled)
                    Divider().overlay(T.line)
                    SettingRow(title: "Cuộn mượt", sub: "Trôi chậm dần sau mỗi nấc lăn", isOn: $settings.smooth).disabled(!settings.scrollEnabled)
                    Divider().overlay(T.line)
                    SettingRow(title: "Đảo chiều cuộn", sub: "Lăn xuống thì trang đi lên", isOn: $settings.reverse).disabled(!settings.scrollEnabled)
                }
            }
            DMCard(title: "Độ mượt") {
                DMSlider(title: "Khoảng cuộn mỗi nấc (Step)", value: $settings.step, range: 1...100) { $0.vn(1) }
                DMSlider(title: "Tốc độ (Speed)", value: $settings.speed, range: 1...10) { $0.vn(2) }
                DMSlider(title: "Độ trôi – cao = trôi lâu (Duration)", value: $settings.duration, range: 1...5) { $0.vn(2) }
                Button("Về mặc định") { settings.resetScroll() }.buttonStyle(DMButton(kind: .ghost))
            }
            .disabled(!settings.scrollEnabled || !settings.smooth)
            DMCard(title: "Phím giữ khi lăn") {
                VStack(spacing: 0) {
                    KV(k: "⌥ Option", v: "Cuộn nhanh gấp 5 (trang dài)")
                    KV(k: "⇧ Shift", v: "Cuộn ngang")
                    KV(k: "⌘ Command", v: "Tạm tắt cuộn mượt (cuộn chính xác)")
                }
            }
        }
    }
}

struct GeneralView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var hid: MouseHID
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var nav: Nav
    var body: some View {
        Screen(title: "Cài đặt", sub: "Quyền, khởi động, giới thiệu.") {
            DMCard(title: "Quyền") {
                PermRow(title: "Trợ năng", sub: "Để cuộn mượt và gán nút", ok: model.trusted) { model.requestTrust() }
                PermRow(title: "Theo dõi đầu vào", sub: "Để đọc chuột và test", ok: hid.listenGranted) { model.requestListen() }
            }
            DMCard {
                VStack(spacing: 0) {
                    SettingRow(title: "Mở khi đăng nhập máy", sub: "App chạy nền, biểu tượng trên thanh menu",
                               isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                    Divider().overlay(T.line)
                    SettingRow(title: "Hiện chữ khi chức năng chạy", sub: "Ô nhỏ giữa màn hình, tự tắt sau 0,6 giây", isOn: $settings.hud)
                }
            }
            DMCard(title: "Giới thiệu") {
                AboutBlock()
            }
            .id("gioi-thieu")
        }
    }
}

/// Giới thiệu – giống Messenger Vdk: biểu tượng, tên, phiên bản · ngày, © by Vduck, các link
enum AppInfo {
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    static let releaseDate = "04/11/2026"
    static let github = URL(string: "https://github.com/Vduck141/duckmouse")!
    static let whatsNew = """
    1.0.0 (04/11/2026) – bản đầu tiên
    • Chuột của tôi: tự nhận chuột (cáp / dongle / Bluetooth), thông số 100 mẫu chuột, chọn hoặc nhập tay chuột lạ.
    • Test chuột 3 bước: độ mượt, từng nút (ô thử khoá chức năng), bánh xe – kết luận bằng lời.
    • Cuộn mượt như trackpad.
    • Gán chức năng: giữ nút + kéo 4 hướng, 34 chức năng, hình động minh hoạ.
    """
}

struct AboutBlock: View {
    @EnvironmentObject var nav: Nav
    @State private var showNew = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DuckMouse").font(.system(size: 20, weight: .semibold))
                    Text("Phiên bản \(AppInfo.version) · \(AppInfo.releaseDate)").foregroundStyle(T.ink3)
                    Text("© 2026 by Vduck").font(.system(size: 11.5)).foregroundStyle(T.ink3)
                }
            }
            .padding(.vertical, 4)
            HStack(spacing: 16) {
                Button("Có gì mới") { showNew = true }.buttonStyle(.link)
                Link("Trang GitHub", destination: AppInfo.github)
                Button("Xem lại giới thiệu") { withAnimation(T.ease) { nav.showWelcome = true } }.buttonStyle(.link)
            }
            .font(.system(size: 13, weight: .semibold))
            Text("App chuột tiếng Việt cho macOS, miễn phí, mã nguồn mở (CC BY-NC 4.0). Giao diện theo Lucian UX/UI Prompt (MIT); thông số chuột ghi nguồn trong từng mẫu.")
                .font(.system(size: 12)).foregroundStyle(T.ink3).fixedSize(horizontal: false, vertical: true)
        }
        .alert("Có gì mới", isPresented: $showNew) { Button("Đóng", role: .cancel) {} } message: { Text(AppInfo.whatsNew) }
    }
}

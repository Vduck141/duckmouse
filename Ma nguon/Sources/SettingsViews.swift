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
                    Divider().overlay(T.line)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Màn giới thiệu").font(.system(size: 14, weight: .bold))
                            Text("Xem lại các tính năng của app").font(.system(size: 12.5)).foregroundStyle(T.ink3)
                        }
                        Spacer()
                        Button("Xem lại") { withAnimation(T.ease) { nav.showWelcome = true } }.buttonStyle(DMButton(kind: .ghost))
                    }
                    .padding(.vertical, 8)
                }
            }
            DMCard(title: "Giới thiệu") {
                Text("DuckMouse – app chuột tiếng Việt cho macOS, miễn phí, mã nguồn mở. Thoát app thì chuột trở về như macOS gốc. © 2026 by Vduck")
                Text("Cuộn mượt học từ Mos của Caldis (github.com/Caldis/Mos, CC BY-NC 4.0 – không thương mại). Giao diện theo Lucian UX/UI Prompt (MIT). Thông số 100 chuột tra 04/11/2026 – nguồn ghi trong từng mẫu.")
                    .font(.system(size: 12.5)).foregroundStyle(T.ink3)
            }
        }
    }
}

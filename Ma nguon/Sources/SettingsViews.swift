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
            DMCard(title: "Nhật ký & dò lỗi") {
                DebugBlock()
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
    static let releaseDate = "05/11/2026"
    static let github = URL(string: "https://github.com/Vduck141/duckmouse")!
    static let whatsNew = """
    1.1.3 (05/11/2026)
    • Nhật ký & dò lỗi (Cài đặt): bật Chế độ dò lỗi → bấm nút bị lỗi → Xuất nhật ký ra Tải về → gửi Duck. Không ghi chữ bạn gõ.
    • Chuột gửi nút hông kiểu phím (Ugreen chế độ Mac ⌘[ / ⌘], kiểu Windows ⌥← / ⌥→, phím Back / Forward) → tự đổi thành nút hông để gán được.
    • Nút «Thử» gửi phím tắt sang app bạn đang dùng · ghi được phím nóng · cảnh báo app chuột khác đang chạy.
    • Bỏ phần tự đổi phím âm lượng của 1.1.2 (đó là nút người dùng tự gán trong phần mềm hãng).

    1.1.0 (04/11/2026)
    • Thêm 200 mẫu chuột – tổng 300 mẫu văn phòng, silent, gaming (Logitech, Razer, SteelSeries, Corsair, HyperX, Glorious, Zowie, ASUS, Microsoft, Dell, HP, Lenovo, Rapoo, DareU, E-Dra, Fuhlen…).
    • Tab Mời cà phê: mã VietQR ủng hộ ngay trong app.

    1.0.0 (04/11/2026) – bản đầu tiên
    • Chuột của tôi: tự nhận chuột (cáp / dongle / Bluetooth), thông số 100 mẫu chuột, chọn hoặc nhập tay chuột lạ.
    • Test chuột 3 bước: độ mượt, từng nút (ô thử khoá chức năng), bánh xe – kết luận bằng lời.
    • Cuộn mượt như trackpad.
    • Gán chức năng: giữ nút + kéo 4 hướng, 34 chức năng, hình động minh hoạ.
    """
}

/// Cài đặt → Nhật ký & dò lỗi: bật ghi chi tiết 10 phút, xuất file gửi Duck
struct DebugBlock: View {
    @State private var until: Date? = Log.debugUntil
    @State private var exported: URL?
    private let tick = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private var timeText: String { until.map { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: $0) } ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingRow(title: "Chế độ dò lỗi",
                       sub: until == nil ? "Ghi chi tiết từng lần bấm nút (chuột gửi gì, app đổi / bỏ qua vì sao) để Duck tìm lỗi. Tự tắt sau 10 phút."
                                         : "Đang ghi chi tiết – tự tắt lúc \(timeText). Bấm các nút chuột bị lỗi vài lần rồi xuất nhật ký.",
                       isOn: Binding(get: { until != nil }, set: { Log.setDebug($0); until = Log.debugUntil }))
            HStack(spacing: 10) {
                Button("Xuất nhật ký ra Tải về") {
                    exported = Log.export()
                    if let u = exported { NSWorkspace.shared.activateFileViewerSelecting([u]) }
                }
                .buttonStyle(DMButton(kind: .ink))
                Button("Mở thư mục nhật ký") {
                    Log.flush()
                    NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: Log.file.path) ? Log.file : Log.dir])
                }
                .buttonStyle(DMButton(kind: .ghost))
                Spacer()
            }
            if let u = exported {
                Text("Đã lưu \(u.lastPathComponent) trong Tải về – gửi file này cho Duck.").font(.system(size: 12, weight: .semibold)).foregroundStyle(T.mint)
            }
            Text("Cách báo lỗi: bật Chế độ dò lỗi → bấm các nút chuột bị lỗi vài lần → Xuất nhật ký → gửi file trong Tải về cho Duck. Nhật ký chỉ nằm trên máy bạn, không ghi chữ bạn gõ.")
                .font(.system(size: 12)).foregroundStyle(T.ink3).fixedSize(horizontal: false, vertical: true)
        }
        .onReceive(tick) { _ in if until != Log.debugUntil { until = Log.debugUntil } }
    }
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

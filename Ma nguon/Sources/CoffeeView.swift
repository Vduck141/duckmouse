// Tab "Mời cà phê": mã VietQR chuyển khoản (app tự vẽ bằng CoreImage, không gọi web) + số tài khoản để chép
import SwiftUI
import AppKit
import CoreImage

enum Donate {
    static let bank = "MB Bank", bin = "970422", owner = "TRAN VIET DUC", account = "3453868666666"
    static let note = "Tien moi cf cam on"
    static var payload: String { maVietQR(nganHang: bin, soTK: account, noiDung: note) }

    /// Chuỗi VietQR (EMVCo): ngân hàng (BIN) + số TK + nội dung (tag 62/08), không ghi số tiền; CRC-16 CCITT-FALSE
    static func maVietQR(nganHang: String, soTK: String, noiDung: String) -> String {
        func o(_ t: String, _ v: String) -> String { t + String(format: "%02d", v.utf8.count) + v }
        let p = o("00", "01") + o("01", "11")
            + o("38", o("00", "A000000727") + o("01", o("00", nganHang) + o("01", soTK)) + o("02", "QRIBFTTA"))
            + o("53", "704") + o("58", "VN") + o("62", o("08", noiDung)) + "6304"
        var c: UInt16 = 0xFFFF
        for b in p.utf8 { c ^= UInt16(b) << 8; for _ in 0..<8 { c = c & 0x8000 != 0 ? (c << 1) ^ 0x1021 : c << 1 } }
        return p + String(format: "%04X", c)
    }

    /// Vẽ QR mức sửa lỗi M, phóng số nguyên lần (không nội suy) → ô vuông sắc nét; ảnh @2x cho Retina
    static func qrImage(points: CGFloat) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(payload.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let ci = f.outputImage else { return nil }
        let scale = max(1, floor(points * 2 / ci.extent.width))
        let big = ci.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext(options: [.useSoftwareRenderer: false]).createCGImage(big, from: big.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
    }
}

struct CoffeeView: View {
    @State private var qr = Donate.qrImage(points: 170)
    @State private var copied = false

    var body: some View {
        Screen(title: "Mời cà phê ☕", sub: "App miễn phí. Thấy hữu ích thì mời mình ly cà phê để làm tiếp nhé ☕") {
            DMCard {
                HStack(alignment: .center, spacing: 26) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white)
                        if let qr { Image(nsImage: qr).interpolation(.none).resizable().frame(width: 170, height: 170) }
                    }
                    .frame(width: 198, height: 198)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(T.brand, lineWidth: 3))
                    .accessibilityLabel("Mã VietQR chuyển khoản")
                    VStack(alignment: .leading, spacing: 10) {
                        Chip(text: "VietQR · quét bằng app ngân hàng", kind: .brand)
                        Text("\(Donate.bank) · \(Donate.owner)").font(.system(size: 15, weight: .heavy)).tracking(-0.3)
                        Text(Donate.account).font(.system(size: 26, weight: .heavy, design: .monospaced)).textSelection(.enabled)
                        HStack(spacing: 10) {
                            Button(copied ? "Đã chép ✓" : "Chép số tài khoản") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(Donate.account, forType: .string)
                                copied = true
                                AppModel.shared.show("Đã chép số tài khoản")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                            }
                            .buttonStyle(DMButton(kind: .brand))
                            .accessibilityLabel("Chép số tài khoản")
                        }
                        Text("Quét mã bằng app ngân hàng bất kỳ – nội dung «\(Donate.note)» điền sẵn, bạn chỉ nhập số tiền.")
                            .font(.system(size: 12.5)).foregroundStyle(T.ink3).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

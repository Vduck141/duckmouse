// Tên hãng theo mã USB (VID) – dùng khi chuột chưa có trong danh sách thông số (MiceDB)
import Foundation

enum KnownMice {
    // Tên hãng theo mã USB (VID) – chỉ vài hãng phổ biến
    static func vendorName(_ vid: Int) -> String? {
        [0x046D: "Logitech", 0x05AC: "Apple", 0x1532: "Razer", 0x045E: "Microsoft",
         0x1038: "SteelSeries", 0x3434: "Keychron", 0x25A7: "Compx (chip dongle)",
         0x093A: "PixArt", 0x1BCF: "Sunplus", 0x248A: "Telink", 0x0461: "Primax",
         0x413C: "Dell", 0x03F0: "HP", 0x17EF: "Lenovo", 0x258A: "SINOWEALTH", 0x3554: "CX"][vid]
    }
}

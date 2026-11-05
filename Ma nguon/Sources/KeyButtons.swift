// Nút hông chuột gửi kiểu PHÍM (chuột Ugreen chế độ Mac gửi ⌘[ / ⌘], chuột kiểu Windows gửi ⌥← / ⌥→) → đổi thành nút hông 4 / 5
// để gán chức năng, giữ + kéo như nút chuột thường. Chỉ đổi phím đến từ CHÍNH con chuột (đọc thiết bị gửi của từng sự kiện),
// bàn phím thật không bị đụng. Phím khác chuột gửi (nếu có) để nguyên.
import AppKit
import CoreGraphics
import IOKit

// API riêng của macOS (LinearMouse, Mac Mouse Fix cũng dùng): lấy sự kiện HID gốc của 1 CGEvent → mã thiết bị gửi
@_silgen_name("CGEventCopyIOHIDEvent") private func CGEventCopyIOHIDEvent(_ e: CGEvent) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetSenderID") private func IOHIDEventGetSenderID(_ e: CFTypeRef) -> UInt64

final class KeyButtons {
    static let shared = KeyButtons()
    private(set) var running = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Phím đang giữ từ chuột: mã phím → nút đã đổi (để nuốt phím lặp + cú nhả)
    private var held: [Int64: Int] = [:]
    /// Thiết bị gửi → mã hãng:mã chuột (mã thiết bị không đổi trong 1 lần cắm)
    private var senderCode: [UInt64: Int] = [:]
    /// Đầu thu có cả bàn phím (đã thấy gõ chữ qua nó) → không đổi phím, kẻo ⌘← / ⌥← của bàn phím thật thành nút chuột
    private var keyboardCodes: Set<Int> = Set(UserDefaults.standard.array(forKey: "keyboardDongles") as? [Int] ?? [])

    // MARK: đổi phím → nút

    /// Phím mũi tên / [ ] kèm ⌘ hoặc ⌥ → nút hông (4 = quay lại, 5 = đi tiếp). Mã phím macOS: 33 [ · 30 ] · 123 ← · 124 →
    static func button(keyCode: Int64, flags: CGEventFlags) -> Int? {
        let m = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        switch keyCode {
        case 33 where m == .maskCommand: return 4
        case 30 where m == .maskCommand: return 5
        case 123 where m == .maskCommand || m == .maskAlternate: return 4
        case 124 where m == .maskCommand || m == .maskAlternate: return 5
        default: return nil
        }
    }

    /// Cùng bảng trên nhưng theo mã HID (dùng ở MouseHID để biết phím này app tự đổi được): 0x2F [ · 0x30 ] · 0x50 ← · 0x4F →
    static func button(hidUsage u: UInt32, mods: Set<UInt32>) -> Int? {
        switch u {
        case 0x2F where mods == [3]: return 4
        case 0x30 where mods == [3]: return 5
        case 0x50 where mods == [3] || mods == [2]: return 4
        case 0x4F where mods == [3] || mods == [2]: return 5
        default: return nil
        }
    }

    static func keyText(_ keyCode: Int64, _ flags: CGEventFlags) -> String {
        (flags.contains(.maskAlternate) ? "⌥" : "") + (flags.contains(.maskCommand) ? "⌘" : "") +
            ([33: "[", 30: "]", 123: "←", 124: "→"][keyCode] ?? "#\(keyCode)")
    }

    // MARK: bật / tắt

    func start() {
        guard !running else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: { _, type, event, ref in
            Unmanaged<KeyButtons>.fromOpaque(ref!).takeUnretainedValue().handle(type, event)
        }, userInfo: me) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        running = true
    }

    func stop() {
        guard running else { return }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; running = false
        for b in Set(held.values) { ButtonEngine.shared.virtualButton(b, down: false) }   // đang giữ dở → nhả
        held = [:]
    }

    var healthy: Bool { guard let tap else { return !running }; return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap) }

    // MARK: xử lý

    /// Bản thử logic: thay cách đọc thiết bị gửi (sự kiện tự tạo không có thiết bị)
    static var mouseCodeHook: ((CGEvent) -> Int?)?

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let pass = Unmanaged.passUnretained(event)
        guard event.getIntegerValueField(.eventSourceUserData) != ScrollEngine.marker else { return pass }   // phím DuckMouse tự gửi
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let candidate = Self.button(keyCode: code, flags: event.flags)
        // nhanh: phím thường không phải từ chuột đang giữ → chỉ cần xem có phải chuột gõ chữ không (đầu thu có bàn phím)
        if candidate == nil && held[code] == nil {
            if type == .keyDown, Self.isTyping(code, event.flags), let c = mouseCode(event), !keyboardCodes.contains(c) { learnKeyboard(c) }
            return pass
        }
        if type == .keyUp, let b = held[code] {                     // nhả phím đã đổi (dù ⌘ nhả trước)
            held[code] = nil
            ButtonEngine.shared.virtualButton(b, down: false, orig: event)
            MouseHID.shared.emitVirtual(b, down: false, text: nil)
            return nil
        }
        guard let b = candidate, let c = mouseCode(event), !keyboardCodes.contains(c) else { return pass }
        if type == .keyDown {
            if held[code] != nil || event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }   // phím lặp khi giữ
            held[code] = b
            MouseHID.shared.emitVirtual(b, down: true, text: "phím " + Self.keyText(code, event.flags))
            ButtonEngine.shared.virtualButton(b, down: true, orig: event)
            return nil
        }
        return pass
    }

    /// Mã hãng:mã chuột của thiết bị gửi, nếu thiết bị đó là 1 con chuột đang nối (không phải bàn phím thật)
    private func mouseCode(_ event: CGEvent) -> Int? {
        if let h = Self.mouseCodeHook { return h(event) }
        guard let h = CGEventCopyIOHIDEvent(event)?.takeRetainedValue() else { return nil }   // sự kiện app khác tự tạo
        let sender = IOHIDEventGetSenderID(h)
        let code: Int
        if let c = senderCode[sender] { code = c } else {
            code = Self.lookup(sender)
            senderCode[sender] = code
        }
        guard code != 0, MouseHID.shared.devices.contains(where: { $0.vendorID != 0 && ($0.vendorID << 16 | $0.productID) == code }) else { return nil }
        return code
    }

    private static func lookup(_ sender: UInt64) -> Int {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(sender))
        guard svc != 0 else { return 0 }
        defer { IOObjectRelease(svc) }
        let opt = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        guard let v = IORegistryEntrySearchCFProperty(svc, kIOServicePlane, "VendorID" as CFString, nil, opt) as? Int,
              let p = IORegistryEntrySearchCFProperty(svc, kIOServicePlane, "ProductID" as CFString, nil, opt) as? Int else { return 0 }
        return v << 16 | p
    }

    /// Gõ chữ / số / dấu / cách thật (không kèm ⌘ ⌥ ⌃) – chuột chỉ gửi phím tắt, không ai «gõ chữ» bằng chuột.
    /// Mã phím macOS 0–50 = chữ, số, dấu, Space (bỏ 36 ↩, 48 Tab)
    static func isTyping(_ code: Int64, _ flags: CGEventFlags) -> Bool {
        code >= 0 && code <= 50 && code != 36 && code != 48 && flags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty
    }

    /// Thấy gõ chữ / số qua đầu thu của chuột → đầu thu có bàn phím đi kèm (Logitech Unifying, bộ phím chuột…) → nhớ, không đổi nữa
    private func learnKeyboard(_ c: Int) {
        keyboardCodes.insert(c)
        UserDefaults.standard.set(Array(keyboardCodes), forKey: "keyboardDongles")
        NSLog("DuckMouse: đầu thu %04X:%04X có bàn phím – không đổi phím ⌘[ / ⌥← thành nút chuột", c >> 16, c & 0xFFFF)
    }

    /// Đầu thu này app có đổi phím → nút không (MouseHID dùng để báo ở tab Test)
    func converts(vendor: Int, product: Int) -> Bool { running && !keyboardCodes.contains(vendor << 16 | product) }

    // MARK: thử (bản thử --gia-lap, không có chuột thật): chạy đúng đường như phím từ chuột
    func simulate(_ keyCode: Int64, flags: CGEventFlags, down: Bool) {
        guard let b = Self.button(keyCode: keyCode, flags: flags) ?? held[keyCode],
              let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: down) else { return }
        e.flags = flags
        if down {
            held[keyCode] = b
            MouseHID.shared.emitVirtual(b, down: true, text: "phím " + Self.keyText(keyCode, flags) + " (giả lập)")
            ButtonEngine.shared.virtualButton(b, down: true, orig: e)
        } else {
            held[keyCode] = nil
            ButtonEngine.shared.virtualButton(b, down: false, orig: e)
            MouseHID.shared.emitVirtual(b, down: false, text: nil)
        }
    }
}

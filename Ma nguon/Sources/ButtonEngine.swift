// Gán nút chuột (giữa, hông sau, hông trước, nút 6+) → click / giữ rồi kéo 4 hướng. Nút trái/phải không đụng tới.
import AppKit
import CoreGraphics

final class ButtonEngine {
    static let shared = ButtonEngine()
    private(set) var running = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Ô thử nút (tab Test): con trỏ trong ô thì chỉ ghi nhận, KHÔNG chạy chức năng, không trả nút về app
    static var testLock = false
    /// Báo cho ô thử: (nút, hướng) vừa nhận – hướng .click khi ấn nhả không kéo
    static var onTest: ((Int, Dir) -> Void)?

    // Nút đang giữ: chờ xem anh click hay giữ rồi kéo
    private var holdButton = 0
    private var holdDown: CGEvent?
    private var fired = false
    private var dragX = 0.0, dragY = 0.0
    private var downTime = Date.distantPast

    func start() {
        guard !running else { return }
        let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue) | CGEventMask(1 << CGEventType.otherMouseUp.rawValue) |
                   CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: { _, type, event, ref in
            Unmanaged<ButtonEngine>.fromOpaque(ref!).takeUnretainedValue().handle(type, event)
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
        tap = nil; source = nil; running = false; holdDown = nil
    }

    /// Bộ bắt còn sống không (macOS có thể tắt sau khi máy ngủ dậy / app bị treo)
    var healthy: Bool { guard let tap else { return !running }; return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap) }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != ScrollEngine.marker else { return Unmanaged.passUnretained(event) }
        // CGEvent đánh số từ 0 (2 = giữa); IOHID / giao diện đánh số từ 1 (3 = giữa)
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
        let s = Settings.shared
        let lock = Self.testLock

        if type == .otherMouseDragged {              // chuột vẫn di bình thường, chỉ đếm quãng kéo
            if button == holdButton && holdDown != nil { trackDrag(event, lock: lock) }
            return Unmanaged.passUnretained(event)
        }
        let click = s.slot(button, .click)
        let gesture = s.hasGesture(button)
        if !lock && !gesture {                       // không có cử chỉ → xử lý ngay
            if click.action == .macDinh { return Unmanaged.passUnretained(event) }
            if type == .otherMouseDown { DispatchQueue.main.async { Actions.perform(click) } }
            return nil
        }
        if type == .otherMouseDown {
            holdButton = button; holdDown = event.copy(); fired = false; dragX = 0; dragY = 0; downTime = Date()
            return nil
        }
        // nhả nút
        guard button == holdButton, let down = holdDown else { return lock ? nil : Unmanaged.passUnretained(event) }
        holdDown = nil
        if fired { return nil }                       // đã chạy cử chỉ → nuốt cú nhả
        if lock { DispatchQueue.main.async { Self.onTest?(button, .click) }; return nil }
        if click.action == .macDinh {                 // ấn nhanh → trả lại nút gốc (Chrome hiểu Quay lại / Đi tiếp)
            for e in [down, event.copy()].compactMap({ $0 }) {
                e.setIntegerValueField(.eventSourceUserData, value: ScrollEngine.marker)
                e.post(tap: .cgSessionEventTap)
            }
        } else {
            DispatchQueue.main.async { Actions.perform(click) }
        }
        return nil
    }

    private func trackDrag(_ event: CGEvent, lock: Bool) {
        let s = Settings.shared
        guard !fired, Date().timeIntervalSince(downTime) >= s.wait(holdButton) else { return }   // chưa giữ đủ → chưa đếm
        dragX += Double(event.getIntegerValueField(.mouseEventDeltaX))
        dragY += Double(event.getIntegerValueField(.mouseEventDeltaY))
        let dist = s.dragDistance
        let dir: Dir
        if abs(dragX) >= dist && abs(dragX) > abs(dragY) { dir = dragX < 0 ? .trai : .phai }
        else if abs(dragY) >= dist && abs(dragY) > abs(dragX) { dir = dragY < 0 ? .len : .xuong }
        else { return }
        let b = holdButton
        if lock { fired = true; DispatchQueue.main.async { Self.onTest?(b, dir) }; return }
        let slot = s.slot(b, dir)
        guard slot.action != .macDinh else { return }
        fired = true
        DispatchQueue.main.async { Actions.perform(slot) }
    }
}

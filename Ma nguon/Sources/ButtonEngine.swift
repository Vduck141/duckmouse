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
        setMoveTap(false); virtualHeld = nil; virtualKeyDown = nil; virtualKeyUp = nil
    }

    /// Bộ bắt còn sống không (macOS có thể tắt sau khi máy ngủ dậy / app bị treo)
    var healthy: Bool { guard let tap else { return !running }; return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap) }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Log.info("BỘ BẮT", "macOS tạm tắt bộ bắt nút (\(type == .tapDisabledByTimeout ? "chạy chậm" : "người dùng")) → bật lại")
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
        let who = virtualHeld == button ? "nút ảo \(button)" : "nút \(button)"
        let isDown = type == .otherMouseDown
        if !lock && !gesture {                       // không có cử chỉ → xử lý ngay
            if click.action == .macDinh {
                if isDown { Log.detail("NÚT", "\(who) nhấn · click = Giữ mặc định → trả cho app") }
                return Unmanaged.passUnretained(event)
            }
            if isDown {
                Log.detail("NÚT", "\(who) nhấn · click = \(click.action.title) → chạy")
                DispatchQueue.main.async { Self.perform(click) }
            }
            return nil
        }
        if isDown {
            Log.detail("NÚT", "\(who) nhấn · " + (lock ? "ô thử nút (chỉ ghi nhận)" : "có cử chỉ → giữ chờ kéo (≥ \(s.wait(button))s, \(Int(s.dragDistance)) px)"))
            holdButton = button; holdDown = event.copy(); fired = false; dragX = 0; dragY = 0; downTime = Date()
            return nil
        }
        // nhả nút
        guard button == holdButton, let down = holdDown else { return lock ? nil : Unmanaged.passUnretained(event) }
        holdDown = nil
        if fired { return nil }                       // đã chạy cử chỉ → nuốt cú nhả
        if lock { DispatchQueue.main.async { Self.onTest?(button, .click) }; return nil }
        if click.action == .macDinh {                 // ấn nhanh → trả lại nút gốc (Chrome hiểu Quay lại / Đi tiếp)
            let key = virtualKeyDown.flatMap { kd in virtualKeyUp.map { [kd, $0] } }
            Log.detail("NÚT", "\(who) nhả, không kéo · click = Giữ mặc định → trả lại \(key == nil ? "nút \(button)" : "phím gốc") cho app")
            replay(key ?? [down, event.copy()].compactMap { $0 })
        } else {
            Log.detail("NÚT", "\(who) nhả, không kéo · click = \(click.action.title) → chạy")
            DispatchQueue.main.async { Self.perform(click) }
        }
        return nil
    }

    /// Chạy chức năng (bản thử thay bằng performHook để ghi lại, không bấm thật)
    static var performHook: ((Slot) -> Void)?
    static var postHook: ((CGEvent) -> Void)?
    /// Bản thử logic (không bật bộ bắt thật): coi như bộ bắt đang chạy
    static var simulateRunning = false
    private static func perform(_ s: Slot) { if let h = performHook { h(s) } else { Actions.perform(s) } }

    /// Gửi lại sự kiện gốc cho app (đánh dấu để bộ bắt của DuckMouse bỏ qua)
    private func replay(_ events: [CGEvent]) {
        for e in events {
            e.setIntegerValueField(.eventSourceUserData, value: ScrollEngine.marker)
            if let h = Self.postHook { h(e) } else { e.post(tap: .cgSessionEventTap) }
        }
    }

    // MARK: nút ảo – chuột gửi nút hông kiểu phím (⌘[ / ⌥← / phím Back…) → KeyButtons / MouseHID đổi thành nút 4/5

    /// Phím gốc của nút ảo đang giữ: «Giữ mặc định» thì gửi lại đúng phím chuột gửi (⌘[ …) thay vì nút chuột 4/5
    private var virtualKeyDown: CGEvent?, virtualKeyUp: CGEvent?
    private(set) var virtualHeld: Int?

    /// Ấn / nhả nút ảo: chạy qua đúng đường của nút chuột thật (ô test, Gán chức năng, giữ + kéo).
    /// orig = phím gốc chuột gửi (nil = phím đa phương tiện → trả lại bằng nút chuột 4/5)
    func virtualButton(_ b: Int, down: Bool, orig: CGEvent? = nil) {
        let pos = CGEvent(source: nil)?.location ?? .zero
        guard let e = CGEvent(mouseEventSource: nil, mouseType: down ? .otherMouseDown : .otherMouseUp,
                              mouseCursorPosition: pos, mouseButton: CGMouseButton(rawValue: UInt32(b - 1)) ?? .center) else { return }
        e.setIntegerValueField(.mouseEventButtonNumber, value: Int64(b - 1))
        e.flags = []                                  // chuột gửi ⌘ kèm phím → không để thành ⌘ + click
        if down {
            virtualHeld = b; virtualKeyDown = orig?.copy(); virtualKeyUp = nil
            setMoveTap(true)
        } else {
            virtualKeyUp = orig?.copy()
            setMoveTap(false)
        }
        let pass = (running || Self.simulateRunning) ? handle(down ? .otherMouseDown : .otherMouseUp, e) != nil : true
        if pass { replay([orig?.copy() ?? e].compactMap { $0 }) }   // không gán gì → trả lại phím gốc / nút 4/5 cho app
        if !down { virtualHeld = nil; virtualKeyDown = nil; virtualKeyUp = nil }
    }

    /// Bộ nghe di chuột (chỉ nghe, bật lúc đang giữ nút ảo): nút ảo không có sự kiện kéo, macOS chỉ báo «di chuột»
    private var moveTap: CFMachPort?
    private func setMoveTap(_ on: Bool) {
        if on && moveTap == nil {
            let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            let me = Unmanaged.passUnretained(self).toOpaque()
            guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                            eventsOfInterest: mask, callback: { _, type, event, ref in
                let eng = Unmanaged<ButtonEngine>.fromOpaque(ref!).takeUnretainedValue()
                if type == .mouseMoved { eng.virtualMoved(event) }
                return Unmanaged.passUnretained(event)
            }, userInfo: me) else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0), .commonModes)
            moveTap = t
        }
        if let moveTap { CGEvent.tapEnable(tap: moveTap, enable: on) }
    }

    /// Di chuột lúc giữ nút ảo → đếm quãng kéo như nút thật (cùng đơn vị điểm ảnh)
    func virtualMoved(_ event: CGEvent) {
        guard running || Self.simulateRunning, virtualHeld != nil, holdDown != nil else { return }
        trackDrag(event, lock: Self.testLock)
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
        Log.detail("KÉO", "nút \(b) \(dir.title) (\(Int(dragX)), \(Int(dragY))) → chạy \(slot.action.title)")
        DispatchQueue.main.async { Self.perform(slot) }
    }
}

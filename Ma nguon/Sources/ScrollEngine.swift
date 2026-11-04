// Cuộn mượt – viết lại theo thuật toán của Mos (Caldis, CC BY-NC 4.0, xem LICENSE):
// chặn sự kiện bánh xe → cộng vào "đích" → mỗi khung hình màn hình đi 1 phần quãng còn lại (chậm dần)
// → làm mềm đầu cú đẩy → phát lại sự kiện cuộn nhỏ (giữ số lẻ, không làm tròn).
import AppKit
import CoreGraphics
import CoreVideo
import os

final class ScrollEngine {
    static let shared = ScrollEngine()
    static let marker: Int64 = 0x4455_434B_4D4F_5553   // "DUCKMOUS" – đánh dấu sự kiện do app tự phát

    private(set) var running = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var link: CVDisplayLink?          // nhịp theo màn hình (60Hz / 120Hz…) – giống Mos

    // Trạng thái dùng chung giữa luồng chính (nhận bánh xe) và luồng màn hình (phát cuộn) → khoá
    private var lock = os_unfair_lock_s()
    // trục 0 = dọc, 1 = ngang
    private var target = [0.0, 0.0], current = [0.0, 0.0]
    private var filter = [[0.0, 0.0], [0.0, 0.0]]   // cửa sổ làm mềm của Mos (ScrollFilter) cho từng trục
    private var trans = 0.1
    private var targetPID: pid_t = 0
    private var postFlags: CGEventFlags = []
    private var template: CGEvent?            // bản sao sự kiện gốc (giữ vị trí con trỏ, cửa sổ…) – giống Mos
    private let deadZone = 1.0

    // Nhật ký nhịp phát (chỉ khi bật `defaults write vn.vduck.DuckMouse debugScroll -bool YES`) để kiểm độ đều
    private let debug = UserDefaults.standard.bool(forKey: "debugScroll")
    private var debugLines: [String] = []

    func start() {
        guard !running else { return }
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: { _, type, event, ref in
            Unmanaged<ScrollEngine>.fromOpaque(ref!).takeUnretainedValue().handle(type, event)
        }, userInfo: me) else { return }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        makeLink()
        running = true
    }

    func stop() {
        guard running else { return }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let link { CVDisplayLinkStop(link) }
        tap = nil; source = nil; link = nil; running = false
        os_unfair_lock_lock(&lock); resetLocked(); os_unfair_lock_unlock(&lock)
    }

    /// Bộ bắt còn sống không
    var healthy: Bool { guard let tap else { return !running }; return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap) }

    private func makeLink() {
        var l: CVDisplayLink?
        guard CVDisplayLinkCreateWithActiveCGDisplays(&l) == kCVReturnSuccess, let l else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(l, { _, _, _, _, _, ref in
            Unmanaged<ScrollEngine>.fromOpaque(ref!).takeUnretainedValue().frame()
            return kCVReturnSuccess
        }, me)
        link = l
    }

    private func resetLocked() {
        target = [0, 0]; current = [0, 0]; filter = [[0, 0], [0, 0]]
        template = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let pass = Unmanaged.passUnretained(event)
        guard type == .scrollWheel,
              event.getIntegerValueField(.eventSourceUserData) != Self.marker else { return pass }
        if ButtonEngine.testLock { return nil }      // ô thử nút: chỉ đếm nấc (IOHID), không cuộn trang
        // Trackpad / Magic Mouse có pha cử chỉ → để nguyên
        if event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0 ||
           event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return pass }

        let s = Settings.shared
        let flags = event.flags
        if !s.smooth || flags.contains(.maskCommand) {          // ⌘ giữ = tạm tắt cuộn mượt
            if s.reverse { Self.negate(event) }
            return pass
        }

        var dy = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        var dx = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        if dy == 0 && dx == 0 {
            dy = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            dx = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        }
        if dy == 0 && dx == 0 {
            dy = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            dx = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        }
        if dy == 0 && dx == 0 { return pass }
        if s.reverse { dy = -dy; dx = -dx }
        var post = flags
        if flags.contains(.maskShift) && dx == 0 { dx = dy; dy = 0; post.remove(.maskShift) }  // ⇧ = cuộn ngang
        var amp = 1.0
        if flags.contains(.maskAlternate) { amp = 5; post.remove(.maskAlternate) }            // ⌥ = cuộn nhanh

        // Công thức Mos: trans = 1 − √(duration / 5,2), làm tròn 3 số lẻ
        let tr = max(0.001, ((1 - (s.duration / 5.2).squareRoot()) * 1000).rounded() / 1000)
        os_unfair_lock_lock(&lock)
        trans = tr
        for (axis, raw) in [dy, dx].enumerated() where raw != 0 {
            let v = (abs(raw) < s.step ? (raw < 0 ? -s.step : s.step) : raw) * s.speed * amp
            let remaining = target[axis] - current[axis]
            if remaining != 0 && (remaining > 0) != (v > 0) {     // đổi chiều → bỏ quãng cũ
                target[axis] = 0; current[axis] = 0; filter[axis] = [0, 0]
            }
            target[axis] += v
        }
        targetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        postFlags = post
        template = event.copy()
        os_unfair_lock_unlock(&lock)
        if let link, !CVDisplayLinkIsRunning(link) { CVDisplayLinkStart(link) }
        return nil
    }

    /// Chạy trên luồng màn hình, mỗi khung hình 1 lần
    private func frame() {
        os_unfair_lock_lock(&lock)
        var out = [0.0, 0.0]
        var residual = 0.0
        for axis in 0..<2 {
            let step = (target[axis] - current[axis]) * trans
            current[axis] += step
            // ScrollFilter của Mos: chia cú đẩy đầu ra vài khung để không giật
            let first = filter[axis][1]
            filter[axis] = [first, first + 0.23 * (step - first)]
            out[axis] = first
            residual = max(residual, abs(target[axis] - current[axis]))
        }
        let outMag = max(abs(out[0]), abs(out[1]))
        var event: CGEvent?
        if outMag > deadZone, let e = template?.copy() {
            e.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: out[0])
            e.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: out[1])
            e.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1)
            e.setIntegerValueField(.eventSourceUserData, value: Self.marker)
            e.flags = postFlags
            event = e
        }
        let pid = targetPID
        let done = residual <= deadZone && outMag <= deadZone
        if done { resetLocked() }
        os_unfair_lock_unlock(&lock)

        if let event { if pid > 0 { event.postToPid(pid) } else { event.post(tap: .cgSessionEventTap) } }
        if debug { logFrame(out[0], posted: event != nil, done: done) }
        if done, let link { CVDisplayLinkStop(link) }
    }

    private func logFrame(_ dy: Double, posted: Bool, done: Bool) {
        debugLines.append(String(format: "%.4f\t%.3f\t%d", CFAbsoluteTimeGetCurrent(), dy, posted ? 1 : 0))
        if done {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("duckmouse-scroll.tsv")
            let text = debugLines.joined(separator: "\n") + "\n--\n"
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(text.data(using: .utf8)!); try? h.close() }
            else { try? text.write(to: url, atomically: true, encoding: .utf8) }
            debugLines = []
        }
    }

    private static func negate(_ e: CGEvent) {
        for f: CGEventField in [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2] {
            e.setIntegerValueField(f, value: -e.getIntegerValueField(f))
        }
        for f: CGEventField in [.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
                                .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2] {
            e.setDoubleValueField(f, value: -e.getDoubleValueField(f))
        }
    }
}

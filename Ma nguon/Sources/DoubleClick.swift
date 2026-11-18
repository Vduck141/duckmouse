// Bấm đúp chắc tay (1.1.8) – Duck đo 18/11/2026: chuột HyperWork bấm đúp hay hỏng vì con trỏ nhích 4–15 pt giữa 2 cú
// (macOS chỉ tính bấm đúp khi 2 cú gần như trùng chỗ). Cách sửa: 2 cú bấm trái cách nhau ≤ ngưỡng bấm đúp của máy
// và lệch ≤ 20 pt → đặt cú sau vào đúng chỗ cú đầu + tăng clickState → app nhận là bấm đúp / bấm ba.
// Chỉ đụng chuột thật (subtype 0, do phần cứng gửi); trackpad và sự kiện app tự phát để nguyên.
import AppKit
import CoreGraphics

/// Phần tính toán thuần (không đụng macOS) – để X thử bằng sự kiện giả
struct DoubleClickLogic {
    var maxDistance: Double = 20        // lệch tối đa giữa 2 cú (pt)
    var dragSlop: Double = 4            // giữ nút mà dời quá 4 pt = kéo, không nối chuỗi
    var interval: Double = 0.5          // ngưỡng bấm đúp của máy (giây) – lấy từ NSEvent.doubleClickInterval

    private(set) var anchor: CGPoint?   // chỗ cú đầu của chuỗi
    private var lastDownTime = 0.0
    private var chain = 0               // clickState của cú gần nhất
    private var downLoc = CGPoint.zero  // chỗ thật của cú đang giữ
    private var moved = false           // cú đang giữ đã kéo đi
    private var held = false
    private(set) var fixLoc: CGPoint?   // cú đang giữ đã bị dời → cú nhả dời theo
    private(set) var fixState = 0

    struct Out: Equatable { var loc: CGPoint?; var state: Int? }

    /// Cú ấn. sysState = clickState macOS đã tính. Trả vị trí / clickState mới (nil = để nguyên)
    mutating func down(_ p: CGPoint, time t: Double, sysState: Int) -> Out {
        defer { lastDownTime = t; downLoc = p; moved = false; held = true }
        fixLoc = nil; fixState = 0
        if let a = anchor, chain >= 1, t - lastDownTime <= interval, Self.dist(a, p) <= maxDistance {
            let want = max(sysState, chain + 1)
            chain = want
            if Self.dist(a, p) == 0 && sysState == want { return Out() }          // macOS tự nhận rồi
            fixLoc = a; fixState = want
            return Out(loc: a, state: want)
        }
        anchor = p; chain = max(1, sysState)
        return Out()
    }

    /// Kéo khi đang giữ
    mutating func dragged(_ p: CGPoint) -> Out {
        if held && Self.dist(downLoc, p) > dragSlop { moved = true }
        return Out()
    }

    /// Cú nhả: dời theo cú ấn nếu cú ấn đã bị dời; kéo đi thì cắt chuỗi
    mutating func up(_ p: CGPoint) -> Out {
        held = false
        if Self.dist(downLoc, p) > dragSlop { moved = true }
        let out = fixLoc.map { Out(loc: moved ? nil : $0, state: fixState) } ?? Out()
        if moved { anchor = nil; chain = 0 }
        fixLoc = nil
        return out
    }

    mutating func reset() { anchor = nil; chain = 0; fixLoc = nil; held = false; moved = false }

    static func dist(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
}

final class DoubleClick {
    static let shared = DoubleClick()

    private(set) var running = false
    let guardian = TapGuard("bấm đúp")   // 1.1.9 tự trông bộ bắt
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    private var loop: CFRunLoop?
    private var logic = DoubleClickLogic()
    private var count = 0               // số lần đã sửa (ghi nhật ký chi tiết khi bật dò lỗi)

    func start() {
        guard !running else { return }
        logic.reset()
        logic.interval = NSEvent.doubleClickInterval
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
                 | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: { _, type, event, ref in
            Unmanaged<DoubleClick>.fromOpaque(ref!).takeUnretainedValue().handle(type, event)
        }, userInfo: me) else { return }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        source = src
        // Luồng riêng: luồng chính bận vẽ giao diện cũng không làm trễ cú bấm trái
        let sem = DispatchSemaphore(value: 0)
        let th = Thread { [weak self] in
            self?.loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            sem.signal()
            CFRunLoopRun()
        }
        th.name = "DuckMouse.BamDup"
        th.qualityOfService = .userInteractive
        th.start()
        sem.wait()
        thread = th
        guardian.reset()
        running = true
    }

    func stop() {
        guard running else { return }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let loop { CFRunLoopStop(loop) }
        tap = nil; source = nil; loop = nil; thread = nil; running = false
    }

    var healthy: Bool { guard let tap else { return !running }; return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap) }

    /// Cập nhật ngưỡng khi anh đổi «Tốc độ bấm hai lần» trong Cài đặt máy
    func refreshInterval() { let i = NSEvent.doubleClickInterval; loop.map { CFRunLoopPerformBlock($0, CFRunLoopMode.commonModes.rawValue) { self.logic.interval = i }; CFRunLoopWakeUp($0) } }

    /// Xử lý 1 sự kiện (X thử thẳng hàm này bằng CGEvent giả)
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            guardian.disabled(type == .tapDisabledByTimeout ? .timeout : .user) { [weak self] in
                if let t = self?.tap, CFMachPortIsValid(t) { CGEvent.tapEnable(tap: t, enable: true) }
            }
            logic.reset()
            return pass
        }
        guardian.seen()
        // chỉ chuột thật: trackpad (subtype 3) / tablet và cú bấm do app phát (pid ≠ 0) để nguyên
        guard event.getIntegerValueField(.mouseEventSubtype) == 0,
              event.getIntegerValueField(.eventSourceUnixProcessID) == 0 else { return pass }
        let p = event.location
        let out: DoubleClickLogic.Out
        switch type {
        case .leftMouseDown:
            let sys = Int(event.getIntegerValueField(.mouseEventClickState))
            out = logic.down(p, time: ProcessInfo.processInfo.systemUptime, sysState: sys)
            if out.state != nil {
                count += 1
                let d = logic.anchor.map { DoubleClickLogic.dist($0, p) } ?? 0
                Log.detail("BẤM ĐÚP", String(format: "nối cú bấm lệch %.1f pt → clickState %d (lần %d)", d, out.state!, count))
            }
        case .leftMouseUp: out = logic.up(p)
        case .leftMouseDragged: out = logic.dragged(p)
        default: return pass
        }
        if let l = out.loc { event.location = l }
        if let s = out.state { event.setIntegerValueField(.mouseEventClickState, value: Int64(s)) }
        return pass
    }
}

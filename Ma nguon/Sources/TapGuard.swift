// Tự trông bộ bắt (1.1.9) – học cách MFinder canh bộ bắt sự kiện:
// 1) macOS tắt bộ bắt → bật lại ngay; tắt dồn dập (>3 lần/phút) → chờ 1, 2, 4… tối đa 30 s rồi mới bật, không giành giật làm giật máy.
// 2) Bộ bắt «chết lặng» (vẫn báo đang chạy mà không nhận gì): HID thấy chuột thật bấm / lăn mà 0,5 s sau bộ bắt
//    vẫn chưa nhận → hụt 3 lần liền thì gỡ móc cũ, gắn móc mới. Gắn lại cách nhau ít nhất 10 s, gắn mãi không đỡ thì giãn dần tới 5 phút.
import Foundation
import os

final class TapGuard {
    let name: String
    /// Gỡ móc cũ + gắn móc mới (chạy trên luồng chính)
    var onDead: (() -> Void)?

    private var lock = os_unfair_lock_s()
    private var lastSeen = 0.0
    private var disables: [Double] = []
    private var reenablePending = false
    private var missed = 0
    private var lastRearm = -1e9
    private var rearmGap = 10.0

    init(_ name: String) { self.name = name }

    static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// Chờ bao lâu trước khi bật lại, theo số lần bị tắt trong 1 phút
    static func backoff(_ n: Int) -> Double { n <= 3 ? 0 : min(30, pow(2, Double(n - 4))) }

    /// Bộ bắt vừa nhận 1 sự kiện (gọi đầu hàm xử lý của tap)
    func seen() {
        let t = Self.now
        os_unfair_lock_lock(&lock); lastSeen = t; os_unfair_lock_unlock(&lock)
    }

    /// Vừa gắn móc mới → xoá đếm hụt
    func reset() {
        let t = Self.now
        os_unfair_lock_lock(&lock); lastSeen = t; missed = 0; os_unfair_lock_unlock(&lock)
    }

    /// macOS vừa tắt bộ bắt
    func disabled(_ type: CGEventTypeLike, enable: @escaping () -> Void) {
        let t = Self.now
        os_unfair_lock_lock(&lock)
        disables = disables.filter { t - $0 < 60 } + [t]
        let n = disables.count
        let wait = Self.backoff(n)
        let already = reenablePending
        if wait > 0 { reenablePending = true }
        os_unfair_lock_unlock(&lock)
        let why = type == .timeout ? "chạy chậm" : "người dùng"
        if wait == 0 {
            Log.info("BỘ BẮT", "macOS tạm tắt bộ bắt \(name) (\(why)) → bật lại ngay")
            enable(); return
        }
        guard !already else { return }
        Log.info("BỘ BẮT", "macOS tắt bộ bắt \(name) \(n) lần trong 1 phút (\(why)) → chờ \(Int(wait)) s rồi bật lại")
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [self] in
            os_unfair_lock_lock(&lock); reenablePending = false; os_unfair_lock_unlock(&lock)
            enable()
        }
    }

    /// HID vừa thấy chuột thật bấm / lăn (luồng chính) → 0,5 s sau kiểm bộ bắt đã nhận chưa
    func hidSaw() {
        let t = Self.now
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            let now = Self.now
            os_unfair_lock_lock(&lock)
            if lastSeen >= t - 0.5 { missed = 0; rearmGap = 10; os_unfair_lock_unlock(&lock); return }
            missed += 1
            let dead = missed >= 3 && now - lastRearm >= rearmGap
            if dead { missed = 0; lastRearm = now; rearmGap = min(300, rearmGap * 2) }
            os_unfair_lock_unlock(&lock)
            if dead {
                Log.info("BỘ BẮT", "bộ bắt \(name) chết lặng: chuột bấm/lăn 3 lần mà bộ bắt không nhận → gắn lại")
                onDead?()
            }
        }
    }
}

/// Loại «bị tắt» gọn cho TapGuard (khỏi kéo CoreGraphics vào phần thử logic)
enum CGEventTypeLike { case timeout, user }

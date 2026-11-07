import Foundation

/// 核心判定引擎：不断连，只靠 RSSI 强弱决定锁车/解锁
/// 带滞回（hysteresis）+ 去抖（连续满足才动作），避免信号抖动反复触发
final class LockEngine {

    static let shared = LockEngine()

    enum Action {
        case lock
        case unlock
    }

    // ====== 可调参数（App 内滑杆会实时改这几个）======
    var lockRSSI: Int = -75          // 低于此值 → 判定"走远"
    var unlockRSSI: Int = -60        // 高于此值 → 判定"走近"
    var lockHold: TimeInterval = 15  // 弱信号持续多久才锁车（秒）
    var unlockHold: TimeInterval = 1.5 // 强信号持续多久才解锁（秒）
    var enabled: Bool = true

    private var weakSince: Date?
    private var strongSince: Date?
    private var lastAction: String = ""

    private init() {}

    func reset() {
        weakSince = nil
        strongSince = nil
        lastAction = ""
    }

    /// 喂一个 RSSI，返回需要执行的动作；nil 表示不动
    func feed(rssi: Int) -> Action? {
        guard enabled else { return nil }
        let now = Date()

        if rssi < lockRSSI {
            strongSince = nil
            if weakSince == nil { weakSince = now }
            if let w = weakSince,
               now.timeIntervalSince(w) >= lockHold,
               lastAction != "lock" {
                lastAction = "lock"
                weakSince = nil
                return .lock
            }
        } else if rssi > unlockRSSI {
            weakSince = nil
            if strongSince == nil { strongSince = now }
            if let s = strongSince,
               now.timeIntervalSince(s) >= unlockHold,
               lastAction != "unlock" {
                lastAction = "unlock"
                strongSince = nil
                return .unlock
            }
        } else {
            // 滞回区：两个计时器都不动，防抖
        }
        return nil
    }
}

import Foundation
import CoreBluetooth
import UserNotifications
import UIKit

/// 蓝牙管理器：扫描 → 连接 → 轮询 RSSI → 触发引擎 → 发指令
final class BleManager: NSObject, ObservableObject,
                        CBCentralManagerDelegate, CBPeripheralDelegate {

    static let shared = BleManager()

    // ====== 状态 ======
    @Published var status: String = "待启动"
    @Published var lastRSSI: Int = 0
    @Published var deviceName: String = "-"
    @Published var logs: [String] = []
    @Published var isConnected: Bool = false

    // ====== 参数（界面可改，存 UserDefaults）======
    @Published var namePrefix: String = "BYD"
    @Published var serviceUUID: String = "0000ffe0-0000-1000-8000-00805f9b34fb"
    @Published var charUUID: String = "0000ffe1-0000-1000-8000-00805f9b34fb"
    @Published var lockHex: String = "AA0100AB"
    @Published var unlockHex: String = "AA0200AC"
    @Published var pollInterval: Double = 2.0

    // ====== 内部 ======
    private var central: CBCentralManager!
    private var car: CBPeripheral?
    private var chr: CBCharacteristic?
    private var pollTimer: Timer?

    private let store = UserDefaults.standard

    override init() {
        super.init()

        // 从 UserDefaults 恢复参数
        if let v = store.string(forKey: "namePrefix") { namePrefix = v }
        if let v = store.string(forKey: "serviceUUID") { serviceUUID = v }
        if let v = store.string(forKey: "charUUID") { charUUID = v }
        if let v = store.string(forKey: "lockHex") { lockHex = v }
        if let v = store.string(forKey: "unlockHex") { unlockHex = v }
        if let v = store.object(forKey: "pollInterval") as? Double { pollInterval = v }

        central = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "yb.bydlock.central",
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )

        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - 外部接口

    func saveParams() {
        store.set(namePrefix, forKey: "namePrefix")
        store.set(serviceUUID, forKey: "serviceUUID")
        store.set(charUUID, forKey: "charUUID")
        store.set(lockHex, forKey: "lockHex")
        store.set(unlockHex, forKey: "unlockHex")
        store.set(pollInterval, forKey: "pollInterval")
        log("参数已保存")
    }

    func start() {
        guard central.state == .poweredOn else {
            status = "蓝牙未就绪：\(stateText(central.state))"
            log(status)
            return
        }
        beginScan()
    }

    func stop() {
        stopPolling()
        if let c = central, let p = car {
            c.cancelPeripheralConnection(p)
        }
        weakReset()
    }

    func rescan() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.start() }
    }

    // MARK: - 扫描

    private func beginScan() {
        status = "扫描中，前缀：\(namePrefix)"
        log(status)
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        status = "蓝牙状态：\(stateText(central.state))"
        log(status)
        if central.state == .poweredOn { beginScan() }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {

        let advName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let n = peripheral.name ?? advName

        guard !n.isEmpty, n.hasPrefix(namePrefix) else { return }

        if car == nil {
            car = peripheral
            peripheral.delegate = self
            deviceName = n
            central.stopScan()
            status = "发现 \(n)，连接中…"
            log(status)
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        status = "已连接，发现服务…"
        log(status)
        let svc = CBUUID(string: serviceUUID)
        peripheral.discoverServices([svc])
        startPolling()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        isConnected = false
        status = "已断开，3 秒后重连"
        log(status)
        stopPolling()
        chr = nil
        car = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.beginScan() }
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        isConnected = false
        car = nil
        status = "连接失败，2 秒后重试"
        log(status)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.beginScan() }
    }

    /// 后台被系统恢复时调用
    func centralManager(_ central: CBCentralManager,
                        willRestoreState dict: [String: Any]) {
        if let list = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let p = list.first {
            car = p
            p.delegate = self
            isConnected = true
            status = "后台恢复连接"
            log(status)
            startPolling()
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            log("发现服务失败：\(error!.localizedDescription)")
            return
        }
        let ch = CBUUID(string: charUUID)
        peripheral.services?.forEach {
            peripheral.discoverCharacteristics([ch], for: $0)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        service.characteristics?.forEach { c in
            if c.uuid == CBUUID(string: charUUID) {
                chr = c
                log("找到写入特征值")
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didReadRSSI RSSI: NSNumber,
                    error: Error?) {
        guard error == nil else { return }
        let r = RSSI.intValue
        lastRSSI = r

        // 只在整数值变化时才写日志，避免刷屏
        if abs(r - lastLoggedRSSI) >= 3 {
            lastLoggedRSSI = r
            log("RSSI \(r)")
        }

        if let action = LockEngine.shared.feed(rssi: r) {
            switch action {
            case .lock:
                sendHex(lockHex)
                log("→→ 锁车（RSSI \(r)）")
                notify("已锁车", "信号 \(r) dBm")
            case .unlock:
                sendHex(unlockHex)
                log("→→ 解锁（RSSI \(r)）")
                notify("已解锁", "信号 \(r) dBm")
            }
        }
    }

    private var lastLoggedRSSI: Int = 999

    // MARK: - 轮询

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.car?.readRSSI()
        }
        if let t = pollTimer {
            RunLoop.main.add(t, forMode: .common)
        }
        log("开始轮询 RSSI，间隔 \(pollInterval)s")
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - 发指令

    private func sendHex(_ hex: String) {
        guard let p = car, let c = chr else {
            log("指令未发送：未连接或无特征值")
            return
        }
        guard let data = Data(hexString: hex) else {
            log("指令格式错误：\(hex)")
            return
        }
        p.writeValue(data, for: c, type: .withResponse)
        log("已发送 \(hex)")
    }

    /// 测试：立即发一次锁车
    func testLock() { sendHex(lockHex) }
    /// 测试：立即发一次解锁
    func testUnlock() { sendHex(unlockHex) }

    // MARK: - 工具

    private func weakReset() {
        LockEngine.shared.reset()
        status = "已停止"
        log(status)
    }

    private func stateText(_ s: CBManagerState) -> String {
        switch s {
        case .poweredOn:  return "开启"
        case .poweredOff: return "关闭"
        case .unauthorized: return "未授权"
        case .unsupported: return "不支持"
        case .resetting: return "重置中"
        default: return "未知"
        }
    }

    private func log(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(s)"
        DispatchQueue.main.async {
            self.logs.insert(line, at: 0)
            if self.logs.count > 300 { self.logs.removeLast() }
        }
    }

    private func notify(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: c,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}

// MARK: - Hex 转换

extension Data {
    init?(hexString: String) {
        let clean = hexString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: ",", with: "")
            .uppercased()
        guard clean.count % 2 == 0, !clean.isEmpty else { return nil }
        var bytes = [UInt8]()
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let b = UInt8(clean[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        self = Data(bytes)
    }
}

import SwiftUI

struct ContentView: View {
    @ObservedObject var ble = BleManager.shared
    @State private var lockRSSI: Double = -75
    @State private var unlockRSSI: Double = -60
    @State private var lockHold: Double = 15
    @State private var unlockHold: Double = 1.5
    @State private var engineOn: Bool = true
    @State private var showSettings = false

    var body: some View {
        NavigationView {
            List {
                statusSection
                thresholdSection
                timeSection
                testSection
                logSection
            }
            .navigationTitle("BYD Lock")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(ble: ble)
            }
            .onAppear {
                LockEngine.shared.lockRSSI = Int(lockRSSI)
                LockEngine.shared.unlockRSSI = Int(unlockRSSI)
                LockEngine.shared.lockHold = lockHold
                LockEngine.shared.unlockHold = unlockHold
                ble.start()
            }
        }
    }

    // MARK: - 状态

    private var statusSection: some View {
        Section(header: Text("Status")) {
            HStack {
                Circle()
                    .fill(ble.isConnected ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(ble.status).font(.subheadline)
            }
            HStack {
                Text("Device")
                Spacer()
                Text(ble.deviceName).foregroundColor(.secondary)
            }
            HStack {
                Text("RSSI")
                Spacer()
                Text("\(ble.lastRSSI) dBm")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(rssiColor(ble.lastRSSI))
            }
            HStack(spacing: 12) {
                Button("Start") { ble.start() }
                    .buttonStyle(.borderedProminent)
                Button("Rescan") { ble.rescan() }
                    .buttonStyle(.bordered)
                Button("Stop") { ble.stop() }
                    .buttonStyle(.bordered)
                    .tint(.gray)
            }
        }
    }

    // MARK: - 阈值

    private var thresholdSection: some View {
        Section(
            header: Text("Thresholds"),
            footer: Text("Below lock threshold long enough → lock. Above unlock threshold → unlock. Between them is the hysteresis zone.")
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Lock threshold")
                    Spacer()
                    Text("\(Int(lockRSSI)) dBm")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.red)
                }
                Slider(value: $lockRSSI, in: -100 ... -40, step: 1) { _ in
                } onEditingChanged: { _ in
                    LockEngine.shared.lockRSSI = Int(lockRSSI)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Unlock threshold")
                    Spacer()
                    Text("\(Int(unlockRSSI)) dBm")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.green)
                }
                Slider(value: $unlockRSSI, in: -100 ... -40, step: 1) { _ in
                } onEditingChanged: { _ in
                    LockEngine.shared.unlockRSSI = Int(unlockRSSI)
                }
            }
        }
    }

    // MARK: - 时间

    private var timeSection: some View {
        Section(
            header: Text("Timing"),
            footer: Text("Lock hold: how long the weak signal must persist before locking. Unlock hold: same for unlocking.")
        ) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Lock hold")
                    Spacer()
                    Text("\(Int(lockHold)) s").foregroundColor(.secondary)
                }
                Slider(value: $lockHold, in: 3 ... 60, step: 1) { _ in
                } onEditingChanged: { _ in
                    LockEngine.shared.lockHold = lockHold
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Unlock hold")
                    Spacer()
                    Text(String(format: "%.1f s", unlockHold)).foregroundColor(.secondary)
                }
                Slider(value: $unlockHold, in: 0.5 ... 10, step: 0.5) { _ in
                } onEditingChanged: { _ in
                    LockEngine.shared.unlockHold = unlockHold
                }
            }

            Toggle("Engine enabled", isOn: $engineOn)
                .onChange(of: engineOn) { newValue in
                    LockEngine.shared.enabled = newValue
                }
        }
    }

    // MARK: - 测试

    private var testSection: some View {
        Section(
            header: Text("Manual test"),
            footer: Text("If the car does not react, the UUID or command bytes are wrong. Grab them from the original app.")
        ) {
            Button("Send LOCK command") { ble.testLock() }
            Button("Send UNLOCK command") { ble.testUnlock() }
        }
    }

    // MARK: - 日志

    private var logSection: some View {
        Section(header: Text("Log")) {
            ForEach(Array(ble.logs.prefix(60).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func rssiColor(_ v: Int) -> Color {
        if v == 0 { return .secondary }
        if v > -60 { return .green }
        if v > -75 { return .orange }
        return .red
    }
}

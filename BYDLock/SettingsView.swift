import SwiftUI

struct SettingsView: View {
    @ObservedObject var ble: BleManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("设备匹配"),
                        footer: Text("车机蓝牙名称的前缀。比亚迪一般是 BYD 开头，也可以填 HAN 之类。填错会扫不到车。")) {
                    HStack {
                        Text("名称前缀")
                        Spacer()
                        TextField("BYD", text: $ble.namePrefix)
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                    }
                }

                Section(header: Text("服务 UUID"),
                        footer: Text("从原 App 反编译结果里替换。默认值只是常见透传服务的占位。")) {
                    TextField("Service UUID", text: $ble.serviceUUID)
                        .font(.system(.footnote, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("特征 UUID")) {
                    TextField("Characteristic UUID", text: $ble.charUUID)
                        .font(.system(.footnote, design: .monospaced))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }

                Section(header: Text("指令（十六进制）"),
                        footer: Text("格式：连续的十六进制串，如 AA0100AB。锁车/解锁各一条。")) {
                    HStack {
                        Text("锁车")
                        Spacer()
                        TextField("AA0100AB", text: $ble.lockHex)
                            .font(.system(.footnote, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.allCharacters)
                    }
                    HStack {
                        Text("解锁")
                        Spacer()
                        TextField("AA0200AC", text: $ble.unlockHex)
                            .font(.system(.footnote, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            .autocapitalization(.allCharacters)
                    }
                }

                Section(header: Text("轮询间隔"),
                        footer: Text("越小反应越快，也越费电。建议 2 秒。")) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("间隔")
                            Spacer()
                            Text(String(format: "%.1f 秒", ble.pollInterval))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $ble.pollInterval, in: 0.5 ... 10, step: 0.5)
                    }
                }
            }
            .navigationTitle("参数设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        ble.saveParams()
                        ble.rescan()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

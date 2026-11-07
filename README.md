# BYDLock — iOS 蓝牙 RSSI 无感锁车

## 是什么
iPhone 通过 CoreBluetooth 持续连接车机蓝牙，轮询 RSSI 信号强度，
按阈值自动发送锁车/解锁指令。**不需要断开蓝牙**，靠信号强弱判定人走远了没有。

## 直接拿 ipa（不用 Mac）

1. GitHub 建一个新仓库（Private 也行）
2. 把这个目录所有文件上传（保持目录结构）
3. 仓库 → Actions → `Build IPA` → Run workflow
4. 等约 5 分钟 → 底部 Artifacts → 下载 `BYDLock-unsigned-ipa`
5. 解压得到 `BYDLock.ipa` → 传到手机 → TrollStore 安装

## TrollStore 安装

```
文件 App → 长按 ipa → 共享 → TrollStore → Install
```

装不上时：
```
TrollStore → 右上角 + → Install IPA File → 选 ipa
```

## 首次配置

打开 App 后点右上角齿轮：

| 项目 | 说明 |
|---|---|
| 名称前缀 | 车机蓝牙名前缀，默认 `BYD`。扫不到就改成 `HAN` 或全名 |
| Service UUID | 默认是常见透传服务，需按实际替换 |
| Characteristic UUID | 同上 |
| 锁车/解锁指令 | 十六进制串，如 `AA0100AB` |

## 调参建议

| 参数 | 默认 | 效果 |
|---|---|---|
| 锁车阈值 | -75 dBm | 调大（如 -70）锁得更早；调小（如 -85）锁得更晚 |
| 解锁阈值 | -60 dBm | 调大（如 -55）解锁更谨慎；调小（如 -70）解锁更早 |
| 锁车保持 | 15 秒 | 弱信号持续这么久才锁，防路过误锁 |
| 解锁保持 | 1.5 秒 | 防信号抖动反复解锁 |
| 轮询间隔 | 2 秒 | 越小越灵敏，也越耗电 |

**首次实车调试步骤**：先点「启动」，走近车看 RSSI 数值变化，
记下"在车边"和"走开 5 米"分别是多少，再据此设定两个阈值。

## 关于 UUID 和指令字节

默认值只是占位。真车需要用下面的方法拿到：

1. 安卓手机装官方/破解版 App
2. 开「开发者选项 → 启用蓝牙 HCI 侦听日志」
3. 操作一次锁车/解锁
4. 抓 `btsnoop_hci.log`，用 Wireshark 打开看 GATT 写入
5. 把 UUID 和 payload 填进 App 设置

## 已知限制

- iOS 后台蓝牙连接会被系统在某些情况下挂起，`bluetooth-central` 后台模式已开启，
  但仍建议保持在后台连续运行，不要手动划掉
- 若车机协议带认证握手（challenge-response），本 App 无法直接通过，
  需要额外实现认证流程

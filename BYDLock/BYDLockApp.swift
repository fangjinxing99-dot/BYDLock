import SwiftUI
import UIKit

@main
struct BYDLockApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var bgHold = BackgroundHold()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    bgHold.begin()
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                BleManager.shared.start()
            case .background:
                // 进入后台时靠 bluetooth-central 后台模式维持 BLE 连接
                break
            default:
                break
            }
        }
    }
}

/// 用 beginBackgroundTask 尽量延长后台存活，配合 bluetooth-central 效果更好
final class BackgroundHold: ObservableObject {
    private var taskId: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        end()
        taskId = UIApplication.shared.beginBackgroundTask(withName: "bydlock") { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard taskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskId)
        taskId = .invalid
    }
}

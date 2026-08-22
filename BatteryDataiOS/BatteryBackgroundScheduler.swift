import BackgroundTasks
import Foundation
import UIKit

enum BatteryBackgroundScheduler {
    static let refreshIdentifier = "com.DmytroIziuk.BatteryData.iOS.refresh"
    private static let storeFilename = "battery_ios_history_v1.json"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            scheduleNextRefresh()
            handle(refreshTask)
        }
    }

    static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        let completion = BackgroundTaskCompletion(task: task)
        task.expirationHandler = {
            completion.finish(success: false)
        }

        setBatteryMonitoringEnabled()
        guard completion.isFinished == false else { return }

        let provider = CompositeBatteryProvider(
            publicProvider: PublicBatteryProvider(),
            privateProvider: PrivateBatteryProvider()
        )
        let store = JSONBatteryHistoryStore(filename: storeFilename)

        var payload = provider.readSnapshot(now: Date())
        payload.snapshot = BatteryETAEstimator.applyingEstimate(
            to: payload.snapshot,
            history: store.loadSnapshots()
        )
        payload.diagnostics = BatteryDiagnostics.refined(payload.diagnostics, using: payload.snapshot)
        guard completion.isFinished == false else { return }
        do {
            try store.append(payload.snapshot)
            completion.finish(success: true)
        } catch {
            completion.finish(success: false)
        }
    }

    private static func setBatteryMonitoringEnabled() {
        let enable: @MainActor () -> Void = {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                enable()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    enable()
                }
            }
        }
    }
}

private final class BackgroundTaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private weak var task: BGAppRefreshTask?
    private var finished = false

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    var isFinished: Bool {
        lock.withLock { finished }
    }

    func finish(success: Bool) {
        let taskToFinish = lock.withLock { () -> BGAppRefreshTask? in
            guard finished == false else { return nil }
            finished = true
            return task
        }

        guard let taskToFinish else { return }
        taskToFinish.expirationHandler = nil
        taskToFinish.setTaskCompleted(success: success)
    }
}

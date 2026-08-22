import Combine
import Foundation

protocol BatteryMetricsProvider {
    func readSnapshot(now: Date) -> BatteryMetricsPayload
}

enum BatteryRefreshReason: String {
    case launch
    case manual
    case foregroundTimer
    case sceneActivation
    case batteryEvent
    case backgroundTask
}

@MainActor
final class BatteryCollectionCoordinator {
    var onUpdate: ((BatteryMetricsPayload, [BatterySnapshot]) -> Void)?

    private let provider: BatteryMetricsProvider
    private let store: BatteryHistoryStore
    private let now: () -> Date
    private let foregroundRefreshInterval: TimeInterval
    private var timer: AnyCancellable?
    private var isRunning = false

    init(
        provider: BatteryMetricsProvider,
        store: BatteryHistoryStore,
        foregroundRefreshInterval: TimeInterval,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.store = store
        self.foregroundRefreshInterval = foregroundRefreshInterval
        self.now = now
    }

    func start() {
        guard isRunning == false else { return }
        isRunning = true
        startTimerIfNeeded()
        refresh(reason: .launch)
    }

    func stop() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }

    func refresh(reason: BatteryRefreshReason) {
        var payload = provider.readSnapshot(now: now())
        let existingHistory = store.loadSnapshots()
        payload.snapshot = BatteryETAEstimator.applyingEstimate(
            to: payload.snapshot,
            history: existingHistory
        )
        payload.diagnostics = BatteryDiagnostics.refined(payload.diagnostics, using: payload.snapshot)
        let updatedHistory = (try? store.append(payload.snapshot)) ?? existingHistory
        onUpdate?(payload, updatedHistory)
    }

    private func startTimerIfNeeded() {
        guard foregroundRefreshInterval > 0 else { return }
        timer?.cancel()
        timer = Timer.publish(every: foregroundRefreshInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh(reason: .foregroundTimer)
            }
    }
}

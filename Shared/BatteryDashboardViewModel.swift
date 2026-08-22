import Combine
import Foundation

@MainActor
final class BatteryDashboardViewModel: ObservableObject {
    @Published private(set) var currentSnapshot: BatterySnapshot?
    @Published private(set) var history: [BatterySnapshot]
    @Published private(set) var diagnostics: [BatteryMetricAvailability]

    private let coordinator: BatteryCollectionCoordinator

    init(coordinator: BatteryCollectionCoordinator, store: BatteryHistoryStore) {
        let persistedHistory = store.loadSnapshots()
        self.coordinator = coordinator
        _history = Published(initialValue: persistedHistory)
        _currentSnapshot = Published(initialValue: persistedHistory.last)
        _diagnostics = Published(initialValue: BatteryDiagnostics.defaults())

        coordinator.onUpdate = { [weak self] payload, history in
            self?.currentSnapshot = payload.snapshot
            self?.history = history
            self?.diagnostics = payload.diagnostics
        }
    }

    func start() {
        coordinator.start()
    }

    func stop() {
        coordinator.stop()
    }

    func refresh(_ reason: BatteryRefreshReason = .manual) {
        coordinator.refresh(reason: reason)
    }

    var sessions: [BatterySessionSummary] {
        BatterySessionBuilder.build(from: history)
    }
}

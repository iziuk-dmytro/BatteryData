import SwiftUI
import UIKit

@main
struct BatteryDataiOSApp: App {
    @StateObject private var model: BatteryDashboardViewModel

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true

        let store = JSONBatteryHistoryStore(filename: "battery_ios_history_v1.json")
        let provider = CompositeBatteryProvider(
            publicProvider: PublicBatteryProvider(),
            privateProvider: PrivateBatteryProvider()
        )
        let coordinator = BatteryCollectionCoordinator(
            provider: provider,
            store: store,
            foregroundRefreshInterval: 300
        )

        _model = StateObject(wrappedValue: BatteryDashboardViewModel(coordinator: coordinator, store: store))
        BatteryBackgroundScheduler.register()
    }

    var body: some Scene {
        WindowGroup {
            BatteryDataiOSRootView(model: model)
        }
    }
}

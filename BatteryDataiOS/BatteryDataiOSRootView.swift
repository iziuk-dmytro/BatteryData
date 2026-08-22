import SwiftUI
import UIKit

struct BatteryDataiOSRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: BatteryDashboardViewModel

    var body: some View {
        TabView {
            NowBatteryView(model: model)
                .tabItem {
                    Label("Now", systemImage: "bolt.batteryblock")
                }

            HistoryBatteryView(model: model)
                .tabItem {
                    Label("History", systemImage: "chart.xyaxis.line")
                }

            DiagnosticsBatteryView(model: model)
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
        }
        .onAppear {
            model.start()
        }
        .onDisappear {
            model.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            guard scenePhase == .active else { return }
            model.refresh(.batteryEvent)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            guard scenePhase == .active else { return }
            model.refresh(.batteryEvent)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            guard scenePhase == .active else { return }
            model.refresh(.batteryEvent)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                model.start()
            case .background:
                model.stop()
                BatteryBackgroundScheduler.scheduleNextRefresh()
            case .inactive:
                model.stop()
            @unknown default:
                break
            }
        }
    }
}

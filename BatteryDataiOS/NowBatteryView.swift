import SwiftUI

struct NowBatteryView: View {
    @ObservedObject var model: BatteryDashboardViewModel

    private var snapshot: BatterySnapshot? {
        model.currentSnapshot
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    currentCard
                    lowLevelCard
                    etaCard
                }
                .padding()
            }
            .navigationTitle("Battery")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh") {
                        model.refresh()
                    }
                }
            }
        }
    }

    private var currentCard: some View {
        GroupBox("Current") {
            VStack(alignment: .leading, spacing: 10) {
                metricRow("Level", snapshot?.batteryLevelText ?? "--")
                metricRow("State", snapshot?.chargeState.displayName ?? "Unknown")
                metricRow(
                    "Low Power Mode",
                    snapshot.map { $0.isLowPowerModeEnabled ? "On" : "Off" } ?? "--"
                )
                metricRow("Updated", snapshot?.timestamp.formatted(date: .omitted, time: .standard) ?? "--")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var lowLevelCard: some View {
        GroupBox("Low-Level Metrics") {
            VStack(alignment: .leading, spacing: 10) {
                metricRow("Voltage", snapshot?.voltageText ?? "--")
                metricRow("Amperage", snapshot?.amperageText ?? "--")
                metricRow("Power", snapshot?.wattsText ?? "--")
                metricRow("Cycle Count", snapshot?.cycleCount.map(String.init) ?? "--")
                metricRow("Current Capacity", snapshot?.currentCapacityText ?? "--")
                metricRow("Max Capacity", snapshot?.maxCapacityText ?? "--")
                metricRow("Design Capacity", snapshot?.designCapacityText ?? "--")
                metricRow("Health", snapshot?.healthText ?? "--")

                if let source = snapshot?.lowLevelSourceDescription {
                    Text(source)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var etaCard: some View {
        GroupBox("ETA") {
            VStack(alignment: .leading, spacing: 10) {
                metricRow("Time to Empty", snapshot?.timeToEmptyText ?? "--")
                metricRow("Time to Full", snapshot?.timeToFullText ?? "--")
                metricRow("ETA Source", snapshot?.etaLabelText ?? "Unavailable")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

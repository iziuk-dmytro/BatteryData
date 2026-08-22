import SwiftUI

struct DiagnosticsBatteryView: View {
    @ObservedObject var model: BatteryDashboardViewModel

    var body: some View {
        NavigationStack {
            List(model.diagnostics) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(item.metric.title)
                            .font(.headline)
                        Spacer()
                        Text(item.source.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(statusText(item.status))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(color(for: item.status))

                    Text(item.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Diagnostics")
        }
    }

    private func statusText(_ status: BatteryMetricStatus) -> String {
        switch status {
        case .available: return "Available"
        case .estimated: return "Estimated"
        case .unavailable: return "Unavailable"
        }
    }

    private func color(for status: BatteryMetricStatus) -> Color {
        switch status {
        case .available: return .green
        case .estimated: return .orange
        case .unavailable: return .secondary
        }
    }
}

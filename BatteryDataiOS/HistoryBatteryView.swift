import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct HistoryBatteryView: View {
    @ObservedObject var model: BatteryDashboardViewModel

    var body: some View {
        let sessions = model.sessions

        NavigationStack {
            List {
                if model.history.isEmpty == false {
                    Section("Battery Level") {
                        chartSection
                            .frame(height: 220)
                    }
                }

                Section("Recent Sessions") {
                    if sessions.isEmpty {
                        Text("No sessions captured yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sessions.prefix(10)) { session in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.chargeState.displayName)
                                    .font(.headline)
                                Text(sessionDateRange(session))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Level \(levelText(session.openingLevel)) → \(levelText(session.closingLevel))")
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    @ViewBuilder
    private var chartSection: some View {
        #if canImport(Charts)
        Chart(model.history) { snapshot in
            if let batteryLevel = snapshot.batteryLevel {
                LineMark(
                    x: .value("Time", snapshot.timestamp),
                    y: .value("Battery", batteryLevel)
                )
                .interpolationMethod(.linear)
            }
        }
        #else
        Text("Charts framework is unavailable for this build.")
            .foregroundStyle(.secondary)
        #endif
    }

    private func levelText(_ level: Int?) -> String {
        level.map { "\($0)%" } ?? "--"
    }

    private func sessionDateRange(_ session: BatterySessionSummary) -> String {
        let start = session.startedAt.formatted(date: .abbreviated, time: .shortened)
        let endDateStyle: Date.FormatStyle.DateStyle = Calendar.current.isDate(
            session.startedAt,
            inSameDayAs: session.endedAt
        ) ? .omitted : .abbreviated
        let end = session.endedAt.formatted(date: endDateStyle, time: .shortened)
        return "\(start) – \(end)"
    }
}

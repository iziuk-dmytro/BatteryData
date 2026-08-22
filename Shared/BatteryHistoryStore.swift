import Foundation

protocol BatteryHistoryStore: AnyObject {
    func loadSnapshots() -> [BatterySnapshot]
    @discardableResult
    func append(_ snapshot: BatterySnapshot) throws -> [BatterySnapshot]
}

final class JSONBatteryHistoryStore: BatteryHistoryStore, @unchecked Sendable {
    private let fileURL: URL
    private static let queue = DispatchQueue(label: "BatteryHistoryStore.queue", qos: .utility)
    private let maxSnapshotCount: Int
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(filename: String, maxSnapshotCount: Int = 2048, baseDirectory: URL? = nil) {
        self.maxSnapshotCount = max(1, maxSnapshotCount)
        let rootDirectory = baseDirectory ?? Self.defaultDirectory()
        self.fileURL = rootDirectory.appendingPathComponent(filename)
    }

    func loadSnapshots() -> [BatterySnapshot] {
        Self.queue.sync {
            guard let data = try? Data(contentsOf: fileURL) else { return [] }
            return (try? decoder.decode([BatterySnapshot].self, from: data)) ?? []
        }
    }

    @discardableResult
    func append(_ snapshot: BatterySnapshot) throws -> [BatterySnapshot] {
        try Self.queue.sync {
            var snapshots = try loadSnapshotsForMutation()
            if let existingIndex = snapshots.firstIndex(where: { $0.timestamp == snapshot.timestamp }) {
                snapshots[existingIndex] = snapshot
            } else {
                snapshots.append(snapshot)
            }
            snapshots.sort { $0.timestamp < $1.timestamp }

            if snapshots.count > maxSnapshotCount {
                snapshots.removeFirst(snapshots.count - maxSnapshotCount)
            }

            let data = try encoder.encode(snapshots)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            return snapshots
        }
    }

    private func loadSnapshotsForMutation() throws -> [BatterySnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([BatterySnapshot].self, from: data)
    }

    private static func defaultDirectory() -> URL {
        let fm = FileManager.default
        return fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
    }
}

struct BatterySessionSummary: Identifiable, Equatable, Sendable {
    let startedAt: Date
    let endedAt: Date
    let chargeState: BatteryChargeState
    let openingLevel: Int?
    let closingLevel: Int?

    var id: Date { startedAt }
}

enum BatterySessionBuilder {
    static func build(from snapshots: [BatterySnapshot]) -> [BatterySessionSummary] {
        guard snapshots.isEmpty == false else { return [] }

        var result: [BatterySessionSummary] = []
        var sessionStart = snapshots[0]
        var previous = snapshots[0]

        for snapshot in snapshots.dropFirst() {
            let shouldSplit = snapshot.chargeState != previous.chargeState
            if shouldSplit {
                result.append(
                    BatterySessionSummary(
                        startedAt: sessionStart.timestamp,
                        endedAt: previous.timestamp,
                        chargeState: sessionStart.chargeState,
                        openingLevel: sessionStart.batteryLevel,
                        closingLevel: previous.batteryLevel
                    )
                )
                sessionStart = snapshot
            }
            previous = snapshot
        }

        result.append(
            BatterySessionSummary(
                startedAt: sessionStart.timestamp,
                endedAt: previous.timestamp,
                chargeState: sessionStart.chargeState,
                openingLevel: sessionStart.batteryLevel,
                closingLevel: previous.batteryLevel
            )
        )

        return result.reversed()
    }
}

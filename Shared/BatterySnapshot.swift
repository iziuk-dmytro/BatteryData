import Foundation

enum BatteryChargeState: String, Codable, CaseIterable, Sendable {
    case unknown
    case unplugged
    case charging
    case full

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .unplugged: return "On Battery"
        case .charging: return "Charging"
        case .full: return "Full"
        }
    }
}

enum BatteryMetricKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case batteryLevel
    case batteryState
    case lowPowerMode
    case voltage
    case amperage
    case watts
    case cycleCount
    case designCapacity
    case maxCapacity
    case currentCapacity
    case healthPercent
    case timeToEmpty
    case timeToFull

    var id: String { rawValue }

    var title: String {
        switch self {
        case .batteryLevel: return "Battery Level"
        case .batteryState: return "Battery State"
        case .lowPowerMode: return "Low Power Mode"
        case .voltage: return "Voltage"
        case .amperage: return "Amperage"
        case .watts: return "Power"
        case .cycleCount: return "Cycle Count"
        case .designCapacity: return "Design Capacity"
        case .maxCapacity: return "Max Capacity"
        case .currentCapacity: return "Current Capacity"
        case .healthPercent: return "Health"
        case .timeToEmpty: return "Time to Empty"
        case .timeToFull: return "Time to Full"
        }
    }
}

enum BatteryMetricSource: String, Codable, Sendable {
    case publicAPI
    case privateAPI
    case estimated
    case merged
    case unavailable

    var displayName: String {
        switch self {
        case .publicAPI: return "Public API"
        case .privateAPI: return "Private Adapter"
        case .estimated: return "Estimated"
        case .merged: return "Merged"
        case .unavailable: return "Unavailable"
        }
    }
}

enum BatteryMetricStatus: String, Codable, Sendable {
    case available
    case estimated
    case unavailable
}

struct BatteryMetricAvailability: Identifiable, Codable, Equatable, Sendable {
    let metric: BatteryMetricKey
    var status: BatteryMetricStatus
    var source: BatteryMetricSource
    var message: String

    var id: String { metric.rawValue }
}

struct BatterySnapshot: Identifiable, Codable, Equatable, Sendable {
    let timestamp: Date
    var batteryLevel: Int?
    var chargeState: BatteryChargeState
    var isLowPowerModeEnabled: Bool
    var voltageMillivolts: Int?
    var amperageMilliamps: Int?
    var watts: Double?
    var cycleCount: Int?
    var designCapacitymAh: Int?
    var maxCapacitymAh: Int?
    var currentCapacitymAh: Int?
    var healthPercent: Int?
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
    var etaSource: BatteryMetricSource?
    var lowLevelSourceDescription: String?

    var id: Date { timestamp }

    var batteryLevelText: String {
        batteryLevel.map { "\($0)%" } ?? "--"
    }

    var voltageText: String {
        voltageMillivolts.map { "\($0) mV" } ?? "--"
    }

    var amperageText: String {
        amperageMilliamps.map { "\($0) mA" } ?? "--"
    }

    var wattsText: String {
        guard let watts else { return "--" }
        let sign = watts >= 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.2f", abs(watts))) W"
    }

    var healthText: String {
        healthPercent.map { "\($0)%" } ?? "--"
    }

    var designCapacityText: String {
        designCapacitymAh.map { "\($0) mAh" } ?? "--"
    }

    var maxCapacityText: String {
        maxCapacitymAh.map { "\($0) mAh" } ?? "--"
    }

    var currentCapacityText: String {
        currentCapacitymAh.map { "\($0) mAh" } ?? "--"
    }

    var timeToEmptyText: String {
        Self.format(minutes: timeToEmptyMinutes)
    }

    var timeToFullText: String {
        Self.format(minutes: timeToFullMinutes)
    }

    var etaLabelText: String {
        etaSource?.displayName ?? BatteryMetricSource.unavailable.displayName
    }

    static func empty(timestamp: Date) -> BatterySnapshot {
        BatterySnapshot(
            timestamp: timestamp,
            batteryLevel: nil,
            chargeState: .unknown,
            isLowPowerModeEnabled: false,
            voltageMillivolts: nil,
            amperageMilliamps: nil,
            watts: nil,
            cycleCount: nil,
            designCapacitymAh: nil,
            maxCapacitymAh: nil,
            currentCapacitymAh: nil,
            healthPercent: nil,
            timeToEmptyMinutes: nil,
            timeToFullMinutes: nil,
            etaSource: nil,
            lowLevelSourceDescription: nil
        )
    }

    static func merged(publicSnapshot: BatterySnapshot, privateSnapshot: BatterySnapshot) -> BatterySnapshot {
        var merged = publicSnapshot
        merged.voltageMillivolts = privateSnapshot.voltageMillivolts ?? merged.voltageMillivolts
        merged.amperageMilliamps = privateSnapshot.amperageMilliamps ?? merged.amperageMilliamps
        merged.watts = privateSnapshot.watts ?? merged.watts
        merged.cycleCount = privateSnapshot.cycleCount ?? merged.cycleCount
        merged.designCapacitymAh = privateSnapshot.designCapacitymAh ?? merged.designCapacitymAh
        merged.maxCapacitymAh = privateSnapshot.maxCapacitymAh ?? merged.maxCapacitymAh
        merged.currentCapacitymAh = privateSnapshot.currentCapacitymAh ?? merged.currentCapacitymAh
        merged.timeToEmptyMinutes = privateSnapshot.timeToEmptyMinutes ?? merged.timeToEmptyMinutes
        merged.timeToFullMinutes = privateSnapshot.timeToFullMinutes ?? merged.timeToFullMinutes
        merged.lowLevelSourceDescription = privateSnapshot.lowLevelSourceDescription ?? merged.lowLevelSourceDescription

        if let explicitHealth = privateSnapshot.healthPercent ?? merged.healthPercent {
            merged.healthPercent = explicitHealth
        } else if let design = merged.designCapacitymAh, let max = merged.maxCapacitymAh, design > 0 {
            merged.healthPercent = Int((Double(max) / Double(design) * 100.0).rounded())
        }

        if merged.watts == nil,
           let voltage = merged.voltageMillivolts,
           let amperage = merged.amperageMilliamps {
            merged.watts = (Double(voltage) * Double(amperage)) / 1_000_000.0
        }

        if privateSnapshot.timeToEmptyMinutes != nil || privateSnapshot.timeToFullMinutes != nil {
            merged.etaSource = .privateAPI
        }

        return merged
    }

    private static func format(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "--" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours)h \(String(format: "%02dm", remainder))" : "\(remainder)m"
    }
}

struct BatteryMetricsPayload: Sendable {
    var snapshot: BatterySnapshot
    var diagnostics: [BatteryMetricAvailability]
}

enum BatteryDiagnostics {
    static func defaults(message: String = "No reading yet.") -> [BatteryMetricAvailability] {
        BatteryMetricKey.allCases.map {
            BatteryMetricAvailability(metric: $0, status: .unavailable, source: .unavailable, message: message)
        }
    }

    static func merged(primary: [BatteryMetricAvailability], secondary: [BatteryMetricAvailability]) -> [BatteryMetricAvailability] {
        let primaryMap = Dictionary(uniqueKeysWithValues: primary.map { ($0.metric, $0) })
        let secondaryMap = Dictionary(uniqueKeysWithValues: secondary.map { ($0.metric, $0) })

        return BatteryMetricKey.allCases.map { key in
            let lhs = primaryMap[key]
            let rhs = secondaryMap[key]
            return preferred(lhs, rhs, for: key)
        }
    }

    static func refined(_ diagnostics: [BatteryMetricAvailability], using snapshot: BatterySnapshot) -> [BatteryMetricAvailability] {
        var map = Dictionary(uniqueKeysWithValues: diagnostics.map { ($0.metric, $0) })

        if snapshot.timeToEmptyMinutes != nil {
            map[.timeToEmpty] = BatteryMetricAvailability(
                metric: .timeToEmpty,
                status: snapshot.etaSource == .estimated ? .estimated : .available,
                source: snapshot.etaSource ?? .unavailable,
                message: snapshot.etaSource == .estimated ? "Estimated from recent history." : "Reported directly by the provider."
            )
        }

        if snapshot.timeToFullMinutes != nil {
            map[.timeToFull] = BatteryMetricAvailability(
                metric: .timeToFull,
                status: snapshot.etaSource == .estimated ? .estimated : .available,
                source: snapshot.etaSource ?? .unavailable,
                message: snapshot.etaSource == .estimated ? "Estimated from recent history." : "Reported directly by the provider."
            )
        }

        if snapshot.watts != nil {
            let source = map[.watts]?.source
            map[.watts] = BatteryMetricAvailability(
                metric: .watts,
                status: .available,
                source: source == .unavailable ? .merged : (source ?? .merged),
                message: "Available in the current snapshot."
            )
        }

        if snapshot.healthPercent != nil {
            let source = map[.healthPercent]?.source
            map[.healthPercent] = BatteryMetricAvailability(
                metric: .healthPercent,
                status: .available,
                source: source == .unavailable ? .merged : (source ?? .merged),
                message: "Calculated from max and design capacity."
            )
        }

        return BatteryMetricKey.allCases.map {
            map[$0] ?? BatteryMetricAvailability(metric: $0, status: .unavailable, source: .unavailable, message: "Unavailable in this build.")
        }
    }

    private static func preferred(
        _ lhs: BatteryMetricAvailability?,
        _ rhs: BatteryMetricAvailability?,
        for key: BatteryMetricKey
    ) -> BatteryMetricAvailability {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if score(lhs) >= score(rhs) { return lhs }
            return rhs
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return BatteryMetricAvailability(
                metric: key,
                status: .unavailable,
                source: .unavailable,
                message: "Unavailable in this build."
            )
        }
    }

    private static func score(_ availability: BatteryMetricAvailability) -> Int {
        switch availability.status {
        case .available: return 3
        case .estimated: return 2
        case .unavailable: return 1
        }
    }
}

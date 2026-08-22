import Foundation

enum AdapterKind: String {
    case magsafe = "MagSafe"
    case usbc = "Power Adapter"
    case unknown = "AC"
}

struct BatteryInfo {
    var percentage: Int?
    var isCharging: Bool?
    var onACPower: Bool?
    var timeToEmptyMin: Int?
    var timeToFullMin: Int?
    var voltage_mV: Int?
    var amperage_mA: Int?
    var watts: Double? {
        guard let v = voltage_mV, let a = amperage_mA else { return nil }
        return (Double(v) * Double(a)) / 1_000_000.0
    }
    var currentCapacity_mAh: Int?
    var cycleCount: Int?
    var designCapacity_mAh: Int?
    var maxCapacity_mAh: Int?
    var temperatureC: Double?
    var healthPercent: Int? {
        guard let d = designCapacity_mAh, let m = maxCapacity_mAh, d > 0 else { return nil }
        let h = (Double(m) / Double(d)) * 100.0
        guard h >= 5, h <= 150 else { return nil }
        return Int(h.rounded())
    }
    var adapterWatts: Int?
    var adapterKind: AdapterKind?

    static let empty = BatteryInfo(
        percentage: nil, isCharging: nil, onACPower: nil,
        timeToEmptyMin: nil, timeToFullMin: nil,
        voltage_mV: nil, amperage_mA: nil, currentCapacity_mAh: nil,
        cycleCount: nil, designCapacity_mAh: nil, maxCapacity_mAh: nil,
        temperatureC: nil,
        adapterWatts: nil, adapterKind: nil
    )

    var statusText: String {
        if let onAC = onACPower, onAC {
            return (isCharging == true) ? "Charging (AC)" : "On AC Power"
        }
        return "On Battery"
    }

    var sfSymbol: String {
        if onACPower == true && isCharging == true { return "bolt.batteryblock.fill" }
        if onACPower == true { return "powerplug" }
        return "battery.100"
    }

    static func format(mins: Int) -> String {
        let h = mins / 60
        let m = mins % 60
        return h > 0 ? "\(h)h \(String(format: "%02dm", m))" : "\(m)m"
    }
}

struct HistorySample: Identifiable {
    let t: Date
    let percent: Int?
    let watts: Double?

    var id: Date { t }
}

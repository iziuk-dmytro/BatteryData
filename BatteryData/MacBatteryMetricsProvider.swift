import Foundation

struct MacBatteryMetricsProvider: BatteryMetricsProvider {
    func readSnapshot(now: Date) -> BatteryMetricsPayload {
        let info = BatteryReader.read() ?? .empty
        let snapshot = BatterySnapshot(
            timestamp: now,
            batteryLevel: info.percentage,
            chargeState: chargeState(for: info),
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            voltageMillivolts: info.voltage_mV,
            amperageMilliamps: info.amperage_mA,
            watts: info.watts,
            cycleCount: info.cycleCount,
            designCapacitymAh: info.designCapacity_mAh,
            maxCapacitymAh: info.maxCapacity_mAh,
            currentCapacitymAh: info.currentCapacity_mAh,
            healthPercent: info.healthPercent,
            timeToEmptyMinutes: info.timeToEmptyMin,
            timeToFullMinutes: info.timeToFullMin,
            etaSource: .publicAPI,
            lowLevelSourceDescription: "Collected from macOS power and IORegistry APIs."
        )

        let diagnostics = BatteryDiagnostics.refined([
            BatteryMetricAvailability(metric: .batteryLevel, status: snapshot.batteryLevel == nil ? .unavailable : .available, source: snapshot.batteryLevel == nil ? .unavailable : .publicAPI, message: "Reported by IOKit."),
            BatteryMetricAvailability(metric: .batteryState, status: snapshot.chargeState == .unknown ? .unavailable : .available, source: snapshot.chargeState == .unknown ? .unavailable : .publicAPI, message: "Reported by IOKit."),
            BatteryMetricAvailability(metric: .lowPowerMode, status: .available, source: .publicAPI, message: "Reported by ProcessInfo."),
            BatteryMetricAvailability(metric: .voltage, status: snapshot.voltageMillivolts == nil ? .unavailable : .available, source: snapshot.voltageMillivolts == nil ? .unavailable : .publicAPI, message: "Read from IORegistry."),
            BatteryMetricAvailability(metric: .amperage, status: snapshot.amperageMilliamps == nil ? .unavailable : .available, source: snapshot.amperageMilliamps == nil ? .unavailable : .publicAPI, message: "Read from IORegistry."),
            BatteryMetricAvailability(metric: .watts, status: snapshot.watts == nil ? .unavailable : .available, source: snapshot.watts == nil ? .unavailable : .publicAPI, message: "Calculated from voltage and amperage."),
            BatteryMetricAvailability(metric: .cycleCount, status: snapshot.cycleCount == nil ? .unavailable : .available, source: snapshot.cycleCount == nil ? .unavailable : .publicAPI, message: "Read from IORegistry."),
            BatteryMetricAvailability(metric: .designCapacity, status: snapshot.designCapacitymAh == nil ? .unavailable : .available, source: snapshot.designCapacitymAh == nil ? .unavailable : .publicAPI, message: "Read from IORegistry."),
            BatteryMetricAvailability(metric: .maxCapacity, status: snapshot.maxCapacitymAh == nil ? .unavailable : .available, source: snapshot.maxCapacitymAh == nil ? .unavailable : .publicAPI, message: "Read from IORegistry."),
            BatteryMetricAvailability(metric: .currentCapacity, status: snapshot.currentCapacitymAh == nil ? .unavailable : .available, source: snapshot.currentCapacitymAh == nil ? .unavailable : .publicAPI, message: "Read from IORegistry."),
            BatteryMetricAvailability(metric: .healthPercent, status: snapshot.healthPercent == nil ? .unavailable : .available, source: snapshot.healthPercent == nil ? .unavailable : .publicAPI, message: "Calculated from max and design capacity."),
            BatteryMetricAvailability(metric: .timeToEmpty, status: snapshot.timeToEmptyMinutes == nil ? .unavailable : .available, source: snapshot.timeToEmptyMinutes == nil ? .unavailable : .publicAPI, message: "Reported by system power APIs."),
            BatteryMetricAvailability(metric: .timeToFull, status: snapshot.timeToFullMinutes == nil ? .unavailable : .available, source: snapshot.timeToFullMinutes == nil ? .unavailable : .publicAPI, message: "Reported by system power APIs."),
        ], using: snapshot)

        return BatteryMetricsPayload(snapshot: snapshot, diagnostics: diagnostics)
    }

    private func chargeState(for info: BatteryInfo) -> BatteryChargeState {
        if info.isCharging == true { return .charging }
        if info.onACPower == true && info.percentage == 100 { return .full }
        if info.onACPower == false { return .unplugged }
        return .unknown
    }
}

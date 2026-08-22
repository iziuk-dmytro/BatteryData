import Foundation
import UIKit

struct PublicBatteryProvider: BatteryMetricsProvider {
    func readSnapshot(now: Date) -> BatteryMetricsPayload {
        let sample = captureBatterySample()

        let snapshot = BatterySnapshot(
            timestamp: now,
            batteryLevel: sample.batteryLevel,
            chargeState: sample.chargeState,
            isLowPowerModeEnabled: sample.isLowPowerModeEnabled,
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
            lowLevelSourceDescription: "Public iOS APIs expose battery level/state, but not low-level battery internals."
        )

        let diagnostics: [BatteryMetricAvailability] = [
            availability(.batteryLevel, sample.batteryLevel != nil, source: .publicAPI, availableMessage: "Reported by UIDevice battery monitoring."),
            availability(.batteryState, sample.chargeState != .unknown, source: .publicAPI, availableMessage: "Reported by UIDevice battery monitoring."),
            availability(.lowPowerMode, true, source: .publicAPI, availableMessage: "Reported by ProcessInfo."),
            availability(.voltage, false, source: .unavailable, unavailableMessage: "Not available from public iOS APIs."),
            availability(.amperage, false, source: .unavailable, unavailableMessage: "Not available from public iOS APIs."),
            availability(.watts, false, source: .unavailable, unavailableMessage: "Not available from public iOS APIs."),
            availability(.cycleCount, false, source: .unavailable, unavailableMessage: "Not available from public iOS APIs."),
            availability(.designCapacity, false, source: .unavailable, unavailableMessage: "Not available from public iOS APIs."),
            availability(.maxCapacity, false, source: .unavailable, unavailableMessage: "Not available from public iOS APIs."),
            availability(.currentCapacity, false, source: .unavailable, unavailableMessage: "Not available from public iOS APIs."),
            availability(.healthPercent, false, source: .unavailable, unavailableMessage: "Not available without a private or external data source."),
            availability(.timeToEmpty, false, source: .unavailable, unavailableMessage: "No direct ETA from public iOS APIs."),
            availability(.timeToFull, false, source: .unavailable, unavailableMessage: "No direct ETA from public iOS APIs."),
        ]

        return BatteryMetricsPayload(snapshot: snapshot, diagnostics: diagnostics)
    }

    private func captureBatterySample() -> (batteryLevel: Int?, chargeState: BatteryChargeState, isLowPowerModeEnabled: Bool) {
        let read: @MainActor () -> (batteryLevel: Int?, chargeState: BatteryChargeState, isLowPowerModeEnabled: Bool) = {
            let device = UIDevice.current
            let level = device.batteryLevel
            let batteryLevel = level >= 0 ? Int((level * 100).rounded()) : nil
            return (
                batteryLevel: batteryLevel,
                chargeState: BatteryChargeState(device.batteryState),
                isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
            )
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                read()
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                read()
            }
        }
    }

    private func availability(
        _ metric: BatteryMetricKey,
        _ isAvailable: Bool,
        source: BatteryMetricSource,
        availableMessage: String = "Available.",
        unavailableMessage: String = "Unavailable."
    ) -> BatteryMetricAvailability {
        BatteryMetricAvailability(
            metric: metric,
            status: isAvailable ? .available : .unavailable,
            source: isAvailable ? source : .unavailable,
            message: isAvailable ? availableMessage : unavailableMessage
        )
    }
}

struct PrivateBatteryProvider: BatteryMetricsProvider {
    func readSnapshot(now: Date) -> BatteryMetricsPayload {
        let snapshot = BatterySnapshot(
            timestamp: now,
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
            lowLevelSourceDescription: "Private provider scaffold is installed, but no internal adapter is configured in this build."
        )

        let unavailableMetrics: [BatteryMetricKey] = [
            .voltage,
            .amperage,
            .watts,
            .cycleCount,
            .designCapacity,
            .maxCapacity,
            .currentCapacity,
            .healthPercent,
            .timeToEmpty,
            .timeToFull,
        ]

        let diagnostics = unavailableMetrics.map {
            BatteryMetricAvailability(
                metric: $0,
                status: .unavailable,
                source: .unavailable,
                message: "Private battery adapter has not been implemented yet for this target."
            )
        }

        return BatteryMetricsPayload(snapshot: snapshot, diagnostics: diagnostics)
    }
}

struct CompositeBatteryProvider: BatteryMetricsProvider {
    let publicProvider: PublicBatteryProvider
    let privateProvider: PrivateBatteryProvider

    func readSnapshot(now: Date) -> BatteryMetricsPayload {
        let resolvedPublic = publicProvider.readSnapshot(now: now)
        let resolvedPrivate = privateProvider.readSnapshot(now: now)

        let snapshot = BatterySnapshot.merged(
            publicSnapshot: resolvedPublic.snapshot,
            privateSnapshot: resolvedPrivate.snapshot
        )

        let diagnostics = BatteryDiagnostics.merged(
            primary: resolvedPrivate.diagnostics,
            secondary: resolvedPublic.diagnostics
        )

        return BatteryMetricsPayload(snapshot: snapshot, diagnostics: diagnostics)
    }
}

extension BatteryChargeState {
    init(_ state: UIDevice.BatteryState) {
        switch state {
        case .charging:
            self = .charging
        case .full:
            self = .full
        case .unplugged:
            self = .unplugged
        case .unknown:
            self = .unknown
        @unknown default:
            self = .unknown
        }
    }
}

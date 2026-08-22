import Foundation

enum BatteryETAEstimator {
    private static let maxSampleCount = 24
    private static let maxSampleGap: TimeInterval = 15 * 60
    private static let maxEstimatedMinutes = 7 * 24 * 60

    static func applyingEstimate(to snapshot: BatterySnapshot, history: [BatterySnapshot]) -> BatterySnapshot {
        guard snapshot.timeToEmptyMinutes == nil, snapshot.timeToFullMinutes == nil else {
            return snapshot
        }
        guard snapshot.chargeState == .charging || snapshot.chargeState == .unplugged else {
            return snapshot
        }

        let relevant = contiguousSamples(endingWith: snapshot, history: history)

        guard relevant.count >= 2,
              let first = relevant.first,
              let last = relevant.last,
              let firstLevel = first.batteryLevel,
              let lastLevel = last.batteryLevel,
              last.timestamp > first.timestamp
        else {
            return snapshot
        }

        let deltaMinutes = last.timestamp.timeIntervalSince(first.timestamp) / 60.0
        guard deltaMinutes > 0 else { return snapshot }

        let rate = Double(lastLevel - firstLevel) / deltaMinutes
        guard rate.isFinite, rate != 0, abs(rate) <= 5 else { return snapshot }

        var estimated = snapshot

        switch snapshot.chargeState {
        case .charging:
            guard rate > 0 else { return snapshot }
            let remaining = max(0, 100 - lastLevel)
            let minutes = Int((Double(remaining) / rate).rounded())
            guard minutes > 0, minutes <= maxEstimatedMinutes else { return snapshot }
            estimated.timeToFullMinutes = minutes
            estimated.etaSource = .estimated
        case .unplugged:
            guard rate < 0 else { return snapshot }
            let minutes = Int((Double(lastLevel) / abs(rate)).rounded())
            guard minutes > 0, minutes <= maxEstimatedMinutes else { return snapshot }
            estimated.timeToEmptyMinutes = minutes
            estimated.etaSource = .estimated
        case .full, .unknown:
            break
        }

        return estimated
    }

    private static func contiguousSamples(
        endingWith snapshot: BatterySnapshot,
        history: [BatterySnapshot]
    ) -> [BatterySnapshot] {
        var reversedSamples = [snapshot]
        var newerTimestamp = snapshot.timestamp

        for candidate in history.reversed() {
            guard candidate.chargeState == snapshot.chargeState else { break }

            let gap = newerTimestamp.timeIntervalSince(candidate.timestamp)
            guard gap >= 0, gap <= maxSampleGap else { break }
            newerTimestamp = candidate.timestamp

            if candidate.batteryLevel != nil {
                reversedSamples.append(candidate)
            }
            if reversedSamples.count == maxSampleCount {
                break
            }
        }

        return Array(reversedSamples.reversed())
    }
}

//
//  SystemProfilerBluetoothReader.swift
//  BatteryData
//
//  Created by Dmytro Izyuk on 17.12.2025.
//

import Foundation
import Darwin

struct AirPodsBatterySnapshot: Equatable {
    var device: Int?
    var left: Int?
    var right: Int?
    var casePct: Int?
}

enum SystemProfilerBluetoothReader {

    private static let processQueue = DispatchQueue(
        label: "SystemProfilerBluetoothReader.process",
        qos: .utility
    )

    // MARK: - JSON (recommended for AirPods)

    /// Uses: /usr/sbin/system_profiler SPBluetoothDataType -json
    static func fetchBluetoothJSON() async -> Data? {
        await runSystemProfiler(arguments: ["SPBluetoothDataType", "-json"])
    }


    /// Parses your JSON shape:
    /// SPBluetoothDataType[0].device_connected = [ { "AirPods Ivanka": { device_address, device_batteryLevelLeft, ... } }, ... ]
    ///
    /// - address: may be "a8-91-..." or "A8:91:..." - it will be normalized internally
    /// - deviceName: optional fallback match by name
    static func parseBattery(jsonData: Data, address: String?, deviceName: String?) -> AirPodsBatterySnapshot? {
        guard
            let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let arr = root["SPBluetoothDataType"] as? [[String: Any]],
            let first = arr.first
        else { return nil }

        let normalizedAddr = normalizedBluetoothAddress(address)

        let normalizedName = deviceName?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        func pct(_ v: Any?) -> Int? {
            if let i = v as? Int, (0...100).contains(i) { return i }
            if let n = v as? NSNumber {
                let i = n.intValue
                return (0...100).contains(i) ? i : nil
            }
            if let s = v as? String {
                let digits = s.filter(\.isNumber)
                if let i = Int(digits), (0...100).contains(i) { return i }
            }
            return nil
        }

        guard let connected = first["device_connected"] as? [[String: Any]] else { return nil }

        for item in connected {
            // item: ["AirPods Ivanka": ["device_address": "...", "device_batteryLevelLeft": "94%", ...]]
            guard let (name, propsAny) = item.first,
                  let props = propsAny as? [String: Any]
            else { continue }

            let addr = normalizedBluetoothAddress(props["device_address"] as? String)

            let addrMatch = (normalizedAddr != nil && addr == normalizedAddr)
            let nameMatch = (normalizedName != nil && name.localizedCaseInsensitiveContains(normalizedName!))
            let airpodsLike = name.localizedCaseInsensitiveContains("airpods")

            // If explicit address/name provided -> match by them
            // Otherwise -> allow "AirPods*" devices
            guard addrMatch || nameMatch || (normalizedAddr == nil && normalizedName == nil && airpodsLike) else {
                continue
            }

            var snap = AirPodsBatterySnapshot()

            // These are the keys you showed in your JSON:
            snap.left = pct(props["device_batteryLevelLeft"])
            snap.right = pct(props["device_batteryLevelRight"])
            snap.casePct = pct(props["device_batteryLevelCase"])

            // Some systems may expose an overall battery level (rare)
            snap.device = pct(props["device_batteryLevel"])
                ?? pct(props["device_batteryLevelMain"])
                ?? pct(props["device_batteryLevelOverall"])

            if snap.device != nil || snap.left != nil || snap.right != nil || snap.casePct != nil {
                return snap
            }
        }

        return nil
    }

    static func displayBatteryPercent(from snapshot: AirPodsBatterySnapshot) -> Int? {
        if let device = snapshot.device {
            return device
        }

        let earbuds = [snapshot.left, snapshot.right].compactMap { $0 }
        if earbuds.isEmpty {
            return snapshot.casePct
        }

        if earbuds.count == 1 {
            return earbuds[0]
        }

        let average = Double(earbuds.reduce(0, +)) / Double(earbuds.count)
        return Int(average.rounded())
    }

    // MARK: - TEXT (fallback, not reliable for AirPods)

    /// Uses: /usr/sbin/system_profiler SPBluetoothDataType
    static func fetchBluetoothText() async -> String? {
        guard let data = await runSystemProfiler(arguments: ["SPBluetoothDataType"]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Parse a device block by Bluetooth address, e.g. "A8:91:3D:0C:EB:EA"
    static func parseBattery(output: String, address: String) -> AirPodsBatterySnapshot? {
        let addr = address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: ":")
            .uppercased()
        guard !addr.isEmpty else { return nil }

        // Find "Address: <addr>"
        let needle = "Address: \(addr)"
        guard let addrRange = output.range(of: needle, options: [.caseInsensitive]) else { return nil }

        // Take a window around it
        let tail = output[addrRange.lowerBound...]
        let block = String(tail.prefix(2000))

        var snap = AirPodsBatterySnapshot()
        snap.device = firstPercent(in: block, keys: ["Battery Level"])
        snap.left   = firstPercent(in: block, keys: ["Left Battery Level", "Left Battery"])
        snap.right  = firstPercent(in: block, keys: ["Right Battery Level", "Right Battery"])
        snap.casePct = firstPercent(in: block, keys: ["Case Battery Level", "Case Battery"])

        if snap.device == nil, snap.left == nil, snap.right == nil, snap.casePct == nil {
            return nil
        }
        return snap
    }

    static func parseBatteryByName(output: String, deviceName: String) -> AirPodsBatterySnapshot? {
        let name = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        // finds a line like "          AirPods Ivanka:"
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\\n\\s*\(escaped):"

        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = output as NSString
        guard let m = re.firstMatch(in: output, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }

        // take a block after "Name:" for up to 2000 chars
        let start = m.range.location + m.range.length
        let tail = output.dropFirst(start)
        let block = String(tail.prefix(2000))

        var snap = AirPodsBatterySnapshot()
        snap.device = firstPercent(in: block, keys: ["Battery Level"])
        snap.left   = firstPercent(in: block, keys: ["Left Battery Level", "Left Battery"])
        snap.right  = firstPercent(in: block, keys: ["Right Battery Level", "Right Battery"])
        snap.casePct = firstPercent(in: block, keys: ["Case Battery Level", "Case Battery"])

        if snap.device == nil, snap.left == nil, snap.right == nil, snap.casePct == nil {
            return nil
        }
        return snap
    }

    private static func firstPercent(in text: String, keys: [String]) -> Int? {
        for key in keys {
            let pattern = "\(NSRegularExpression.escapedPattern(for: key))\\s*:\\s*(\\d{1,3})%?"
            if let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let ns = text as NSString
                let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length))
                if let m, m.numberOfRanges >= 2 {
                    let s = ns.substring(with: m.range(at: 1))
                    if let v = Int(s), (0...100).contains(v) { return v }
                }
            }
        }
        return nil
    }

    private static func normalizedBluetoothAddress(_ address: String?) -> String? {
        guard let address else { return nil }
        let normalized = address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: ":")
            .uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func runSystemProfiler(arguments: [String]) async -> Data? {
        let state = ProcessCancellationState()
        let timeout = DispatchWorkItem {
            state.cancel()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: timeout)

        let result: Data? = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                processQueue.async {
                    autoreleasepool {
                        guard state.isCancelled == false else {
                            continuation.resume(returning: nil)
                            return
                        }

                        let process = Process()
                        let output = Pipe()
                        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                        process.arguments = arguments
                        process.standardOutput = output
                        process.standardError = FileHandle.nullDevice
                        state.install(process)

                        guard state.isCancelled == false else {
                            state.clear(process)
                            continuation.resume(returning: nil)
                            return
                        }

                        do {
                            try process.run()
                        } catch {
                            state.clear(process)
                            continuation.resume(returning: nil)
                            return
                        }

                        if state.isCancelled {
                            process.terminate()
                        }

                        let data = output.fileHandleForReading.readDataToEndOfFile()
                        process.waitUntilExit()
                        state.clear(process)

                        guard state.isCancelled == false,
                              process.terminationStatus == 0,
                              data.isEmpty == false else {
                            continuation.resume(returning: nil)
                            return
                        }

                        continuation.resume(returning: data)
                    }
                }
            }
        } onCancel: {
            state.cancel()
        }
        timeout.cancel()
        return result
    }
}

private final class ProcessCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func install(_ process: Process) {
        lock.withLock {
            self.process = process
        }
    }

    func clear(_ process: Process) {
        lock.withLock {
            if self.process === process {
                self.process = nil
            }
        }
    }

    func cancel() {
        let runningProcess = lock.withLock { () -> Process? in
            guard cancelled == false else { return nil }
            cancelled = true
            return process
        }

        guard let runningProcess, runningProcess.isRunning else { return }
        runningProcess.terminate()

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.forceTerminate()
        }
    }

    private func forceTerminate() {
        let processIdentifier = lock.withLock { () -> Int32? in
            guard let process, process.isRunning else { return nil }
            return process.processIdentifier
        }
        guard let processIdentifier, processIdentifier > 0 else { return }
        Darwin.kill(processIdentifier, SIGKILL)
    }
}

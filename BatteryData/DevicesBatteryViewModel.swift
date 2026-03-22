import Foundation
@preconcurrency import CoreBluetooth
import IOBluetooth

private let devicesBatteryServiceID = "180F"
private let devicesBatteryLevelCharacteristicID = "2A19"

private struct DeviceDiscoverySource: OptionSet, Equatable {
    let rawValue: Int

    static let ioBluetooth = DeviceDiscoverySource(rawValue: 1 << 0)
    static let ble = DeviceDiscoverySource(rawValue: 1 << 1)
}

struct DeviceBatteryInfo: Identifiable, Equatable {
    let id: String
    var name: String
    var batteryPercent: Int?
    var lastUpdated: Date?
    var isConnected: Bool
    var address: String?
    var peripheralIdentifier: UUID?
    fileprivate var sources: DeviceDiscoverySource = []
}

struct IOBluetoothAudioDeviceSnapshot: Equatable {
    let name: String
    let address: String?
    let batteryPercent: Int?
    let isConnected: Bool
}

struct BLEBatteryUpdate: Equatable {
    let name: String
    let peripheralIdentifier: UUID
    let batteryPercent: Int?
    let isConnected: Bool
}

struct DeviceBatteryStore {
    private(set) var devices: [DeviceBatteryInfo] = []

    var connectedDevices: [DeviceBatteryInfo] {
        devices.filter(\.isConnected)
    }

    mutating func clear() {
        devices.removeAll()
    }

    mutating func applyIOBluetoothSnapshots(_ snapshots: [IOBluetoothAudioDeviceSnapshot], now: Date) {
        var seenAddresses = Set<String>()
        var seenFallbackIDs = Set<String>()

        for snapshot in snapshots where snapshot.isConnected {
            let normalizedAddress = Self.normalizedAddress(snapshot.address)
            let fallbackID = Self.fallbackIdentifier(name: snapshot.name)
            let existingDevice = device(at: indexForIOBluetoothSnapshot(snapshot))

            if let normalizedAddress {
                seenAddresses.insert(normalizedAddress)
            } else {
                seenFallbackIDs.insert(fallbackID)
            }

            let index = indexForIOBluetoothSnapshot(snapshot)
            let stableID = normalizedAddress.map(Self.addressIdentifier) ?? existingDevice.idOr(fallbackID)

            upsertDevice(
                at: index,
                stableID: stableID,
                name: snapshot.name,
                batteryPercent: snapshot.batteryPercent,
                address: normalizedAddress,
                peripheralIdentifier: existingDevice?.peripheralIdentifier,
                source: .ioBluetooth,
                isConnected: true,
                now: now
            )
        }

        for idx in devices.indices {
            guard devices[idx].sources.contains(.ioBluetooth) else { continue }

            let keepConnected: Bool
            if let address = devices[idx].address {
                keepConnected = seenAddresses.contains(address)
            } else {
                keepConnected = seenFallbackIDs.contains(devices[idx].id)
            }

            guard keepConnected == false else { continue }
            devices[idx].sources.remove(.ioBluetooth)
            devices[idx].isConnected = devices[idx].sources.contains(.ble)
        }
    }

    mutating func applyBLEUpdate(_ update: BLEBatteryUpdate, now: Date) {
        let index = indexForBLEUpdate(update)
        let existingDevice = device(at: index)
        let stableID = existingDevice?.id ?? Self.peripheralIdentifier(update.peripheralIdentifier)
        let existingAddress = existingDevice?.address

        upsertDevice(
            at: index,
            stableID: stableID,
            name: update.name,
            batteryPercent: update.batteryPercent,
            address: existingAddress,
            peripheralIdentifier: update.peripheralIdentifier,
            source: .ble,
            isConnected: update.isConnected,
            now: now
        )
    }

    private func device(at index: Int?) -> DeviceBatteryInfo? {
        guard let index, devices.indices.contains(index) else { return nil }
        return devices[index]
    }

    mutating func removeBLEPeripheral(_ peripheralIdentifier: UUID) {
        guard let idx = devices.firstIndex(where: { $0.peripheralIdentifier == peripheralIdentifier }) else {
            return
        }

        devices[idx].sources.remove(.ble)
        devices[idx].peripheralIdentifier = nil
        devices[idx].isConnected = devices[idx].sources.contains(.ioBluetooth)
    }

    mutating func enrichMissingBattery(from jsonData: Data, now: Date) {
        for idx in devices.indices where devices[idx].isConnected && devices[idx].batteryPercent == nil {
            let snapshot = SystemProfilerBluetoothReader.parseBattery(
                jsonData: jsonData,
                address: devices[idx].address,
                deviceName: devices[idx].name
            )

            guard
                let snapshot,
                let batteryPercent = SystemProfilerBluetoothReader.displayBatteryPercent(from: snapshot)
            else {
                continue
            }

            devices[idx].batteryPercent = batteryPercent
            devices[idx].lastUpdated = now
        }
    }

    private mutating func upsertDevice(
        at index: Int?,
        stableID: String,
        name: String,
        batteryPercent: Int?,
        address: String?,
        peripheralIdentifier: UUID?,
        source: DeviceDiscoverySource,
        isConnected: Bool,
        now: Date
    ) {
        let trimmedName = Self.trimmedName(name, fallback: "Audio device")

        if let index {
            devices[index].name = trimmedName
            devices[index].sources.insert(source)
            devices[index].isConnected = isConnected || !devices[index].sources.isEmpty
            devices[index].lastUpdated = now

            if let batteryPercent {
                devices[index].batteryPercent = batteryPercent
            }
            if let address {
                devices[index].address = address
            }
            if let peripheralIdentifier {
                devices[index].peripheralIdentifier = peripheralIdentifier
            }
            return
        }

        devices.append(
            DeviceBatteryInfo(
                id: stableID,
                name: trimmedName,
                batteryPercent: batteryPercent,
                lastUpdated: now,
                isConnected: isConnected,
                address: address,
                peripheralIdentifier: peripheralIdentifier,
                sources: source
            )
        )
    }

    private func indexForIOBluetoothSnapshot(_ snapshot: IOBluetoothAudioDeviceSnapshot) -> Int? {
        if let address = Self.normalizedAddress(snapshot.address),
           let byAddress = devices.firstIndex(where: { $0.address == address }) {
            return byAddress
        }

        let normalizedName = Self.normalizedName(snapshot.name)
        guard normalizedName.isEmpty == false else { return nil }

        let nameMatches = devices.indices.filter {
            Self.normalizedName(devices[$0].name) == normalizedName
        }

        return nameMatches.count == 1 ? nameMatches[0] : nil
    }

    private func indexForBLEUpdate(_ update: BLEBatteryUpdate) -> Int? {
        if let byPeripheral = devices.firstIndex(where: { $0.peripheralIdentifier == update.peripheralIdentifier }) {
            return byPeripheral
        }

        let normalizedName = Self.normalizedName(update.name)
        guard normalizedName.isEmpty == false else { return nil }

        let nameMatches = devices.indices.filter {
            Self.normalizedName(devices[$0].name) == normalizedName
        }

        return nameMatches.count == 1 ? nameMatches[0] : nil
    }

    private static func trimmedName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func normalizedName(_ name: String) -> String {
        trimmedName(name, fallback: "")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    private static func fallbackIdentifier(name: String) -> String {
        "name:\(normalizedName(name))"
    }

    static func normalizedAddress(_ address: String?) -> String? {
        guard let address else { return nil }
        let normalized = address
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: ":")
            .uppercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func addressIdentifier(_ address: String) -> String {
        "addr:\(address)"
    }

    private static func peripheralIdentifier(_ identifier: UUID) -> String {
        "ble:\(identifier.uuidString)"
    }
}

private extension Optional where Wrapped == DeviceBatteryInfo {
    func idOr(_ fallback: String) -> String {
        self?.id ?? fallback
    }
}

@MainActor
final class DevicesBatteryViewModel: NSObject, ObservableObject {

    @Published private(set) var connectedDevices: [DeviceBatteryInfo] = []
    @Published private(set) var errorText: String?

    var connectedHeadphones: [DeviceBatteryInfo] { connectedDevices }

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var batteryChars: [UUID: CBCharacteristic] = [:]
    private var store = DeviceBatteryStore()

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    private var refreshDebounceTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    deinit {
        refreshDebounceTask?.cancel()
        refreshTask?.cancel()

        Task { @MainActor [weak self] in
            self?.stop()
        }
    }

    func start() {
        setupIOBluetoothNotifications()
        refresh()
    }

    func stop() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        refreshTask?.cancel()
        refreshTask = nil

        peripherals.values.forEach { peripheral in
            central.cancelPeripheralConnection(peripheral)
        }
        peripherals.removeAll()
        batteryChars.removeAll()

        teardownIOBluetoothNotifications()

        store.clear()
        connectedDevices.removeAll()
        errorText = nil
    }

    func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.runRefresh(generation: generation)
        }
    }

    private func runRefresh(generation: Int) async {
        guard generation == refreshGeneration else { return }

        errorText = nil
        let now = Date()

        store.applyIOBluetoothSnapshots(loadIOBluetoothDevices(), now: now)
        syncConnectedDevices()

        guard shouldContinueRefresh(generation) else { return }

        if let json = await SystemProfilerBluetoothReader.fetchBluetoothJSON(),
           shouldContinueRefresh(generation) {
            store.enrichMissingBattery(from: json, now: Date())
            syncConnectedDevices()
        }

        guard shouldContinueRefresh(generation) else { return }

        if central.state == .poweredOn {
            let connected = central.retrieveConnectedPeripherals(
                withServices: [CBUUID(string: devicesBatteryServiceID)]
            )
            mergeBLEPeripherals(connected)
        }

        syncConnectedDevices()
    }

    private func shouldContinueRefresh(_ generation: Int) -> Bool {
        Task.isCancelled == false && generation == refreshGeneration
    }

    private func syncConnectedDevices() {
        connectedDevices = store.connectedDevices
    }

    private func mergeBLEPeripherals(_ connected: [CBPeripheral]) {
        for peripheral in connected {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self

            let update = BLEBatteryUpdate(
                name: peripheral.name ?? "BLE device",
                peripheralIdentifier: peripheral.identifier,
                batteryPercent: nil,
                isConnected: true
            )
            store.applyBLEUpdate(update, now: Date())

            if peripheral.state != .connected {
                central.connect(peripheral, options: nil)
            } else {
                peripheral.discoverServices([CBUUID(string: devicesBatteryServiceID)])
            }
        }
    }

    private func setupIOBluetoothNotifications() {
        guard connectNotification == nil else { return }

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(iobtDeviceConnected(_:device:))
        )

        registerDisconnectForCurrentlyConnectedAudioDevices()
    }

    private func teardownIOBluetoothNotifications() {
        connectNotification?.unregister()
        connectNotification = nil

        for notification in disconnectNotifications.values {
            notification.unregister()
        }
        disconnectNotifications.removeAll()
    }

    private func registerDisconnect(for device: IOBluetoothDevice) {
        guard
            let address = DeviceBatteryStore.normalizedAddress(device.addressString),
            disconnectNotifications[address] == nil
        else {
            return
        }

        let notification = device.register(
            forDisconnectNotification: self,
            selector: #selector(iobtDeviceDisconnected(_:device:))
        )

        if let notification {
            disconnectNotifications[address] = notification
        }
    }

    private func registerDisconnectForCurrentlyConnectedAudioDevices() {
        for device in getAllIOBluetoothAudioDevices() where device.isConnected() {
            registerDisconnect(for: device)
        }
    }

    private func scheduleRefresh(delay: TimeInterval = 0.35) {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            guard let self else { return }
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                self.refresh()
            }
        }
    }

    @objc private func iobtDeviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        registerDisconnect(for: device)
        scheduleRefresh()
    }

    @objc private func iobtDeviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let address = DeviceBatteryStore.normalizedAddress(device.addressString),
           let notification = disconnectNotifications[address] {
            notification.unregister()
            disconnectNotifications.removeValue(forKey: address)
        }
        scheduleRefresh()
    }

    private func isLikelyHeadphonesName(_ name: String) -> Bool {
        let normalized = name.lowercased()

        if normalized.contains("keyboard") || normalized.contains("mouse") || normalized.contains("trackpad") {
            return false
        }
        if normalized.contains("magic keyboard") || normalized.contains("magic mouse") || normalized.contains("logitech") {
            return false
        }
        if normalized.contains("mx keys") || normalized.contains("mx master") {
            return false
        }

        if normalized.contains("airpods") { return true }
        if normalized.contains("beats") { return true }
        if normalized.contains("headphone") || normalized.contains("headphones") { return true }
        if normalized.contains("buds") || normalized.contains("earbuds") { return true }
        if normalized.contains("ear") && normalized.contains("pod") { return true }

        return false
    }

    private func getAllIOBluetoothAudioDevices() -> [IOBluetoothDevice] {
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        return paired.filter { device in
            let name = (device.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return isLikelyHeadphonesName(name)
        }
    }

    private func loadIOBluetoothDevices() -> [IOBluetoothAudioDeviceSnapshot] {
        getAllIOBluetoothAudioDevices().map { device in
            IOBluetoothAudioDeviceSnapshot(
                name: device.name ?? "Audio device",
                address: DeviceBatteryStore.normalizedAddress(device.addressString),
                batteryPercent: device.bd_batteryPercent,
                isConnected: device.isConnected()
            )
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension DevicesBatteryViewModel: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn {
                refresh()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        // not used
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([CBUUID(string: devicesBatteryServiceID)])
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // ignore
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            peripherals.removeValue(forKey: peripheral.identifier)
            batteryChars.removeValue(forKey: peripheral.identifier)
            store.removeBLEPeripheral(peripheral.identifier)
            syncConnectedDevices()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension DevicesBatteryViewModel: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return }
        guard let services = peripheral.services else { return }

        let batteryService = CBUUID(string: devicesBatteryServiceID)
        let batteryLevelCharacteristic = CBUUID(string: devicesBatteryLevelCharacteristicID)

        for service in services where service.uuid == batteryService {
            peripheral.discoverCharacteristics([batteryLevelCharacteristic], for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else { return }

        Task { @MainActor in
            guard let characteristics = service.characteristics else { return }
            let batteryLevelCharacteristic = CBUUID(string: devicesBatteryLevelCharacteristicID)

            for characteristic in characteristics where characteristic.uuid == batteryLevelCharacteristic {
                batteryChars[peripheral.identifier] = characteristic
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else { return }
        let batteryLevelCharacteristic = CBUUID(string: devicesBatteryLevelCharacteristicID)
        guard characteristic.uuid == batteryLevelCharacteristic else { return }
        guard let data = characteristic.value, let firstByte = data.first else { return }

        Task { @MainActor in
            let update = BLEBatteryUpdate(
                name: peripheral.name ?? "BLE device",
                peripheralIdentifier: peripheral.identifier,
                batteryPercent: Int(firstByte),
                isConnected: true
            )
            store.applyBLEUpdate(update, now: Date())
            syncConnectedDevices()
        }
    }
}

// MARK: - IOBluetooth best-effort battery extraction

private extension IOBluetoothDevice {
    var bd_batteryPercent: Int? {
        guard responds(to: Selector(("batteryPercent"))) else { return nil }

        return ObjC.catchException {
            (self.value(forKey: "batteryPercent") as? NSNumber)?.intValue
        }
    }
}

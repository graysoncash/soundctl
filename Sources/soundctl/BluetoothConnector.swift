import CoreBluetooth
import Foundation
import IOBluetooth

enum BluetoothConnector {
    static let authorizeSubcommand = "__authorize-bluetooth"

    /// Reading `CBCentralManager.authorization` never prompts. When undetermined
    /// we attempt the prompt in a child process: an ad-hoc-signed binary is
    /// killed by TCC rather than prompted, so isolating it keeps that abort off
    /// the main process. IOBluetooth is only touched once this returns true.
    static func ensureAccess() -> Bool {
        switch CBCentralManager.authorization {
        case .allowedAlways:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            spawnAuthorizationPrompt()
            return CBCentralManager.authorization == .allowedAlways
        @unknown default:
            return false
        }
    }

    private static func spawnAuthorizationPrompt() {
        guard let executable = Bundle.main.executablePath else { return }

        let child = Process()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = [authorizeSubcommand]
        guard (try? child.run()) != nil else { return }
        child.waitUntilExit()
    }

    static func runAuthorizationPrompt() {
        _ = BluetoothAuthorizer.requestAccess()
    }

    static func pairedDevice(matching identifier: String) -> IOBluetoothDevice? {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return nil
        }

        // IOBluetooth reports addresses as lowercase dash-separated
        let normalizedMac = identifier
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .lowercased()

        if let device = paired.first(where: { $0.addressString?.lowercased() == normalizedMac }) {
            return device
        }

        let loweredName = identifier.lowercased()
        return paired.first { device in
            guard let name = device.name?.lowercased() else { return false }
            return name == loweredName || name.contains(loweredName)
        }
    }

    static func connect(_ device: IOBluetoothDevice, attempts: Int = 3) throws {
        let name = device.name ?? device.addressString ?? "unknown"
        var lastStatus: IOReturn = kIOReturnSuccess

        for attempt in 1...max(1, attempts) {
            let status = device.openConnection()
            logAttempt(attempt, of: attempts, status: status, connected: device.isConnected())

            // Opening the baseband link is enough; the audio profile and
            // CoreAudio registration follow asynchronously and are polled by the
            // caller. A device held by another host pages slowly, so retry.
            if status == kIOReturnSuccess {
                return
            }

            lastStatus = status
            if attempt < attempts {
                Thread.sleep(forTimeInterval: 1.5)
            }
        }

        throw AudioError.bluetoothConnectionFailed(
            "Failed to connect to Bluetooth device \"\(name)\": \(describe(lastStatus))")
    }

    private static func logAttempt(
        _ attempt: Int, of total: Int, status: IOReturn, connected: Bool
    ) {
        let hex = String(format: "0x%08x", UInt32(bitPattern: status))
        let line = "  attempt \(attempt)/\(total): openConnection=\(hex) "
            + "isConnected=\(connected)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private static func describe(_ status: IOReturn) -> String {
        let hex = String(format: "0x%08x", UInt32(bitPattern: status))
        let detail: String
        switch status {
        case kIOReturnTimeout:
            detail = "timed out — device did not respond (is it powered on and in range?)"
        case kIOReturnNoDevice:
            detail = "no such device"
        case kIOReturnNotOpen:
            detail = "the link did not come up (device may be connected to another host)"
        case kIOReturnNotPermitted, kIOReturnNotPrivileged:
            detail = "not permitted (check Bluetooth access in Privacy & Security)"
        case kIOReturnError:
            detail = "general Bluetooth error (often a page timeout from a sleeping device)"
        default:
            detail = "unexpected error"
        }
        return "\(detail) [IOReturn \(hex)]"
    }
}

/// Raises the macOS Bluetooth permission dialog by instantiating a live
/// `CBCentralManager` (reading `.authorization` alone never prompts). Callbacks
/// run on a background queue so the calling thread can block until the user
/// responds.
private final class BluetoothAuthorizer: NSObject, CBCentralManagerDelegate {
    private static let promptTimeout: TimeInterval = 30

    static func requestAccess() -> Bool {
        BluetoothAuthorizer().run(timeout: promptTimeout)
    }

    private let queue = DispatchQueue(label: "cash.grayson.soundctl.bluetooth-auth")
    private let semaphore = DispatchSemaphore(value: 0)
    private var manager: CBCentralManager?

    private func run(timeout: TimeInterval) -> Bool {
        FileHandle.standardError.write(
            Data("Requesting Bluetooth access — please allow the prompt…\n".utf8))

        manager = CBCentralManager(delegate: self, queue: queue)
        _ = semaphore.wait(timeout: .now() + timeout)
        return CBCentralManager.authorization == .allowedAlways
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // `.unknown`/`.resetting` are transient; the state settles after the
        // user answers the dialog.
        switch central.state {
        case .unknown, .resetting:
            return
        default:
            semaphore.signal()
        }
    }
}

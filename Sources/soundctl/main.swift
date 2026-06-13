import ArgumentParser
import CoreAudio
import Foundation

struct ConfigOption: ParsableArguments {
    @Option(
        name: .shortAndLong,
        help: "Path to config file (default: ~/.config/soundctl/config.json)")
    var config: String?

    func apply() {
        Config.configPath = config
    }
}

struct SoundCtl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "soundctl",
        abstract: "A command-line utility to control sound devices on macOS",
        version: version,
        subcommands: [
            Set.self, List.self, Current.self, Next.self, Mute.self, AuthorizeBluetooth.self,
        ],
        defaultSubcommand: Current.self
    )
}

/// Hidden subcommand run as a throwaway child by `ensureAccess`, so a TCC abort
/// on first Bluetooth use can't take down the parent.
struct AuthorizeBluetooth: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: BluetoothConnector.authorizeSubcommand,
        abstract: "Internal: trigger the Bluetooth permission prompt",
        shouldDisplay: false
    )

    func run() throws {
        BluetoothConnector.runAuthorizationPrompt()
    }
}

struct Set: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set the audio device"
    )

    @OptionGroup var configOption: ConfigOption

    @Argument(help: "Device identifier (MAC address, CoreAudio device ID, or name)")
    var identifier: String

    @Option(name: .shortAndLong, help: "Device type (input/output/system/all)")
    var type: AudioDeviceType = .output

    @Option(help: "Seconds to wait for a Bluetooth device to appear after connecting")
    var bluetoothTimeout: Double = 10

    func run() throws {
        configOption.apply()

        do {
            try resolveAndSet()
        } catch let error as AudioError {
            guard case .deviceNotFound = error else { throw error }
            try connectBluetoothAndRetry(originalError: error)
        }
    }

    private func resolveAndSet() throws {
        if type == .all {
            try AudioManager.setAllDevicesByName(identifier)
            return
        }

        let device = try resolveDevice()
        try AudioManager.setDevice(device.id, type: type)
        print("\(type.rawValue) audio device set to \"\(device.name)\"")
    }

    private func resolveDevice() throws -> AudioDevice {
        // Try MAC address format first
        if isMacAddressFormat(identifier) {
            let normalizedMac = normalizeMacAddress(identifier)
            if let device = try? AudioManager.findDevice(byUID: normalizedMac, type: type) {
                return device
            }
        }

        // Try as numeric ID
        if let deviceID = UInt32(identifier) {
            if let device = try? AudioManager.findDevice(byID: deviceID, type: type) {
                return device
            }
        }

        // Fall back to name matching
        return try AudioManager.findDevice(byName: identifier, type: type)
    }

    private func connectBluetoothAndRetry(originalError: AudioError) throws {
        guard BluetoothConnector.ensureAccess() else {
            FileHandle.standardError.write(
                Data(
                    """
                    note: skipped Bluetooth connection attempt — Bluetooth access is unavailable. \
                    Allow your terminal under System Settings → Privacy & Security → Bluetooth \
                    (add it with the + button if it is not listed), then retry.\n
                    """.utf8))
            throw originalError
        }

        guard let btDevice = BluetoothConnector.pairedDevice(matching: identifier),
            !btDevice.isConnected()
        else {
            throw originalError
        }

        let btName = btDevice.name ?? identifier
        print("\"\(btName)\" is paired but not connected; connecting via Bluetooth...")
        try BluetoothConnector.connect(btDevice)

        // The audio device registers with CoreAudio shortly after the
        // Bluetooth link comes up; retry until it appears or we time out.
        let deadline = Date().addingTimeInterval(bluetoothTimeout)
        while true {
            do {
                try resolveAndSet()
                return
            } catch {
                guard Date() < deadline else { throw error }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    func isMacAddressFormat(_ string: String) -> Bool {
        let macPattern = #"^[0-9A-Fa-f]{2}([:\-.][0-9A-Fa-f]{2}){5}$"#
        return string.range(of: macPattern, options: .regularExpression) != nil
    }

    func normalizeMacAddress(_ macAddress: String) -> String {
        return macAddress.replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all audio devices"
    )

    @OptionGroup var configOption: ConfigOption

    @Option(name: .shortAndLong, help: "Device type (input/output/system/all)")
    var type: AudioDeviceType = .output

    @Option(name: .shortAndLong, help: "Output format (human/cli/json)")
    var format: OutputFormat = .human

    func run() throws {
        configOption.apply()

        switch type {
        case .input, .output:
            let devices = try AudioManager.getAllDevices(type: type)
            for device in devices {
                print(device.format(as: format))
            }
        case .system:
            let devices = try AudioManager.getAllDevices(type: .output)
            for device in devices {
                print(device.format(as: format))
            }
        case .all:
            let inputDevices = try AudioManager.getAllDevices(type: .input)
            for device in inputDevices {
                print(device.format(as: format))
            }
            let outputDevices = try AudioManager.getAllDevices(type: .output)
            for device in outputDevices {
                print(device.format(as: format))
            }
        }
    }
}

struct Current: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show current audio device"
    )

    @OptionGroup var configOption: ConfigOption

    @Option(name: .shortAndLong, help: "Device type (input/output/system)")
    var type: AudioDeviceType = .output

    @Option(name: .shortAndLong, help: "Output format (human/cli/json)")
    var format: OutputFormat = .human

    func run() throws {
        configOption.apply()

        let deviceType = type == .all ? .output : type
        let device = try AudioManager.getCurrentDevice(type: deviceType)
        print(device.format(as: format))
    }
}

struct Next: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Cycle to the next audio device"
    )

    @OptionGroup var configOption: ConfigOption

    @Option(name: .shortAndLong, help: "Device type (input/output/system/all)")
    var type: AudioDeviceType = .output

    func run() throws {
        configOption.apply()

        switch type {
        case .all:
            _ = try? AudioManager.cycleNext(type: .input)
            _ = try? AudioManager.cycleNext(type: .output)
            let device = try AudioManager.cycleNext(type: .system)
            print("\(type.rawValue) audio device set to \"\(device.name)\"")
        default:
            let device = try AudioManager.cycleNext(type: type)
            print("\(type.rawValue) audio device set to \"\(device.name)\"")
        }
    }
}

struct Mute: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Control mute status of audio devices"
    )

    @OptionGroup var configOption: ConfigOption

    @Argument(help: "Mute action (toggle/on/off)")
    var action: String = "toggle"

    @Option(name: .shortAndLong, help: "Device type (input/output/all)")
    var type: AudioDeviceType = .output

    func run() throws {
        configOption.apply()

        let muteAction: MuteAction
        switch action.lowercased() {
        case "on", "mute":
            muteAction = .mute
        case "off", "unmute":
            muteAction = .unmute
        case "toggle":
            muteAction = .toggle
        default:
            throw ValidationError("Invalid mute action '\(action)'. Use: toggle, on, or off")
        }

        let deviceType = type == .all ? .input : type

        switch deviceType {
        case .input, .output:
            try AudioManager.setMute(muteAction, type: deviceType)
        case .system:
            throw AudioError.muteNotSupported
        case .all:
            try? AudioManager.setMute(muteAction, type: .input)
            try? AudioManager.setMute(muteAction, type: .output)
        }
    }
}

extension OutputFormat: ExpressibleByArgument {}
extension AudioDeviceType: ExpressibleByArgument {}

SoundCtl.main()

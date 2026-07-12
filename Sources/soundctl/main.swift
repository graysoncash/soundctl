import ArgumentParser
import CoreAudio
import Foundation

struct ConfigOption: ParsableArguments {
    @Option(
        name: .shortAndLong,
        help: "Path to config file (default: ~/.config/soundctl/config.toml)")
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
            Set.self, List.self, Current.self, Next.self, Mute.self, AliasCommand.self,
            MonitorCommand.self, AuthorizeBluetooth.self,
        ],
        defaultSubcommand: Current.self
    )
}

/// Post a device-change notification when either the `--notify` flag or the
/// `[behavior] notify` config setting is enabled.
func notifyIfEnabled(flag: Bool, type: AudioDeviceType, deviceName: String) {
    guard flag || (Config.load()?.behavior.notify ?? false) else { return }
    Notifier.notify(title: "soundctl", body: "\(type.rawValue.capitalized): \(deviceName)")
}

/// Completion candidates for a device identifier: saved alias names plus the
/// names of the current input and output devices.
func deviceCompletions() -> [String] {
    var names: [String] = []
    if let aliases = Config.load()?.aliases { names.append(contentsOf: aliases.keys) }
    for type in [AudioDeviceType.output, .input] {
        if let devices = try? AudioManager.getAllDevices(type: type) {
            names.append(contentsOf: devices.map(\.name))
        }
    }
    return Array(Swift.Set(names)).sorted()
}

/// Completion candidates for an alias name.
func aliasCompletions() -> [String] {
    (Config.load()?.aliases ?? [:]).keys.sorted()
}

/// Parse a comma-separated `--type` value (e.g. "input,output") into a
/// deduplicated, order-preserving list of device types.
func parseDeviceTypes(_ raw: String) throws -> [AudioDeviceType] {
    let parts = raw.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty }

    var result: [AudioDeviceType] = []
    for part in parts {
        guard let type = AudioDeviceType(rawValue: part) else {
            throw ValidationError(
                "Invalid device type '\(part)'. Use: input, output, system, or all")
        }
        if !result.contains(type) { result.append(type) }
    }
    return result.isEmpty ? [.output] : result
}

struct AliasCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alias",
        abstract: "Manage device aliases",
        subcommands: [AliasAdd.self, AliasList.self, AliasRemove.self],
        defaultSubcommand: AliasList.self
    )
}

struct AliasAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add or update an alias"
    )

    @OptionGroup var configOption: ConfigOption

    @Argument(help: "Alias name (e.g. app)")
    var name: String

    @Argument(help: "Device MAC address or name")
    var device: String

    @Option(
        name: .shortAndLong,
        help: "Comma-separated device types (input/output/system/all)")
    var type: String = "output"

    func run() throws {
        configOption.apply()

        let types = try parseDeviceTypes(type)
        let config = Config.loadForEditing()
        var aliases = config.aliases
        aliases[name] = Config.Alias(device: device, types: types)
        try config.withAliases(aliases).save()

        let typeList = types.map(\.rawValue).joined(separator: ", ")
        print("Alias \"\(name)\" → \(device) [\(typeList)]")
    }
}

struct AliasList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List saved aliases"
    )

    @OptionGroup var configOption: ConfigOption

    func run() throws {
        configOption.apply()

        let aliases = Config.load()?.aliases ?? [:]
        guard !aliases.isEmpty else {
            print("No aliases configured")
            return
        }

        for name in aliases.keys.sorted() {
            let alias = aliases[name]!
            let typeList = alias.types.map(\.rawValue).joined(separator: ", ")
            print("\(name) → \(alias.device) [\(typeList)]")
        }
    }
}

struct AliasRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove an alias"
    )

    @OptionGroup var configOption: ConfigOption

    @Argument(help: "Alias name to remove", completion: .custom { _, _, _ in aliasCompletions() })
    var name: String

    func run() throws {
        configOption.apply()

        let config = Config.loadForEditing()
        var aliases = config.aliases
        guard let key = aliases.keys.first(where: { $0.lowercased() == name.lowercased() }) else {
            throw ValidationError("No alias named '\(name)'")
        }
        aliases.removeValue(forKey: key)
        try config.withAliases(aliases).save()
        print("Removed alias \"\(key)\"")
    }
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

    @Argument(
        help: "Device identifier (MAC address, CoreAudio device ID, or name)",
        completion: .custom { _, _, _ in deviceCompletions() })
    var identifier: String

    @Option(
        name: .shortAndLong,
        help: "Device type (input/output/system/all); overrides an alias's saved types")
    var type: AudioDeviceType?

    @Option(help: "Seconds to wait for a Bluetooth device to appear after connecting")
    var bluetoothTimeout: Double = 10

    @Flag(name: .long, help: "Post a macOS notification when the device changes")
    var notify: Bool = false

    func validate() throws {
        guard bluetoothTimeout >= 0 else {
            throw ValidationError("--bluetooth-timeout must be 0 or greater")
        }
    }

    func run() throws {
        configOption.apply()

        let alias = Config.load()?.alias(named: identifier)
        let target = alias?.device ?? identifier

        let types: [AudioDeviceType]
        if let type {
            types = [type]
        } else {
            types = alias?.types ?? [.output]
        }

        for type in types {
            try apply(target: target, type: type)
        }
    }

    private func apply(target: String, type: AudioDeviceType) throws {
        do {
            try resolveAndSet(target: target, type: type)
            disconnectExclusivePeers(target: target)
        } catch let error as AudioError {
            guard case .deviceNotFound = error else { throw error }
            try connectBluetoothAndRetry(target: target, type: type, originalError: error)
        }
    }

    private func resolveAndSet(target: String, type: AudioDeviceType) throws {
        if type == .all {
            try setAllDevices(target: target)
            return
        }

        let device = try resolveDevice(target: target, type: type)
        try AudioManager.setDevice(device.id, type: type)
        print("\(type.rawValue) audio device set to \"\(device.name)\"")
        notifyIfEnabled(flag: notify, type: type, deviceName: device.name)
    }

    /// Sets the target as the input, output, and system device, resolving it
    /// the same way single-type sets do (MAC/UID, numeric ID, then name) so
    /// that identifiers like a MAC address work here too. Throws only when the
    /// device could not be resolved for any concrete type.
    private func setAllDevices(target: String) throws {
        var resolvedName: String?

        for concreteType in [AudioDeviceType.input, .output, .system] {
            guard let device = try? resolveDevice(target: target, type: concreteType),
                (try? AudioManager.setDevice(device.id, type: concreteType)) != nil
            else {
                continue
            }
            print("\(concreteType.rawValue) audio device set to \"\(device.name)\"")
            resolvedName = device.name
        }

        guard let resolvedName else {
            throw AudioError.deviceNotFound(target)
        }
        notifyIfEnabled(flag: notify, type: .all, deviceName: resolvedName)
    }

    private func resolveDevice(target: String, type: AudioDeviceType) throws -> AudioDevice {
        // Try MAC address format first
        if isMacAddressFormat(target) {
            let normalizedMac = normalizeMacAddress(target)
            if let device = try? AudioManager.findDevice(byUID: normalizedMac, type: type) {
                return device
            }
        }

        // Try as numeric ID
        if let deviceID = UInt32(target) {
            if let device = try? AudioManager.findDevice(byID: deviceID, type: type) {
                return device
            }
        }

        // Fall back to name matching
        return try AudioManager.findDevice(byName: target, type: type)
    }

    /// Enforces `[exclusive]` config groups: disconnect every other connected
    /// member of any group the target belongs to. Callers invoke this only
    /// once the target is confirmed — already registered with CoreAudio, or
    /// its Bluetooth link freshly up — so a failed or misclicked switch never
    /// interrupts the device currently playing. Both the target and group
    /// entries are resolved against the paired-device list so names and MAC
    /// addresses compare by address. Failures downgrade to warnings — a rival
    /// that will not let go should not block the device switch itself.
    private func disconnectExclusivePeers(target: String) {
        let groups = Config.load()?.exclusive.groups ?? []
        guard !groups.isEmpty else { return }

        guard BluetoothConnector.ensureAccess() else {
            FileHandle.standardError.write(
                Data(
                    "note: skipped exclusive-group enforcement — Bluetooth access is unavailable.\n"
                        .utf8))
            return
        }

        guard let targetDevice = BluetoothConnector.pairedDevice(matching: target),
            let targetAddress = targetDevice.addressString
        else { return }

        for group in groups {
            let members = group.compactMap { BluetoothConnector.pairedDevice(matching: $0) }
            guard members.contains(where: { $0.addressString == targetAddress }) else { continue }

            for member in members
            where member.addressString != targetAddress && member.isConnected() {
                let memberName = member.name ?? member.addressString ?? "unknown"
                print(
                    "Disconnecting \"\(memberName)\" — exclusive with "
                        + "\"\(targetDevice.name ?? target)\"")
                do {
                    try BluetoothConnector.disconnect(member)
                } catch {
                    FileHandle.standardError.write(Data("warning: \(error)\n".utf8))
                }
            }
        }
    }

    private func connectBluetoothAndRetry(
        target: String, type: AudioDeviceType, originalError: AudioError
    ) throws {
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

        guard let btDevice = BluetoothConnector.pairedDevice(matching: target),
            !btDevice.isConnected()
        else {
            throw originalError
        }

        let btName = btDevice.name ?? target
        print("\"\(btName)\" is paired but not connected; connecting via Bluetooth...")
        try BluetoothConnector.connect(btDevice)

        // The target's link is up, so it is safe to evict exclusive-group
        // rivals now; a failed connect above leaves them playing untouched.
        disconnectExclusivePeers(target: target)

        // The audio device registers with CoreAudio shortly after the
        // Bluetooth link comes up; retry until it appears or we time out.
        let deadline = Date().addingTimeInterval(bluetoothTimeout)
        while true {
            do {
                try resolveAndSet(target: target, type: type)
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

    @Flag(name: .long, help: "Post a macOS notification when the device changes")
    var notify: Bool = false

    func run() throws {
        configOption.apply()

        switch type {
        case .all:
            _ = try? AudioManager.cycleNext(type: .input)
            _ = try? AudioManager.cycleNext(type: .output)
            let device = try AudioManager.cycleNext(type: .system)
            print("\(type.rawValue) audio device set to \"\(device.name)\"")
            notifyIfEnabled(flag: notify, type: type, deviceName: device.name)
        default:
            let device = try AudioManager.cycleNext(type: type)
            print("\(type.rawValue) audio device set to \"\(device.name)\"")
            notifyIfEnabled(flag: notify, type: type, deviceName: device.name)
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

struct MonitorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "monitor",
        abstract: "Watch for device changes and auto-switch the default device"
    )

    @OptionGroup var configOption: ConfigOption

    @Option(
        name: .shortAndLong,
        help: "Device type(s) to watch (input/output/system/all)")
    var type: String = "output"

    func run() throws {
        configOption.apply()

        let types = try parseDeviceTypes(type)
        try Monitor.run(types: types)
    }
}

extension OutputFormat: ExpressibleByArgument {}
extension AudioDeviceType: ExpressibleByArgument {}

SoundCtl.main()

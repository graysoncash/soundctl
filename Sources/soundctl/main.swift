import ArgumentParser
import CoreAudio

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
        subcommands: [Set.self, List.self, Current.self, Next.self, Mute.self],
        defaultSubcommand: Current.self
    )
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

    func run() throws {
        configOption.apply()

        if type == .all {
            try AudioManager.setAllDevicesByName(identifier)
            return
        }

        // Try MAC address format first
        if isMacAddressFormat(identifier) {
            if let device = try? AudioManager.findDevice(byUID: identifier, type: type) {
                try AudioManager.setDevice(device.id, type: type)
                print("\(type.rawValue) audio device set to \"\(device.name)\"")
                return
            }
        }

        // Try as numeric ID
        if let deviceID = UInt32(identifier) {
            if let device = try? AudioManager.findDevice(byID: deviceID, type: type) {
                try AudioManager.setDevice(device.id, type: type)
                print("\(type.rawValue) audio device set to \"\(device.name)\"")
                return
            }
        }

        // Fall back to name matching
        let device = try AudioManager.findDevice(byName: identifier, type: type)
        try AudioManager.setDevice(device.id, type: type)
        print("\(type.rawValue) audio device set to \"\(device.name)\"")
    }

    func isMacAddressFormat(_ string: String) -> Bool {
        let macPattern = #"^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}$"#
        return string.range(of: macPattern, options: .regularExpression) != nil
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

import Foundation
import TOMLKit

struct Config: Codable {
    static let defaultConfigPath = ".config/soundctl/config.toml"

    static var configPath: String?

    let ignoreDevices: DeviceFilter
    let includeDevices: DeviceFilter
    let aliases: [String: Alias]
    let behavior: Behavior
    let monitor: MonitorConfig
    let exclusive: Exclusive

    enum CodingKeys: String, CodingKey {
        case ignoreDevices
        case includeDevices
        case aliases
        case behavior
        case monitor
        case exclusive
    }

    struct DeviceFilter: Codable {
        let names: [String]
        let uids: [String]

        var isEmpty: Bool { names.isEmpty && uids.isEmpty }

        enum CodingKeys: String, CodingKey {
            case names
            case uids
        }

        init(names: [String] = [], uids: [String] = []) {
            self.names = names
            self.uids = uids
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            names = try container.decodeIfPresent([String].self, forKey: .names) ?? []
            uids = try container.decodeIfPresent([String].self, forKey: .uids) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if !names.isEmpty { try container.encode(names, forKey: .names) }
            if !uids.isEmpty { try container.encode(uids, forKey: .uids) }
        }
    }

    struct Alias: Codable {
        let device: String
        let types: [AudioDeviceType]

        init(device: String, types: [AudioDeviceType]) {
            self.device = device
            self.types = types.isEmpty ? [.output] : types
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            device = try container.decode(String.self, forKey: .device)
            types = try container.decodeIfPresent([AudioDeviceType].self, forKey: .types) ?? [.output]
        }
    }

    /// General behavior toggles.
    struct Behavior: Codable {
        /// Post a macOS notification when `set`/`next` change the device.
        let notify: Bool

        var isEmpty: Bool { !notify }

        enum CodingKeys: String, CodingKey {
            case notify
        }

        init(notify: Bool = false) {
            self.notify = notify
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            notify = try container.decodeIfPresent(Bool.self, forKey: .notify) ?? false
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if notify { try container.encode(notify, forKey: .notify) }
        }
    }

    /// Per-type priority lists that drive `soundctl monitor`. Each list holds
    /// device names (or MAC addresses) in preference order; monitor switches to
    /// the first entry that is currently present.
    struct MonitorConfig: Codable {
        let input: [String]
        let output: [String]
        let system: [String]

        var isEmpty: Bool { input.isEmpty && output.isEmpty && system.isEmpty }

        enum CodingKeys: String, CodingKey {
            case input
            case output
            case system
        }

        init(input: [String] = [], output: [String] = [], system: [String] = []) {
            self.input = input
            self.output = output
            self.system = system
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            input = try container.decodeIfPresent([String].self, forKey: .input) ?? []
            output = try container.decodeIfPresent([String].self, forKey: .output) ?? []
            system = try container.decodeIfPresent([String].self, forKey: .system) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if !input.isEmpty { try container.encode(input, forKey: .input) }
            if !output.isEmpty { try container.encode(output, forKey: .output) }
            if !system.isEmpty { try container.encode(system, forKey: .system) }
        }

        /// The configured priority list for a type. `.all` maps to the output
        /// list since that is the type monitor drives by default.
        func priority(for type: AudioDeviceType) -> [String] {
            switch type {
            case .input:
                return input
            case .output, .all:
                return output
            case .system:
                return system
            }
        }
    }

    /// Groups of Bluetooth devices that must never be connected at the same
    /// time. Once `set` confirms the target device is reachable, every other
    /// connected member of any group it belongs to is disconnected; a failed
    /// switch leaves them alone. Entries are device names or MAC addresses,
    /// resolved against the paired-device list.
    struct Exclusive: Codable {
        let groups: [[String]]

        var isEmpty: Bool { groups.isEmpty }

        enum CodingKeys: String, CodingKey {
            case groups
        }

        init(groups: [[String]] = []) {
            self.groups = groups
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            groups = try container.decodeIfPresent([[String]].self, forKey: .groups) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if !groups.isEmpty { try container.encode(groups, forKey: .groups) }
        }
    }

    init(
        ignoreDevices: DeviceFilter = DeviceFilter(),
        includeDevices: DeviceFilter = DeviceFilter(),
        aliases: [String: Alias] = [:],
        behavior: Behavior = Behavior(),
        monitor: MonitorConfig = MonitorConfig(),
        exclusive: Exclusive = Exclusive()
    ) {
        self.ignoreDevices = ignoreDevices
        self.includeDevices = includeDevices
        self.aliases = aliases
        self.behavior = behavior
        self.monitor = monitor
        self.exclusive = exclusive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ignoreDevices =
            try container.decodeIfPresent(DeviceFilter.self, forKey: .ignoreDevices)
            ?? DeviceFilter()
        includeDevices =
            try container.decodeIfPresent(DeviceFilter.self, forKey: .includeDevices)
            ?? DeviceFilter()
        aliases = try container.decodeIfPresent([String: Alias].self, forKey: .aliases) ?? [:]
        behavior = try container.decodeIfPresent(Behavior.self, forKey: .behavior) ?? Behavior()
        monitor =
            try container.decodeIfPresent(MonitorConfig.self, forKey: .monitor) ?? MonitorConfig()
        exclusive =
            try container.decodeIfPresent(Exclusive.self, forKey: .exclusive) ?? Exclusive()
    }

    // Only write populated sections so a config holding just aliases stays tidy.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !ignoreDevices.isEmpty { try container.encode(ignoreDevices, forKey: .ignoreDevices) }
        if !includeDevices.isEmpty { try container.encode(includeDevices, forKey: .includeDevices) }
        if !aliases.isEmpty { try container.encode(aliases, forKey: .aliases) }
        if !behavior.isEmpty { try container.encode(behavior, forKey: .behavior) }
        if !monitor.isEmpty { try container.encode(monitor, forKey: .monitor) }
        if !exclusive.isEmpty { try container.encode(exclusive, forKey: .exclusive) }
    }

    static func load() -> Config? {
        guard let configPath = configFilePath() else { return nil }
        guard FileManager.default.fileExists(atPath: configPath.path) else { return nil }

        guard let toml = try? String(contentsOf: configPath, encoding: .utf8) else { return nil }
        return try? TOMLDecoder().decode(Config.self, from: toml)
    }

    static func loadForEditing() -> Config {
        load() ?? Config()
    }

    func save() throws {
        guard let path = Config.configFilePath() else {
            throw AudioError.propertyError("Could not determine config file path")
        }
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        let toml = try TOMLEncoder().encode(self)
        try toml.write(to: path, atomically: true, encoding: .utf8)
    }

    func withAliases(_ aliases: [String: Alias]) -> Config {
        Config(
            ignoreDevices: ignoreDevices, includeDevices: includeDevices, aliases: aliases,
            behavior: behavior, monitor: monitor, exclusive: exclusive)
    }

    // Aliases are matched case-insensitively so `set APP` and `set app` agree.
    func alias(named name: String) -> Alias? {
        if let exact = aliases[name] { return exact }
        let lowered = name.lowercased()
        return aliases.first { $0.key.lowercased() == lowered }?.value
    }

    static func configFilePath() -> URL? {
        if let path = configPath {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }

        guard let homeDir = FileManager.default.homeDirectoryForCurrentUser as URL? else {
            return nil
        }
        return homeDir.appendingPathComponent(defaultConfigPath)
    }

    func shouldIgnore(device: AudioDevice) -> Bool {
        if !includeDevices.names.isEmpty || !includeDevices.uids.isEmpty {
            return !matchesFilter(device, filter: includeDevices)
        }

        return matchesFilter(device, filter: ignoreDevices)
    }

    private func matchesFilter(_ device: AudioDevice, filter: DeviceFilter) -> Bool {
        let normalizedDeviceName = normalizeString(device.name)

        for name in filter.names {
            let normalizedFilterName = normalizeString(name)
            if normalizedDeviceName.contains(normalizedFilterName)
                || normalizedFilterName.contains(normalizedDeviceName)
            {
                return true
            }
        }

        for uid in filter.uids {
            if device.uid.contains(uid) {
                return true
            }
        }

        return false
    }

    private func normalizeString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }
}

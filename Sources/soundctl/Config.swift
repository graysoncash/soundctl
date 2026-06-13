import Foundation
import TOMLKit

struct Config: Codable {
    static let defaultConfigPath = ".config/soundctl/config.toml"

    static var configPath: String?

    let ignoreDevices: DeviceFilter
    let includeDevices: DeviceFilter
    let aliases: [String: Alias]

    enum CodingKeys: String, CodingKey {
        case ignoreDevices
        case includeDevices
        case aliases
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

    init(
        ignoreDevices: DeviceFilter = DeviceFilter(),
        includeDevices: DeviceFilter = DeviceFilter(),
        aliases: [String: Alias] = [:]
    ) {
        self.ignoreDevices = ignoreDevices
        self.includeDevices = includeDevices
        self.aliases = aliases
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
    }

    // Only write populated sections so a config holding just aliases stays tidy.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !ignoreDevices.isEmpty { try container.encode(ignoreDevices, forKey: .ignoreDevices) }
        if !includeDevices.isEmpty { try container.encode(includeDevices, forKey: .includeDevices) }
        if !aliases.isEmpty { try container.encode(aliases, forKey: .aliases) }
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
        Config(ignoreDevices: ignoreDevices, includeDevices: includeDevices, aliases: aliases)
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

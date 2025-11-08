import Foundation

struct Config: Codable {
    static let defaultConfigPath = ".config/soundctl/config.json"

    static var configPath: String?

    let ignoreDevices: DeviceFilter
    let includeDevices: DeviceFilter

    struct DeviceFilter: Codable {
        let names: [String]
        let uids: [String]

        init(names: [String] = [], uids: [String] = []) {
            self.names = names
            self.uids = uids
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            names = try container.decodeIfPresent([String].self, forKey: .names) ?? []
            uids = try container.decodeIfPresent([String].self, forKey: .uids) ?? []
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ignoreDevices =
            try container.decodeIfPresent(DeviceFilter.self, forKey: .ignoreDevices)
            ?? DeviceFilter()
        includeDevices =
            try container.decodeIfPresent(DeviceFilter.self, forKey: .includeDevices)
            ?? DeviceFilter()
    }

    static func load() -> Config? {
        guard let configPath = configFilePath() else { return nil }
        guard FileManager.default.fileExists(atPath: configPath.path) else { return nil }

        guard let data = try? Data(contentsOf: configPath) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
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

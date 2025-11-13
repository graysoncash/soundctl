import CoreAudio
import Foundation

struct AudioManager {
    private static let config = Config.load()

    // MARK: - Exact Match Lookups

    static func findDevice(byID id: AudioDeviceID, type: AudioDeviceType) throws -> AudioDevice {
        guard AudioDevice.matchesType(id, type) else {
            throw AudioError.deviceNotFound("ID: \(id)")
        }

        let name = try AudioDevice.deviceName(for: id)
        let uid = try AudioDevice.deviceUID(for: id)

        return AudioDevice(id: id, name: name, uid: uid, type: type)
    }

    static func findDevice(byUID uid: String, type: AudioDeviceType) throws -> AudioDevice {
        let devices = try getAllDevices(type: type)

        guard let device = devices.first(where: { $0.uid.contains(uid) }) else {
            throw AudioError.deviceNotFound("UID: \(uid)")
        }

        return device
    }

    // MARK: - Device Retrieval

    static func getCurrentDevice(type: AudioDeviceType) throws -> AudioDevice {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: type.propertySelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else {
            throw AudioError.propertyError("Failed to get current device: \(status)")
        }

        let name = try AudioDevice.deviceName(for: deviceID)
        let uid = try AudioDevice.deviceUID(for: deviceID)

        return AudioDevice(id: deviceID, name: name, uid: uid, type: type)
    }

    static func getAllDevices(type: AudioDeviceType) throws -> [AudioDevice] {
        let allDeviceIDs = try AudioDevice.allDevices()
        var devices: [AudioDevice] = []

        for deviceID in allDeviceIDs {
            guard AudioDevice.matchesType(deviceID, type) else { continue }

            if let name = try? AudioDevice.deviceName(for: deviceID),
                let uid = try? AudioDevice.deviceUID(for: deviceID)
            {
                let device = AudioDevice(id: deviceID, name: name, uid: uid, type: type)

                if let config = config, config.shouldIgnore(device: device) {
                    continue
                }

                devices.append(device)
            }
        }

        return devices.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.uid < rhs.uid
            }
            return lhs.name < rhs.name
        }
    }

    // MARK: - Name-based Matching (Exact → Fuzzy)

    static func findDevice(byName name: String, type: AudioDeviceType) throws -> AudioDevice {
        let devices = try getAllDevices(type: type)
        let normalizedName = normalizeString(name)

        // Try exact match first (fast path)
        if let device = devices.first(where: { normalizeString($0.name) == normalizedName }) {
            return device
        }

        // Fall back to fuzzy matching
        return try findDeviceWithFuzzyMatching(name: name, devices: devices)
    }

    // MARK: - Fuzzy Matching Helpers

    private static func normalizeString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    private static func tokenize(_ string: String) -> Swift.Set<String> {
        let normalized = normalizeString(string.lowercased())
        let tokens = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return Swift.Set(tokens)
    }

    private static func fuzzyMatchScore(input: String, deviceName: String) -> Double {
        let inputTokens = tokenize(input)
        let deviceTokens = tokenize(deviceName)

        guard !inputTokens.isEmpty && !deviceTokens.isEmpty else {
            return 0.0
        }

        // Count matching tokens
        let matchingTokens = inputTokens.intersection(deviceTokens)

        // Bonus for substring matches (e.g., "airpod" in "airpods")
        var substringMatches = 0
        for inputToken in inputTokens {
            for deviceToken in deviceTokens {
                if deviceToken.contains(inputToken) || inputToken.contains(deviceToken) {
                    substringMatches += 1
                    break
                }
            }
        }

        // Score: weighted combination of exact token matches and substring matches
        let exactMatchScore = Double(matchingTokens.count) / Double(inputTokens.count)
        let substringScore = Double(substringMatches) / Double(inputTokens.count)

        // Favor exact matches but give credit for substrings
        return (exactMatchScore * 0.7) + (substringScore * 0.3)
    }

    private static func findDeviceWithFuzzyMatching(
        name: String,
        devices: [AudioDevice]
    ) throws -> AudioDevice {
        let scored = devices.map { device -> (device: AudioDevice, score: Double) in
            (device, fuzzyMatchScore(input: name, deviceName: device.name))
        }.filter { $0.score > 0.0 }
            .sorted { $0.score > $1.score }

        guard !scored.isEmpty else {
            throw AudioError.deviceNotFound(name)
        }

        let topScore = scored[0].score

        // Check for ambiguity: if multiple devices have very similar scores
        let threshold = 0.05  // 5% difference threshold
        let ambiguousMatches = scored.filter { abs($0.score - topScore) < threshold }

        if ambiguousMatches.count > 1 {
            let matchNames = ambiguousMatches.map { $0.device.name }
            throw AudioError.ambiguousMatch(name, matchNames)
        }

        // Require a minimum score to avoid false positives
        guard topScore >= 0.5 else {
            throw AudioError.deviceNotFound(name)
        }

        return scored[0].device
    }

    static func setDevice(_ deviceID: AudioDeviceID, type: AudioDeviceType) throws {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: type.propertySelector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceIDCopy = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceIDCopy
        )

        guard status == noErr else {
            throw AudioError.propertyError("Failed to set device: \(status)")
        }
    }

    static func cycleNext(type: AudioDeviceType) throws -> AudioDevice {
        let currentDevice = try getCurrentDevice(type: type)
        let allDevices = try getAllDevices(type: type)

        guard !allDevices.isEmpty else {
            throw AudioError.deviceNotFound("No devices available")
        }

        if let currentIndex = allDevices.firstIndex(where: { $0.id == currentDevice.id }) {
            let nextIndex = (currentIndex + 1) % allDevices.count
            let nextDevice = allDevices[nextIndex]
            try setDevice(nextDevice.id, type: type)
            return nextDevice
        }

        let firstDevice = allDevices[0]
        try setDevice(firstDevice.id, type: type)
        return firstDevice
    }

    static func setMute(_ action: MuteAction, type: AudioDeviceType) throws {
        guard type != .system && type != .all else {
            throw AudioError.muteNotSupported
        }

        let currentDevice = try getCurrentDevice(type: type)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: type.scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var muteValue: UInt32

        switch action {
        case .mute:
            muteValue = 1
        case .unmute:
            muteValue = 0
        case .toggle:
            var currentMute: UInt32 = 0
            var dataSize = UInt32(MemoryLayout<UInt32>.size)

            let getStatus = AudioObjectGetPropertyData(
                currentDevice.id,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                &currentMute
            )

            guard getStatus == noErr else {
                throw AudioError.propertyError("Failed to get mute state: \(getStatus)")
            }

            muteValue = currentMute == 0 ? 1 : 0
        }

        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(
            currentDevice.id,
            &propertyAddress,
            0,
            nil,
            dataSize,
            &muteValue
        )

        guard status == noErr else {
            throw AudioError.propertyError("Failed to set mute state: \(status)")
        }

        let muteState = muteValue == 1 ? "muted" : "unmuted"
        print("Setting device \(currentDevice.name) to \(muteState)")
    }

    static func setAllDevicesByName(_ name: String) throws {
        var successCount = 0

        if let inputDevice = try? findDevice(byName: name, type: .input) {
            if (try? setDevice(inputDevice.id, type: .input)) != nil {
                print("input audio device set to \"\(name)\"")
                successCount += 1
            }
        }

        if let outputDevice = try? findDevice(byName: name, type: .output) {
            if (try? setDevice(outputDevice.id, type: .output)) != nil {
                print("output audio device set to \"\(name)\"")
                successCount += 1
            }
        }

        if let systemDevice = try? findDevice(byName: name, type: .system) {
            if (try? setDevice(systemDevice.id, type: .system)) != nil {
                print("system audio device set to \"\(name)\"")
                successCount += 1
            }
        }

        guard successCount > 0 else {
            throw AudioError.deviceNotFound(name)
        }
    }
}

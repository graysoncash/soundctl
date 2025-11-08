import CoreAudio
import Foundation

struct AudioManager {
    private static let config = Config.load()

    private static func normalizeString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

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

    static func findDevice(byName name: String, type: AudioDeviceType) throws -> AudioDevice {
        let devices = try getAllDevices(type: type)
        let normalizedName = normalizeString(name)

        guard let device = devices.first(where: { normalizeString($0.name) == normalizedName })
        else {
            throw AudioError.deviceNotFound(name)
        }

        return device
    }

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

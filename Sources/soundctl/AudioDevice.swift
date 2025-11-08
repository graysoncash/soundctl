import CoreAudio
import Foundation

struct AudioDevice: Codable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let type: AudioDeviceType
    let macAddress: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case uid
        case type
        case macAddress = "mac_address"
    }

    init(id: AudioDeviceID, name: String, uid: String, type: AudioDeviceType) {
        self.id = id
        self.name = name
        self.uid = uid
        self.type = type
        self.macAddress = Self.extractMacAddress(from: uid)
    }

    static func extractMacAddress(from uid: String) -> String? {
        let macPattern = #"([0-9A-Fa-f]{2}(?:-[0-9A-Fa-f]{2}){5})"#
        guard let regex = try? NSRegularExpression(pattern: macPattern),
            let match = regex.firstMatch(in: uid, range: NSRange(uid.startIndex..., in: uid)),
            let range = Range(match.range, in: uid)
        else {
            return nil
        }
        return String(uid[range])
    }

    func format(as outputFormat: OutputFormat) -> String {
        switch outputFormat {
        case .human:
            if let mac = macAddress {
                return "\(name) (\(mac))"
            }
            return name
        case .cli:
            let mac = macAddress ?? ""
            return "\(name),\(type),\(id),\(uid),\(mac)"
        case .json:
            if let data = try? JSONEncoder().encode(self),
                let json = String(data: data, encoding: .utf8)
            {
                return json
            }
            return "{}"
        }
    }
}

extension AudioDevice {
    static func allDevices() throws -> [AudioDeviceID] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            throw AudioError.propertyError("Failed to get device list size: \(status)")
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &devices
        )

        guard status == noErr else {
            throw AudioError.propertyError("Failed to get device list: \(status)")
        }

        return devices
    }

    static func deviceName(for deviceID: AudioDeviceID) throws -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var deviceName: CFString?

        let status = withUnsafeMutablePointer(to: &deviceName) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                pointer
            )
        }

        guard status == noErr, let deviceName = deviceName else {
            throw AudioError.propertyError("Failed to get device name: \(status)")
        }

        return deviceName as String
    }

    static func deviceUID(for deviceID: AudioDeviceID) throws -> String {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize = UInt32(MemoryLayout<CFString>.size)
        var deviceUID: CFString?

        let status = withUnsafeMutablePointer(to: &deviceUID) { pointer in
            AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                pointer
            )
        }

        guard status == noErr, let deviceUID = deviceUID else {
            throw AudioError.propertyError("Failed to get device UID: \(status)")
        }

        return deviceUID as String
    }

    static func isInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }

    static func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }

    static func matchesType(_ deviceID: AudioDeviceID, _ type: AudioDeviceType) -> Bool {
        switch type {
        case .input:
            return isInputDevice(deviceID)
        case .output, .system:
            return isOutputDevice(deviceID)
        case .all:
            return isInputDevice(deviceID) || isOutputDevice(deviceID)
        }
    }
}

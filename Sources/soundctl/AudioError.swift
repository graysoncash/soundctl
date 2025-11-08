import Foundation

enum AudioError: Error, CustomStringConvertible {
    case propertyError(String)
    case deviceNotFound(String)
    case invalidDeviceType
    case muteNotSupported

    var description: String {
        switch self {
        case .propertyError(let message):
            return message
        case .deviceNotFound(let name):
            return "Device not found: \(name)"
        case .invalidDeviceType:
            return "Invalid device type"
        case .muteNotSupported:
            return "Mute is not supported for this device type"
        }
    }
}

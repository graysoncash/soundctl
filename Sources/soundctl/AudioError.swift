import Foundation

enum AudioError: Error, CustomStringConvertible {
    case propertyError(String)
    case deviceNotFound(String)
    case ambiguousMatch(String, [String])
    case invalidDeviceType
    case muteNotSupported

    var description: String {
        switch self {
        case .propertyError(let message):
            return message
        case .deviceNotFound(let name):
            return "Device not found: \(name)"
        case .ambiguousMatch(let input, let matches):
            let matchList = matches.map { "  - \($0)" }.joined(separator: "\n")
            return
                "Ambiguous device name '\(input)'. Multiple matches found:\n\(matchList)\nPlease be more specific."
        case .invalidDeviceType:
            return "Invalid device type"
        case .muteNotSupported:
            return "Mute is not supported for this device type"
        }
    }
}

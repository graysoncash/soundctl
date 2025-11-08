import CoreAudio
import Foundation

enum AudioDeviceType: String, CaseIterable, Codable {
    case input
    case output
    case system
    case all

    var propertySelector: AudioObjectPropertySelector {
        switch self {
        case .input:
            return kAudioHardwarePropertyDefaultInputDevice
        case .output:
            return kAudioHardwarePropertyDefaultOutputDevice
        case .system:
            return kAudioHardwarePropertyDefaultSystemOutputDevice
        case .all:
            return kAudioHardwarePropertyDefaultOutputDevice
        }
    }

    var scope: AudioObjectPropertyScope {
        switch self {
        case .input:
            return kAudioObjectPropertyScopeInput
        case .output:
            return kAudioObjectPropertyScopeOutput
        case .system:
            return kAudioObjectPropertyScopeGlobal
        case .all:
            return kAudioObjectPropertyScopeGlobal
        }
    }
}

enum MuteAction: String {
    case mute
    case unmute
    case toggle
}

enum OutputFormat: String {
    case human
    case cli
    case json
}

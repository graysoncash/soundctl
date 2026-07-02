import CoreAudio
import Foundation

/// Watches the CoreAudio device list and automatically switches the default
/// device when hardware comes and goes.
///
/// For each watched type the behavior is:
///   - If a `[monitor]` priority list is configured for that type, switch to the
///     highest-ranked device that is currently present.
///   - Otherwise (fallback) switch to whatever device of that type was just
///     connected.
///
/// Blocklisted devices are never chosen — reconciliation runs over
/// `AudioManager.getAllDevices`, which already applies the config filter.
final class Monitor {
    private let watched: [AudioDeviceType]
    private let config: Config?

    /// Last known device IDs per watched type, used to detect newly-connected
    /// devices for the fallback path.
    private var previous: [AudioDeviceType: Swift.Set<AudioDeviceID>] = [:]

    /// Serial queue the CoreAudio listener block runs on; also serializes all
    /// access to `previous`.
    private let queue = DispatchQueue(label: "cash.grayson.soundctl.monitor")

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private init(watched: [AudioDeviceType], config: Config?) {
        self.watched = watched
        self.config = config
    }

    /// Start monitoring the given types and block forever (until SIGINT). The
    /// requested types are expanded so `.all` covers input, output, and system.
    static func run(types: [AudioDeviceType]) throws {
        let watched = expand(types)
        let monitor = Monitor(watched: watched, config: Config.load())
        try monitor.start()
    }

    private static func expand(_ types: [AudioDeviceType]) -> [AudioDeviceType] {
        if types.contains(.all) {
            return [.input, .output, .system]
        }
        var seen: [AudioDeviceType] = []
        for type in types where !seen.contains(type) {
            seen.append(type)
        }
        return seen.isEmpty ? [.output] : seen
    }

    private func start() throws {
        // Establish a baseline and apply any priority lists immediately so the
        // right device is selected the moment monitoring begins.
        for type in watched {
            let present = (try? AudioManager.getAllDevices(type: type)) ?? []
            previous[type] = Swift.Set(present.map(\.id))

            let list = config?.monitor.priority(for: type) ?? []
            if !list.isEmpty {
                reconcilePriority(type: type, list: list, present: present)
            }
        }

        printBanner()
        try registerListener()
        installSignalHandler()

        // Block forever; the SIGINT source and the listener queue keep working.
        dispatchMain()
    }

    // MARK: - CoreAudio listener

    private func registerListener() throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue
        ) { [weak self] _, _ in
            self?.handleDeviceListChange()
        }

        guard status == noErr else {
            throw AudioError.propertyError("Failed to register device listener: \(status)")
        }
    }

    /// Reconcile every watched type against the current device list. Runs on
    /// `queue`, so `previous` is accessed single-threaded.
    private func handleDeviceListChange() {
        for type in watched {
            let present = (try? AudioManager.getAllDevices(type: type)) ?? []
            let currentIDs = Swift.Set(present.map(\.id))
            let list = config?.monitor.priority(for: type) ?? []

            if !list.isEmpty {
                reconcilePriority(type: type, list: list, present: present)
            } else {
                let added = currentIDs.subtracting(previous[type] ?? [])
                if let newDevice = present.first(where: { added.contains($0.id) }) {
                    switchTo(newDevice, type: type)
                }
            }

            previous[type] = currentIDs
        }
    }

    // MARK: - Reconciliation

    /// Switch to the first device in `list` that is currently present.
    private func reconcilePriority(type: AudioDeviceType, list: [String], present: [AudioDevice]) {
        for wanted in list {
            if let match = present.first(where: { Monitor.matches($0, wanted: wanted) }) {
                switchTo(match, type: type)
                return
            }
        }
    }

    private func switchTo(_ device: AudioDevice, type: AudioDeviceType) {
        // Skip if it is already the default for this type.
        if let current = try? AudioManager.getCurrentDevice(type: type), current.id == device.id {
            return
        }

        do {
            try AudioManager.setDevice(device.id, type: type)
            let stamp = Monitor.timestamp.string(from: Date())
            print("[\(stamp)] \(type.rawValue) → \(device.name)")
            Notifier.notify(
                title: "soundctl", body: "\(type.rawValue.capitalized): \(device.name)")
        } catch {
            FileHandle.standardError.write(
                Data("monitor: failed to set \(type.rawValue) to \"\(device.name)\"\n".utf8))
        }
    }

    /// Match a priority-list entry (a device name or MAC address) against a
    /// device, mirroring the substring/normalized matching used elsewhere.
    private static func matches(_ device: AudioDevice, wanted: String) -> Bool {
        let normalizedWanted = normalize(wanted)

        // MAC / UID match (dashes, colons, and dots are interchangeable).
        let macCandidate =
            normalizedWanted
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .lowercased()
        if device.uid.lowercased().contains(macCandidate) {
            return true
        }

        // Name match, substring in either direction.
        let name = normalize(device.name).lowercased()
        let target = normalizedWanted.lowercased()
        return name.contains(target) || target.contains(name)
    }

    private static func normalize(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    // MARK: - Lifecycle

    private func printBanner() {
        let typeList = watched.map(\.rawValue).joined(separator: ", ")
        print("Monitoring \(typeList) devices. Press Ctrl-C to stop.")

        for type in watched {
            let list = config?.monitor.priority(for: type) ?? []
            if list.isEmpty {
                print("  \(type.rawValue): follow newly-connected device")
            } else {
                print("  \(type.rawValue): \(list.joined(separator: " › "))")
            }
        }
    }

    private func installSignalHandler() {
        // Ignore the default handler so the dispatch source can run instead.
        signal(SIGINT, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        source.setEventHandler {
            print("\nStopped monitoring.")
            exit(0)
        }
        source.resume()
        // Keep the source alive for the life of the process.
        Monitor.signalSource = source
    }

    private static var signalSource: DispatchSourceSignal?
}

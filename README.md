# 🔊 soundctl

A command-line utility to control sound devices on macOS, written in Swift.

## Description

This utility controls the sound devices for macOS. You specify the name of the sound device, such as "Built-in Output", and the utility switches the device immediately without any GUI interaction.

This is a command-line utility only and has no graphical user interface.

## Installation

### Homebrew

```bash
brew tap graysoncash/soundctl
brew install soundctl
```

### Building from Source

```bash
swift build -c release
cp .build/release/soundctl ~/.local/bin/
```

Or use [`just`](https://github.com/casey/just):

```bash
just install   # copy into ~/.local/bin
just link      # or symlink the build output instead
```

Both check that `~/.local/bin` is on your `PATH` and offer to fix your shell config if it isn't.

## Usage

```bash
soundctl <subcommand> [options]
```

### Subcommands

- **current** (default): Show current audio device
- **list**: List all audio devices
- **set** `<identifier>`: Set the audio device
- **next**: Cycle to the next audio device
- **mute** `[action]`: Control mute status
- **alias** `add|list|remove`: Manage device aliases
- **monitor**: Watch for device changes and auto-switch the default device

### Common Options

- **--type, -t** `<type>`: Device type (input/output/system/all). Defaults to output.
- **--format, -f** `<format>`: Output format (human/cli/json). Defaults to human. (Applies to `current` and `list`)

## Examples

### Show current device

```bash
soundctl current
# or just
soundctl
```

Output:
```
Someone's AirPods Max (XX-XX-XX-XX-XX-XX)
```

### Show current device (JSON format)

```bash
soundctl current --format json
```

Output:
```json
{"id":108,"type":"output","name":"Someone's AirPods Max","uid":"XX-XX-XX-XX-XX-XX:output"}
```

### List all output devices

```bash
soundctl list
```

### List all input devices

```bash
soundctl list --type input
```

### List all devices (JSON format)

```bash
soundctl list --format json
```

### Set device by name

```bash
soundctl set "MacBook Pro Speakers"
```

### Set device by MAC address

```bash
soundctl set "XX-XX-XX-XX-XX-XX"
```

### Set device by ID

```bash
soundctl set "93"
```

The `set` command is smart and auto-detects the type of identifier:
- **MAC address format** (XX-XX-XX-XX-XX-XX): Matches via UID
- **Numeric ID**: Matches by device ID
- **Anything else**: Matches by device name

Priority order: MAC address → numeric ID → name (so a device named "123" can still be matched even if there's an ID 123)

### Bluetooth auto-connect

If the identifier doesn't match any active audio device but does match a paired Bluetooth device (by MAC address or name) that isn't currently connected, `set` connects to it over Bluetooth, waits for it to register as an audio device, and then sets it. Use `--bluetooth-timeout <seconds>` to change how long to wait for the device to appear after connecting (default: 10).

This requires Bluetooth permission for your terminal. macOS normally prompts on first use; if your terminal can't prompt (e.g., Warp), add it manually under **System Settings → Privacy & Security → Bluetooth**.

### Exclusive device groups

Declare groups of Bluetooth devices that should never be connected at the same time. When `set` switches to a member of a group, every other connected member is disconnected from Bluetooth — useful when two headsets (say, AirPods Pro and AirPods Max) would otherwise fight over your audio. Rivals are only evicted once the new device is confirmed reachable (registered as an audio device, or its Bluetooth link freshly up), so a `set` that fails — the device is off, out of range, or the command was a misclick — never interrupts whatever is currently playing.

```toml
[exclusive]
groups = [
  ["AirPods Pro", "AirPods Max"],
]
```

Entries are device names or MAC addresses and are matched against the paired-device list, so they work whether or not the device is currently connected. A device can appear in multiple groups. Enforcement requires the same Bluetooth permission as auto-connect; if access is unavailable, `set` still switches the device and prints a note that the group wasn't enforced.

### Aliases

Save a short name for a device (by MAC address or name) along with the device type(s) to apply, so you don't have to type the full identifier. Aliases are stored in your config file (`~/.config/soundctl/config.toml`).

```bash
# Save "app" for AirPods Pro, applied to both input and output
soundctl alias add app "AA:BB:CC:DD:EE:FF" -t input,output

# Save "apm" for AirPods Max, output only (default type is output)
soundctl alias add apm "AirPods Max"

soundctl alias list
soundctl alias remove app
```

Then use the alias anywhere an identifier is expected:

```bash
soundctl set app   # connects (if needed) and sets it as input + output
```

When you `set` an alias, its saved types are applied. Passing `-t` overrides them for that invocation (`soundctl set app -t output` sets output only). Aliases also resolve through Bluetooth auto-connect, so `set app` will connect paired-but-disconnected AirPods first.

### Cycle to next device

```bash
soundctl next
```

### Muting

Toggle the mute state for the currently selected input (e.g., microphone):

```bash
soundctl mute toggle --type input
# or just
soundctl mute
```

Mute the input:

```bash
soundctl mute on --type input
```

Unmute the input:

```bash
soundctl mute off --type input
```

This is useful on a hotkey, e.g., to mute your Teams or Zoom input.

### Monitor mode (auto-switch)

`soundctl monitor` runs in the foreground and watches for audio devices coming and going, automatically switching the default device for you. Press Ctrl-C to stop.

```bash
# Watch output devices (default)
soundctl monitor

# Watch both input and output
soundctl monitor --type input,output
```

For each watched type, the behavior is:

- **Priority list configured** (in the `[monitor]` config section): switch to the highest-ranked device that is currently present. Great for "prefer AirPods, fall back to the display, then the built-in speakers."
- **No list for that type**: follow whatever device of that type was just connected.

```toml
[monitor]
output = ["AirPods Max", "Studio Display", "MacBook Pro Speakers"]
input = ["AirPods Max", "MacBook Pro Microphone"]
```

Blocklisted devices (see [Ignore Devices](#ignore-devices-blocklist)) are never chosen. Monitor mode always posts a notification when it switches.

### Notifications

Pass `--notify` to `set` or `next` to post a macOS notification when the device changes — handy when the command runs from a hotkey and you want visible confirmation:

```bash
soundctl set app --notify
soundctl next --notify
```

To make notifications the default for every `set`/`next`, enable them in your config:

```toml
[behavior]
notify = true
```

### Shell completions

soundctl can generate completion scripts for zsh, bash, and fish. Completions include your saved alias names and the names of your current audio devices.

```bash
# Install the zsh completion onto your fpath
just install-completions

# Or generate scripts for all shells into ./completions
just completions

# Or generate a single script by hand
soundctl --generate-completion-script zsh > /path/on/your/fpath/_soundctl
```

### Understanding IDs

- **id**: Numeric identifier assigned by macOS at runtime. Can change between reboots or reconnections.
- **uid**: Persistent unique identifier string (the MAC address for Bluetooth devices). This is the reliable identifier for matching devices.

## Configuration

You can optionally create a configuration file at `~/.config/soundctl/config.toml` to filter which devices appear in listings and when cycling with the `next` command, define [monitor mode](#monitor-mode-auto-switch) priority lists, and toggle [notifications](#notifications). See [`config.example.toml`](config.example.toml) for a full example.

### Ignore Devices (Blocklist)

```toml
[ignoreDevices]
names = ["Virtual Device", "Aggregate Device"]
uids = ["00-00-00-00-00-00"]
```

### Include Devices (Allowlist)

```toml
[includeDevices]
names = ["MacBook Pro Speakers"]
uids = ["11-22-33-44-55-66"]
```

**Filter Priority:** If `includeDevices` has any entries, only those devices will be shown (allowlist mode). Otherwise, `ignoreDevices` will be used to exclude devices (blocklist mode). Both filters support:
- **names**: Array of device name strings. Matches if the device name contains the string or vice versa.
- **uids**: Array of UID strings (or MAC addresses). Matches if the device UID contains the string.

## Requirements

- macOS 14.0 or later
- Swift 5.9 or later

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

Originally inspired by [switchaudio-osx](https://github.com/deweller/switchaudio-osx) by Devon Weller.

Rewritten in Swift for improved macOS integration and maintainability.

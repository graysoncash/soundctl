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
cp .build/release/soundctl /usr/local/bin/
```

Or use the Makefile:

```bash
make install
```

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

### Understanding IDs

- **id**: Numeric identifier assigned by macOS at runtime. Can change between reboots or reconnections.
- **uid**: Persistent unique identifier string (the MAC address for Bluetooth devices). This is the reliable identifier for matching devices.

## Configuration

You can optionally create a configuration file at `~/.config/soundctl/config.json` to filter which devices appear in listings and when cycling with the `next` command.

### Ignore Devices (Blocklist)

```json
{
  "ignoreDevices": {
    "names": ["Virtual Device", "Aggregate Device"],
    "uids": ["00-00-00-00-00-00"]
  }
}
```

### Include Devices (Allowlist)

```json
{
  "includeDevices": {
    "names": ["MacBook Pro Speakers"],
    "uids": ["11-22-33-44-55-66"]
  }
}
```

**Filter Priority:** If `includeDevices` has any entries, only those devices will be shown (allowlist mode). Otherwise, `ignoreDevices` will be used to exclude devices (blocklist mode). Both filters support:
- **names**: Array of device name strings. Matches if the device name contains the string or vice versa.
- **uids**: Array of UID strings (or MAC addresses). Matches if the device UID contains the string.

## Requirements

- macOS 13.0 or later
- Swift 5.9 or later

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

Originally inspired by [switchaudio-osx](https://github.com/deweller/switchaudio-osx) by Devon Weller.

Rewritten in Swift for improved macOS integration and maintainability.

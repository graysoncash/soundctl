version := `cat VERSION`

# List available recipes
default:
    @just --list

# Generate Version.swift from VERSION file
generate-version:
    @./scripts/generate-version.sh

# Build the binary
build: generate-version
    swift build -c release

# Install the binary to /usr/local/bin
install: build
    sudo cp .build/release/soundctl /usr/local/bin/

# Symlink the built binary into /usr/local/bin
link: build
    sudo ln -sf "$(pwd)/.build/release/soundctl" /usr/local/bin/soundctl

# Remove the binary from /usr/local/bin
uninstall:
    sudo rm -f /usr/local/bin/soundctl

# Generate shell completion scripts into ./completions
completions: build
    @mkdir -p completions
    @.build/release/soundctl --generate-completion-script zsh > completions/_soundctl
    @.build/release/soundctl --generate-completion-script bash > completions/soundctl.bash
    @.build/release/soundctl --generate-completion-script fish > completions/soundctl.fish
    @echo "✅ Wrote completions/ for zsh, bash, and fish"

# Install the zsh completion into a directory on your fpath
install-completions: build
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v brew >/dev/null 2>&1; then
        dest="$(brew --prefix)/share/zsh/site-functions"
    else
        dest="${HOME}/.zsh/completions"
    fi
    mkdir -p "$dest"
    .build/release/soundctl --generate-completion-script zsh > "$dest/_soundctl"
    echo "✅ Installed zsh completion to $dest/_soundctl"
    echo "   Ensure that directory is on your fpath, then run: compinit"

# Clean the build artifacts
clean:
    swift package clean

# Show current version
version:
    @echo "Current version: {{version}}"
    @echo "Existing tags:"
    @git tag -l

# Create and push a release tag
release:
    @if git rev-parse v{{version}} >/dev/null 2>&1; then \
        echo "❌ Tag v{{version}} already exists!"; \
        echo "Update the VERSION file to a new version before releasing."; \
        exit 1; \
    fi
    @echo "Creating release v{{version}}..."
    git tag -a v{{version}} -m "Release v{{version}}"
    git push origin v{{version}}
    @echo ""
    @echo "✅ Tag v{{version}} created and pushed!"
    @echo ""
    @echo "Next steps:"
    @echo "  1. Create GitHub release at: https://github.com/graysoncash/soundctl/releases/new?tag=v{{version}}"
    @echo "  2. Wait for release to be published"
    @echo "  3. Run: just update-formula"

# Update Homebrew formula after GitHub release
update-formula:
    @./scripts/prepare-formula.sh --update
    @echo ""
    @echo "Next: cd ../homebrew-soundctl && git add Formula/soundctl.rb && git commit -m 'Update to v{{version}}' && git push"

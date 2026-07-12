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

# Copy the binary into ~/.local/bin
install: build && _check-path
    @mkdir -p "$HOME/.local/bin"
    cp .build/release/soundctl "$HOME/.local/bin/"
    @echo "✅ Installed soundctl into $HOME/.local/bin"

# Symlink the built binary into ~/.local/bin
link: build && _check-path
    @mkdir -p "$HOME/.local/bin"
    ln -sf "$(pwd)/.build/release/soundctl" "$HOME/.local/bin/soundctl"
    @echo "✅ Linked soundctl into $HOME/.local/bin"

# Warn when ~/.local/bin is not on PATH; offer (via gum) to fix the shell config
_check-path:
    #!/usr/bin/env bash
    set -euo pipefail
    case ":$PATH:" in *":$HOME/.local/bin:"*) exit 0 ;; esac

    line='export PATH="$HOME/.local/bin:$PATH"'
    case "$(basename "${SHELL:-}")" in
        zsh)  config="$HOME/.zshrc" ;;
        bash) config="$HOME/.bash_profile" ;;
        *)    config="" ;;
    esac

    # Fall back to a plain warning when gum is missing, the shell config is
    # unknown, or there is no TTY to prompt on.
    if ! command -v gum >/dev/null 2>&1 || [ -z "$config" ] || [ ! -t 0 ]; then
        echo "⚠️  $HOME/.local/bin is not on your PATH. Add this to your shell config:"
        echo "    $line"
        exit 0
    fi

    gum style --foreground 212 "⚠️  ~/.local/bin is not on your PATH."
    if gum confirm "Add it to $config for you?"; then
        printf '\n%s\n' "$line" >> "$config"
        echo "✅ Added to $config — restart your shell or run: source ${config/#$HOME/~}"
    else
        echo "Add this to your shell config when you're ready:"
        echo "    $line"
    fi

# Remove the soundctl symlink from ~/.local/bin
unlink:
    rm -f "$HOME/.local/bin/soundctl"

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

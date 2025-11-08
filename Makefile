.PHONY: build install uninstall clean release update-formula version generate-version

VERSION := $(shell cat VERSION)

generate-version:  # Generate Version.swift from VERSION file
	@./scripts/generate-version.sh

build: generate-version  # Build the binary
	swift build -c release

install: build  # Install the binary to /usr/local/bin
	cp .build/release/soundctl /usr/local/bin/

uninstall:  # Remove the binary from /usr/local/bin
	rm -f /usr/local/bin/soundctl

clean:  # Clean the build artifacts
	swift package clean

version:  # Show current version
	@echo "Current version: $(VERSION)"
	@echo "Existing tags:"
	@git tag -l

release:  # Create and push a release tag
	@if git rev-parse v$(VERSION) >/dev/null 2>&1; then \
		echo "❌ Tag v$(VERSION) already exists!"; \
		echo "Update the VERSION file to a new version before releasing."; \
		exit 1; \
	fi
	@echo "Creating release v$(VERSION)..."
	git tag -a v$(VERSION) -m "Release v$(VERSION)"
	git push origin v$(VERSION)
	@echo ""
	@echo "✅ Tag v$(VERSION) created and pushed!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Create GitHub release at: https://github.com/graysoncash/soundctl/releases/new?tag=v$(VERSION)"
	@echo "  2. Wait for release to be published"
	@echo "  3. Run: make update-formula"

update-formula:  # Update Homebrew formula after GitHub release
	@./scripts/prepare-formula.sh --update
	@echo ""
	@echo "Next: cd ../homebrew-soundctl && git add Formula/soundctl.rb && git commit -m 'Update to v$(VERSION)' && git push"

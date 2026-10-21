set shell := ["bash", "-euo", "pipefail", "-c"]

derived := "build/DerivedData"
release_app := derived + "/Build/Products/Release/Perch.app"
kept := "Tinycast/App Tinycast/Platform Tinycast/Palette Tinycast/DesignSystem Tinycast/Features/Launcher Tinycast/Features/Clipboard Tinycast/Features/Emoji Tinycast/Features/Calculator Tinycast/Features/WindowManagement Tinycast/Features/HotKeys Tinycast/Features/Settings Tinycast/Windows"

default:
    @just --list

# Regenerate Perch.xcodeproj from project.yml
generate:
    xcodegen generate

# Build the signed Release app into build/
build: generate
    xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Release -quiet \
      -destination 'platform=macOS,arch=arm64' -derivedDataPath {{ derived }} build

# Run the swiftc test harnesses
test:
    ./Scripts/run-tests.sh

# Run swiftlint and the project checks
lint:
    ./Scripts/lint.sh

# Format Tinycast/ and Tests/ in place
format:
    ./Scripts/format.sh

# Build, quit the running Perch, copy it to /Applications, and open it
install: build
    #!/usr/bin/env bash
    set -euo pipefail
    /usr/bin/osascript -e 'tell application id "com.gstark.perch" to quit' 2>/dev/null || true
    while /usr/bin/pgrep -xq Perch; do /bin/sleep 0.2; done
    /bin/rm -rf /Applications/Perch.app
    /usr/bin/ditto "{{ release_app }}" /Applications/Perch.app
    /usr/bin/open /Applications/Perch.app
    echo "Installed /Applications/Perch.app"

# Fetch upstream Tinycast and list unreviewed commits that touch the kept folders
upstream:
    git fetch --quiet upstream
    git log --oneline --no-merges "$(cat .upstream-reviewed)..upstream/main" -- {{ kept }}

# Record upstream/main as reviewed, so `just upstream` lists only newer commits
upstream-reviewed:
    git rev-parse upstream/main > .upstream-reviewed

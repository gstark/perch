set shell := ["bash", "-euo", "pipefail", "-c"]

derived := "build/DerivedData"
release_app := derived + "/Build/Products/Release/Perch.app"
repo := "gstark/perch"
tap := "gstark/tap"
cask := "perch"
kept := "Tinycast/App Tinycast/Platform Tinycast/Palette Tinycast/DesignSystem Tinycast/Features/Launcher Tinycast/Features/Clipboard Tinycast/Features/Emoji Tinycast/Features/Calculator Tinycast/Features/WindowManagement Tinycast/Features/HotKeys Tinycast/Features/Settings Tinycast/Windows"

default:
    @just --list

# Regenerate Perch.xcodeproj from project.yml
generate:
    xcodegen generate

# Build the signed Release app into build/. Extra arguments go to xcodebuild.
build *settings: generate
    xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Release -quiet \
      -destination 'platform=macOS,arch=arm64' -derivedDataPath {{ derived }} {{ settings }} build

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

# Build, publish a GitHub release, and update the cask in the Homebrew tap
homebrew:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "$(git status --porcelain)" ]]; then
      echo "The working tree has changes. Commit them first." >&2
      exit 1
    fi

    base="$(/usr/bin/awk '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }' project.yml)"
    stamp="$(/bin/date +%Y%m%d%H%M)"
    version="${base}-${stamp}"
    zip="build/Perch-${version}.zip"

    just build CURRENT_PROJECT_VERSION="$stamp"
    /bin/rm -f build/Perch-*.zip
    /usr/bin/ditto -c -k --keepParent "{{ release_app }}" "$zip"
    sha="$(/usr/bin/shasum -a 256 "$zip" | /usr/bin/cut -d' ' -f1)"

    git push origin "$(git branch --show-current)"
    gh release create "v${version}" "$zip" -R {{ repo }} \
      --target "$(git rev-parse HEAD)" \
      --title "Perch $version" \
      --notes "Build of $(git rev-parse --short HEAD)."

    tap_dir="$(brew --repository {{ tap }})"
    git -C "$tap_dir" pull --ff-only
    /bin/mkdir -p "$tap_dir/Casks"
    cat > "$tap_dir/Casks/{{ cask }}.rb" <<EOF
    cask "{{ cask }}" do
      version "$version"
      sha256 "$sha"

      url "https://github.com/{{ repo }}/releases/download/v#{version}/Perch-#{version}.zip"
      name "Perch"
      desc "Menu bar launcher, clipboard history, calculator and window manager"
      homepage "https://github.com/{{ repo }}"

      depends_on arch: :arm64
      depends_on macos: :tahoe

      app "Perch.app"

      # The build is signed but not notarized, so remove the quarantine flag to let it open.
      postflight_steps do
        run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{{{appdir}}/Perch.app"]
      end

      uninstall quit: "com.gstark.perch"
    end
    EOF
    git -C "$tap_dir" add "Casks/{{ cask }}.rb"
    git -C "$tap_dir" commit -m "{{ cask }} $version"
    git -C "$tap_dir" push

    echo "Released $version. Run 'brew install {{ tap }}/{{ cask }}' to install it."

# Fetch upstream Tinycast and list unreviewed commits that touch the kept folders
upstream:
    git fetch --quiet upstream
    git log --oneline --no-merges "$(cat .upstream-reviewed)..upstream/main" -- {{ kept }}

# Record upstream/main as reviewed, so `just upstream` lists only newer commits
upstream-reviewed:
    git rev-parse upstream/main > .upstream-reviewed

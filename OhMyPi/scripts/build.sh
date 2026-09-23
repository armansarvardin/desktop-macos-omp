#!/usr/bin/env bash
#
# Build the Oh My Pi macOS app.
#
#   scripts/build.sh              # Debug build, ad-hoc signed, ready to run
#   scripts/build.sh --release    # Release build
#   scripts/build.sh --run        # Build then launch the app
#
# Output lands in build/Build/Products/<Configuration>/OhMyPi.app.
# Set DEVELOPMENT_TEAM in Config/Local.xcconfig to sign with your own team.

set -euo pipefail

cd "$(dirname "$0")/.."

configuration="Debug"
run_after_build=0

for argument in "$@"; do
    case "$argument" in
        --release) configuration="Release" ;;
        --run) run_after_build=1 ;;
        *)
            echo "unknown option: $argument" >&2
            exit 2
            ;;
    esac
done

xcodebuild \
    -project OhMyPi.xcodeproj \
    -scheme OhMyPi \
    -configuration "$configuration" \
    -destination 'platform=macOS' \
    -derivedDataPath build \
    build \
    | grep -E "error:|warning:|BUILD|\*\* " || true

app="build/Build/Products/$configuration/OhMyPi.app"

if [[ ! -d "$app" ]]; then
    echo "build failed: $app not found" >&2
    exit 1
fi

echo "built $app"

if [[ "$run_after_build" == 1 ]]; then
    open "$app"
fi

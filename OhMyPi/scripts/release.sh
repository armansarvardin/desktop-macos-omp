#!/usr/bin/env bash
#
# Archive, export and package the Oh My Pi macOS app as a DMG.
#
#   scripts/release.sh                       # ad-hoc signed DMG in build/
#   NOTARY_PROFILE=omp scripts/release.sh    # Developer ID signed + notarized
#
# Notarization needs Config/Local.xcconfig with DEVELOPMENT_TEAM and
# CODE_SIGN_IDENTITY = Developer ID Application, plus a keychain profile
# created with: xcrun notarytool store-credentials <profile>.

set -euo pipefail

cd "$(dirname "$0")/.."

version="$(sed -n 's/^MARKETING_VERSION = //p' Config/Base.xcconfig | tr -d '[:space:]')"
archive="build/OhMyPi.xcarchive"
export_dir="build/export"
dmg="build/OhMyPi-$version.dmg"

rm -rf "$archive" "$export_dir" "$dmg"

echo "==> Archiving $version"
xcodebuild \
    -project OhMyPi.xcodeproj \
    -scheme OhMyPi \
    -configuration Release \
    -destination 'platform=macOS' \
    -archivePath "$archive" \
    archive \
    | grep -E "error:|warning:|ARCHIVE|\*\* " || true

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "==> Exporting with Developer ID"
    xcodebuild \
        -exportArchive \
        -archivePath "$archive" \
        -exportOptionsPlist scripts/ExportOptions.plist \
        -exportPath "$export_dir" \
        | grep -E "error:|warning:|EXPORT|\*\* " || true
    app="$export_dir/OhMyPi.app"
else
    echo "==> Using the archived app as is (ad-hoc signature)"
    mkdir -p "$export_dir"
    cp -R "$archive/Products/Applications/OhMyPi.app" "$export_dir/"
    app="$export_dir/OhMyPi.app"
fi

echo "==> Packaging $dmg"
staging="build/dmg"
rm -rf "$staging"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "Oh My Pi" -srcfolder "$staging" -ov -format UDZO "$dmg"
rm -rf "$staging"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
fi

echo "done: $dmg"

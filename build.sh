#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "usage: $0 [install]" >&2
	exit 2
}

[ "$#" -le 1 ] || usage
mode="${1:-build}"
case "$mode" in
build | install) ;;
*) usage ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")"

APP_NAME="Balarm"
BUNDLE_ID="com.toni.balarm"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ICON_PATH="$BUILD_DIR/AppIcon.icns"
# The Radial tone ships with macOS but isn't ours to redistribute, so it's
# pulled from the system at build time instead of being committed.
SYSTEM_SOUND="/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/Radial-EncoreInfinitum.m4r"
INSTALL_PATH="/Applications/$APP_NAME.app"
# Staged on the same volume as the installed app, so moving it into place is a rename.
STAGING_PATH="/Applications/.$APP_NAME.app.installing"

# Checked before anything is built or removed, so a missing tone leaves the
# previous build in place.
[ -f "$SYSTEM_SOUND" ] || {
	echo "error: system alarm sound not found at $SYSTEM_SOUND" >&2
	exit 1
}

swift build -c release --product "$APP_NAME"
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Support/Info.plist "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' >"$APP_BUNDLE/Contents/PkgInfo"
cp "$SYSTEM_SOUND" "$APP_BUNDLE/Contents/Resources/Radial.m4a"

# Regenerating the icon takes a few seconds, so only do it when the script
# that produces it changed or the cached .icns is missing.
if [ ! -f "$ICON_PATH" ] || [ "scripts/make-icon.swift" -nt "$ICON_PATH" ]; then
	swift scripts/make-icon.swift "$ICON_PATH"
fi
cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# No signing identity is configured for this project, so sign ad-hoc; that's
# enough to satisfy Gatekeeper's local-run checks on the build machine.
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
codesign --verify --strict "$APP_BUNDLE"

if [ "$mode" = install ]; then
	# The installed app is replaced only once the copy is complete, so a failed
	# copy leaves the previous version installed.
	rm -rf "$STAGING_PATH"
	ditto "$APP_BUNDLE" "$STAGING_PATH"
	rm -rf "$INSTALL_PATH"
	mv "$STAGING_PATH" "$INSTALL_PATH"
	echo "A running $APP_NAME keeps the previous version in memory until relaunched."
	echo "Installed $INSTALL_PATH"
else
	echo "$APP_BUNDLE"
fi

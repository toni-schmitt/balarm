#!/usr/bin/env bash
set -euo pipefail

usage() {
	echo "usage: $0 [install | release]" >&2
	exit 2
}

[ "$#" -le 1 ] || usage
mode="${1:-build}"
case "$mode" in
build | install | release) ;;
*) usage ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")"

APP_NAME="Balarm"
# Info.plist is the one place the bundle ID is written down.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Support/Info.plist)"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ICON_PATH="$BUILD_DIR/AppIcon.icns"
INSTALL_PATH="/Applications/$APP_NAME.app"
# Staged on the same volume as the installed app, so moving it into place is a rename.
STAGING_PATH="/Applications/.$APP_NAME.app.installing"

SWIFT_BUILD=(swift build -c release)
if [ "$mode" = release ]; then
	# A release runs on Apple silicon and Intel Macs alike.
	SWIFT_BUILD+=(--arch arm64 --arch x86_64)
fi
"${SWIFT_BUILD[@]}" --product "$APP_NAME"
BIN_PATH="$("${SWIFT_BUILD[@]}" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Support/Info.plist "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' >"$APP_BUNDLE/Contents/PkgInfo"

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
	# Moved rather than copied: with a second copy of the app, clicking the alarm's
	# notification started that copy as a second Balarm. The installed app is
	# replaced only once the move is complete, so a failed move leaves the previous
	# version installed.
	rm -rf "$STAGING_PATH"
	mv "$APP_BUNDLE" "$STAGING_PATH"
	rm -rf "$INSTALL_PATH"
	mv "$STAGING_PATH" "$INSTALL_PATH"
	echo "A running $APP_NAME keeps the previous version in memory until relaunched."
	echo "Installed $INSTALL_PATH"
else
	if [ -d "$INSTALL_PATH" ]; then
		echo "warning: both $APP_BUNDLE and $INSTALL_PATH exist; clicking the alarm's notification can start the other copy. Delete one, or run ./build.sh install if Homebrew did not install $INSTALL_PATH." >&2
	fi
	echo "$APP_BUNDLE"
fi

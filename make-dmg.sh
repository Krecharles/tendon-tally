#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./make-dmg.sh [version] [--sign] [--notarize] [--staple] [--validate] [--all]

Examples:
  ./make-dmg.sh v1
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./make-dmg.sh v1 --sign
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="TENDON_TALLY_NOTARY" ./make-dmg.sh v1 --all

Flags:
  --sign       Sign the generated DMG with codesign
  --notarize   Submit DMG to Apple notarization (implies --sign --staple --validate)
  --staple     Staple notarization ticket to DMG
  --validate   Validate stapled notarization ticket
  --all        Run sign + notarize + staple + validate
  --help       Show this help

Env vars:
  SIGN_IDENTITY    Required for --sign/--notarize, e.g. "Developer ID Application: Name (TEAMID)"
  NOTARY_PROFILE   Keychain profile for notarytool (default: TENDON_TALLY_NOTARY)
  APP_NAME         App bundle name in release-input (default: TendonTally.app)
  INPUT_DIR        Input folder for .app (default: ./release-input)
  OUTPUT_DIR       Output folder for .dmg (default: ./release-output)
  VOLUME_NAME      Mounted DMG volume name (default: TendonTally)
  BACKGROUND_IMAGE Optional DMG background image path
  ICON_LEFT_X      Finder icon X for app icon (default: 220)
  ICON_RIGHT_X     Finder icon X for Applications link (default: 580)
  ICON_Y           Finder icon Y for both icons (default: 230)
EOF
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    exit 1
  fi
}

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="${APP_NAME:-TendonTally.app}"
INPUT_DIR="${INPUT_DIR:-$ROOT_DIR/release-input}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/release-output}"
VERSION="v1"
VOLUME_NAME="${VOLUME_NAME:-TendonTally}"
BACKGROUND_IMAGE="${BACKGROUND_IMAGE:-}"
ICON_LEFT_X="${ICON_LEFT_X:-220}"
ICON_RIGHT_X="${ICON_RIGHT_X:-580}"
ICON_Y="${ICON_Y:-230}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-TENDON_TALLY_NOTARY}"
SIGN_DMG=0
NOTARIZE_DMG=0
STAPLE_DMG=0
VALIDATE_DMG=0
POSITIONAL_SET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --sign)
      SIGN_DMG=1
      ;;
    --notarize)
      NOTARIZE_DMG=1
      ;;
    --staple)
      STAPLE_DMG=1
      ;;
    --validate)
      VALIDATE_DMG=1
      ;;
    --all)
      SIGN_DMG=1
      NOTARIZE_DMG=1
      STAPLE_DMG=1
      VALIDATE_DMG=1
      ;;
    --*)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
    *)
      if [ "$POSITIONAL_SET" -eq 0 ]; then
        VERSION="$1"
        POSITIONAL_SET=1
      else
        echo "Unexpected extra positional argument: $1"
        usage
        exit 1
      fi
      ;;
  esac
  shift
done

if [ "$NOTARIZE_DMG" -eq 1 ]; then
  SIGN_DMG=1
  STAPLE_DMG=1
  VALIDATE_DMG=1
fi

if [ "$SIGN_DMG" -eq 1 ] && [ -z "$SIGN_IDENTITY" ]; then
  echo "SIGN_IDENTITY is required for --sign/--notarize."
  echo "Example:"
  echo '  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./make-dmg.sh v1 --all'
  exit 1
fi

APP_PATH="$INPUT_DIR/$APP_NAME"
DMG_PATH="$OUTPUT_DIR/TendonTally-${VERSION}.dmg"
STAGING_DIR="$OUTPUT_DIR/dmg-staging"
RW_DMG_PATH="$OUTPUT_DIR/TendonTally-${VERSION}-rw.dmg"
DEVICE=""
MOUNT_DEVICE=""
MOUNT_POINT=""

detach_image() {
  local target="$1"
  if [ -z "$target" ]; then
    return 1
  fi

  hdiutil detach "$target" >/dev/null 2>&1 \
    || hdiutil detach "$target" -force >/dev/null 2>&1
}

cleanup() {
  if ! detach_image "$DEVICE"; then
    detach_image "$MOUNT_DEVICE" || true
  fi

  if [ -n "$MOUNT_POINT" ]; then
    detach_image "$MOUNT_POINT" || true
  fi
}

trap cleanup EXIT

mkdir -p "$INPUT_DIR"

if [ ! -d "$APP_PATH" ]; then
  echo "Missing app bundle at: $APP_PATH"
  echo "Drop your exported .app here and rerun:"
  echo "  $INPUT_DIR/$APP_NAME"
  exit 1
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
mkdir -p "$OUTPUT_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

USE_BACKGROUND=0
if [ -n "$BACKGROUND_IMAGE" ] && [ -f "$BACKGROUND_IMAGE" ]; then
  mkdir -p "$STAGING_DIR/.background"
  cp "$BACKGROUND_IMAGE" "$STAGING_DIR/.background/background.png"
  USE_BACKGROUND=1
elif [ -n "$BACKGROUND_IMAGE" ]; then
  echo "Warning: BACKGROUND_IMAGE not found at '$BACKGROUND_IMAGE'. Continuing without background."
fi

rm -f "$RW_DMG_PATH"
rm -f "$DMG_PATH"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  "$RW_DMG_PATH" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG_PATH")"
DEVICE="$(echo "$ATTACH_OUTPUT" | awk '/^\/dev\//{print $1; exit}')"
MOUNT_DEVICE="$(echo "$ATTACH_OUTPUT" | awk '/\/Volumes\//{print $1; exit}')"
MOUNT_POINT="$(echo "$ATTACH_OUTPUT" | awk '/\/Volumes\//{print $NF; exit}')"

if [ -z "$DEVICE" ]; then
  echo "Failed to find mounted device for DMG."
  exit 1
fi

export TT_VOLUME_NAME="$VOLUME_NAME"
export TT_APP_NAME="$APP_NAME"
export TT_USE_BACKGROUND="$USE_BACKGROUND"
export TT_ICON_LEFT_X="$ICON_LEFT_X"
export TT_ICON_RIGHT_X="$ICON_RIGHT_X"
export TT_ICON_Y="$ICON_Y"

if ! osascript <<'APPLESCRIPT'
set volumeName to system attribute "TT_VOLUME_NAME"
set appName to system attribute "TT_APP_NAME"
set useBackground to system attribute "TT_USE_BACKGROUND"
set iconLeftX to (system attribute "TT_ICON_LEFT_X") as integer
set iconRightX to (system attribute "TT_ICON_RIGHT_X") as integer
set iconY to (system attribute "TT_ICON_Y") as integer

tell application "Finder"
  tell disk volumeName
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 920, 620}

    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 16

    if useBackground is "1" then
      set background picture of viewOptions to file ".background:background.png"
    end if

    set position of item appName of container window to {iconLeftX, iconY}
    set position of item "Applications" of container window to {iconRightX, iconY}

    close
    open
    update without registering applications
    delay 1
  end tell
end tell
APPLESCRIPT
then
  echo "Warning: Could not apply Finder styling. Continuing with standard DMG layout."
fi

# Mark the mounted folder to auto-open in Finder when users mount the DMG.
if [ -n "${MOUNT_POINT:-}" ] && [ -d "$MOUNT_POINT" ]; then
  if ! bless --folder "$MOUNT_POINT" --openfolder "$MOUNT_POINT" >/dev/null 2>&1; then
    echo "Warning: Could not set auto-open folder metadata."
  fi
fi

sync
if ! detach_image "$DEVICE"; then
  if ! detach_image "$MOUNT_DEVICE"; then
    if ! detach_image "$MOUNT_POINT"; then
      echo "Warning: Failed to detach mounted image cleanly."
    fi
  fi
fi
DEVICE=""
MOUNT_DEVICE=""
MOUNT_POINT=""

hdiutil convert "$RW_DMG_PATH" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH" >/dev/null
rm -f "$RW_DMG_PATH"
rm -rf "$STAGING_DIR"

if [ "$SIGN_DMG" -eq 1 ]; then
  require_command codesign
  echo "Signing DMG with identity: $SIGN_IDENTITY"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if [ "$NOTARIZE_DMG" -eq 1 ]; then
  require_command xcrun
  echo "Submitting DMG for notarization with profile: $NOTARY_PROFILE"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
fi

if [ "$STAPLE_DMG" -eq 1 ]; then
  require_command xcrun
  echo "Stapling notarization ticket..."
  xcrun stapler staple "$DMG_PATH"
fi

if [ "$VALIDATE_DMG" -eq 1 ]; then
  require_command xcrun
  echo "Validating notarization staple..."
  xcrun stapler validate "$DMG_PATH"
fi

echo "Created DMG:"
echo "  $DMG_PATH"

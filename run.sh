#!/bin/bash
# Run script for TendonTally using Xcode so the app bundle (with icon) is built

set -e

PROJECT_PATH="$(cd "$(dirname "$0")" && pwd)/TendonTally/TendonTally.xcodeproj"
DERIVED_DATA_PATH="$(cd "$(dirname "$0")" && pwd)/.xcode-build"

echo "Building TendonTally with Xcode (for proper app bundle & icon)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "TendonTally" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/TendonTally.app"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: Built app not found at: $APP_PATH"
  exit 1
fi

echo "Opening TendonTally.app..."
open "$APP_PATH"

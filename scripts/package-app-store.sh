#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

TEAM_ID="${DEVELOPMENT_TEAM:-T8U342A235}"
BUNDLE_ID="${BUNDLE_ID:-com.zairuilab.promptpick}"
APP_VERSION="${APP_VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/build/AppStoreRelease}"
ARCHIVE_PATH="$OUTPUT_DIR/PromptPick.xcarchive"
EXPORT_DIR="$OUTPUT_DIR/export"
EXPORT_OPTIONS="$OUTPUT_DIR/ExportOptions.plist"

mkdir -p "$OUTPUT_DIR" "$EXPORT_DIR"

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>$TEAM_ID</string>
<key>destination</key><string>export</string>
</dict></plist>
PLIST

xcodebuild archive \
  -project Maccy.xcodeproj \
  -scheme Maccy \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination 'generic/platform=macOS' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  MARKETING_VERSION="$APP_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_ENTITLEMENTS=Maccy/Maccy-AppStore.entitlements \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) APP_STORE_BUILD'

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

echo "App Store package: $EXPORT_DIR/PromptPick.pkg"

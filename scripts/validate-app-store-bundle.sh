#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?usage: validate-app-store-bundle.sh /path/to/PromptPick.app}"
EXPECTED_BUNDLE_ID="${BUNDLE_ID:-com.zairuilab.promptpick}"

test -d "$APP_PATH"

actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
encryption="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$APP_PATH/Contents/Info.plist")"

[[ "$actual_bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || { echo "Bundle ID mismatch: $actual_bundle_id"; exit 1; }
[[ "$encryption" == "false" ]] || { echo "Export compliance flag must be false"; exit 1; }
[[ ! -e "$APP_PATH/Contents/Frameworks/Sparkle.framework" ]] || { echo "Sparkle must not ship in the App Store build"; exit 1; }
[[ -e "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy" ]] || { echo "PrivacyInfo.xcprivacy missing"; exit 1; }

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'

echo "Validated PromptPick $actual_version ($actual_build) — $actual_bundle_id"

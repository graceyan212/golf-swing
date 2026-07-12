#!/bin/bash
# Build Swing Check, sign it with the existing (Xcode-managed) provisioning
# profile + Apple Development cert, and install to Grace's iPhone — no Xcode
# GUI / no Apple ID sign-in needed. Run from the ios/ directory.
set -e
cd "$(dirname "$0")"

DEV="00008150-001534D211DB401C"                     # Grace's iPhone
IDENT="D21106FABCEC0ABF8B608B804B3CFB41094992A4"    # Apple Development cert
PROF="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/d3351ce1-ee93-41e3-b04b-88fd8c2a4d55.mobileprovision"
APP=/tmp/SwingCheck.app

echo "▸ Building…"
# ENABLE_DEBUG_DYLIB=NO -> single signed binary (no unsigned SwingCheck.debug.dylib
# that dyld would reject on a real device).
xcodebuild -project SwingCheck.xcodeproj -scheme SwingCheck -configuration Debug \
  -sdk iphoneos -derivedDataPath build-dev CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO build \
  >/tmp/swingcheck_build.log 2>&1 || { echo "✗ Build failed:"; grep -E "error:" /tmp/swingcheck_build.log | head; exit 1; }

SRC=build-dev/Build/Products/Debug-iphoneos/SwingCheck.app
echo "▸ Signing…"
rm -rf "$APP"; ditto "$SRC" "$APP"
cp "$PROF" "$APP/embedded.mobileprovision"
find "$APP" -print0 | xargs -0 xattr -c 2>/dev/null || true
security cms -D -i "$PROF" 2>/dev/null | plutil -extract Entitlements xml1 -o /tmp/swingcheck_ent.plist -
# Sign any nested code first (dylibs/frameworks), then the app bundle.
find "$APP" \( -name "*.dylib" -o -name "*.framework" -o -name "*.appex" \) -print0 2>/dev/null \
  | xargs -0 -I{} codesign --force --sign "$IDENT" --timestamp=none "{}" 2>/dev/null || true
codesign --force --sign "$IDENT" --entitlements /tmp/swingcheck_ent.plist --generate-entitlement-der "$APP" >/dev/null 2>&1
codesign -v --strict "$APP" || { echo "✗ Signing failed"; exit 1; }

echo "▸ Installing to iPhone…"
xcrun devicectl device install app --device "$DEV" "$APP" 2>&1 | grep -E "App installed|error" \
  || { echo "✗ Install failed — is the iPhone connected/unlocked?"; exit 1; }
echo "✓ Done — Swing Check updated on your phone."

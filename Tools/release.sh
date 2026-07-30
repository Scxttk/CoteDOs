#!/bin/sh
# Builds a shipping CoteDOs.app: Release archive, Developer ID export,
# notarization, staple, and a zip in build/release/ ready to attach to a
# GitHub release. Run it from anywhere; it works on the repo root.
#
# One-time setup on a new Mac:
#   * a "Developer ID Application" identity in the keychain
#       security find-identity -v -p codesigning     # must list it
#   * notarytool credentials under the profile name below
#       xcrun notarytool store-credentials cotedos-notary \
#         --apple-id scott_koehler@web.de --team-id 3DZ9T8SGX5
set -e

cd "$(dirname "$0")/.."

PROFILE="cotedos-notary"
OUT="build/release"
ARCHIVE="$OUT/CoteDOs.xcarchive"
APP="$OUT/CoteDOs.app"
ZIP="$OUT/CoteDOs.zip"

rm -rf "$OUT"
mkdir -p "$OUT"

# MarketingShots is skipped, not gated in code: it renders the README images,
# which takes ~25 s, mounts real windows and needs a system wallpaper. Same
# skip as .github/workflows/build.yml.
xcodebuild test -project CoteDOs.xcodeproj -scheme CoteDOs \
  -destination 'platform=macOS' \
  -skip-testing:CoteDOsTests/MarketingShots \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO

xcodebuild archive -project CoteDOs.xcodeproj -scheme CoteDOs \
  -configuration Release -archivePath "$ARCHIVE"

# method=developer-id in ExportOptions.plist: the export re-signs, and that is
# the step that settles the entitlements of the artifact people download.
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$OUT"

# Notarization rejects get-task-allow, and an "Apple Development" signature
# carries it whatever the configuration says. This has been wrong before, so
# check the artifact rather than trusting the build settings.
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - | grep -q "get-task-allow"; then
  echo "get-task-allow is in the exported app — not submitting." >&2
  echo "Release CODE_SIGN_IDENTITY must be Developer ID Application." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"

# ditto, not zip: it keeps the bundle's symlinks intact. A plain zip mangles
# them and notarization rejects the result.
ditto -c -k --keepParent "$APP" "$ZIP"

# --wait exits 0 on a rejection too, so read the status out of the log. The
# submission id in there is what `xcrun notarytool log <id>` wants when Apple
# says Invalid and won't say why in the summary.
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait | tee "$OUT/notary.log"
if ! grep -q "status: Accepted" "$OUT/notary.log"; then
  echo "Notarization did not come back Accepted — see $OUT/notary.log." >&2
  exit 1
fi

# The ticket is stapled into the app, so the zip has to be rebuilt around it.
# Without this every first launch phones Apple, and fails offline.
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# The only check that speaks for a machine that has never seen this app:
# expect "accepted" with "source=Notarized Developer ID".
spctl -a -vvv -t install "$APP"

echo
echo "Ready to attach: $ZIP"
echo "Install it locally with:"
echo "  osascript -e 'quit app \"CoteDOs\"'; rm -rf /Applications/CoteDOs.app"
echo "  ditto $APP /Applications/CoteDOs.app && open /Applications/CoteDOs.app"

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
#
# Don't pipe this into anything. Every check here exits non-zero on failure and
# a pipeline reports the *last* command's status, so `release.sh | tail` turns a
# refusal to ship into a clean success.
set -e

cd "$(dirname "$0")/.."

PROFILE="cotedos-notary"
OUT="build/release"
ARCHIVE="$OUT/CoteDOs.xcarchive"
APP="$OUT/CoteDOs.app"
ZIP="$OUT/CoteDOs.zip"
LOCK="build/.release-lock"

# One run at a time. Two of them share $OUT, and the damage is not a clobbered
# file — it is that the first run reads the second run's notarization log as its
# own verdict, and stops one step short of shipping a build Apple had already
# accepted. mkdir is the atomic test-and-set every shell has.
mkdir -p build
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "Another release run holds $LOCK." >&2
  echo "Wait for it to finish, or remove that directory if it died." >&2
  exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

rm -rf "$OUT"
mkdir -p "$OUT"

# MarketingShots is skipped, not gated in code: it renders the README images,
# which takes ~25 s, mounts real windows and needs a system wallpaper. Same
# skip as .github/workflows/build.yml.
xcodebuild test -project CoteDOs.xcodeproj -scheme CoteDOs \
  -destination 'platform=macOS' \
  -skip-testing:CoteDOsTests/MarketingShots \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=NO

# The Developer ID identity is specified here rather than in the project. Baked
# into the Release config it collides with automatic signing ("conflicting
# provisioning settings") and every ordinary Release build fails — including the
# one you make to try a change locally. Shipping is this script's job, so the
# shipping identity is this script's argument.
xcodebuild archive -project CoteDOs.xcodeproj -scheme CoteDOs \
  -configuration Release -archivePath "$ARCHIVE" \
  CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual

# method=developer-id in ExportOptions.plist: the export re-signs, and that is
# the step that settles the entitlements of the artifact people download.
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$OUT"

# Notarization rejects get-task-allow, and an "Apple Development" signature
# carries it whatever the configuration says. This has been wrong before, so
# check the artifact rather than trusting the build settings.
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - | grep -q "get-task-allow"; then
  echo "get-task-allow is in the exported app — not submitting." >&2
  echo "The archive step must sign with Developer ID Application." >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"

# ditto, not zip: it keeps the bundle's symlinks intact. A plain zip mangles
# them and notarization rejects the result.
ditto -c -k --keepParent "$APP" "$ZIP"

# --wait exits 0 on a rejection too, so the printed status is the only verdict
# there is. Read it from what *this* run received rather than from the log file
# afterwards: the file is shared, and a concurrent run's "In Progress" once got
# read back here as this run's answer. The log is still written, because the
# submission id in it is what `xcrun notarytool log <id>` wants when Apple says
# Invalid and won't say why in the summary.
NOTARY=$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait 2>&1 | tee "$OUT/notary.log")
case "$NOTARY" in
  *"status: Accepted"*) ;;
  *)
    echo "Notarization did not come back Accepted — see $OUT/notary.log." >&2
    exit 1
    ;;
esac

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

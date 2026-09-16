#!/bin/bash
# Builds RightClickNinja.app into ./dist, signs it, and (for release) notarizes it.
#
# Signing:
#   Picks up a "Developer ID Application" certificate from the login keychain.
#   Override with RCN_SIGN_IDENTITY="Developer ID Application: Name (TEAMID)".
#   With no such certificate the build falls back to ad-hoc signing, which only
#   runs on this machine (Gatekeeper blocks it everywhere else).
#
# Notarizing:
#   Needs notarytool credentials stored once:
#     xcrun notarytool store-credentials blueshot-notary \
#       --apple-id johnnyoutlawllc@gmail.com --team-id 2J69KHU242 \
#       --password <app-specific-password>
#   Override the profile name with RCN_NOTARY_PROFILE (defaults to blueshot-notary).
#   Set RCN_SKIP_NOTARIZE=1 to sign but not notarize.
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
APP="$ROOT/dist/RightClickNinja.app"
CONFIG="${1:-release}"
NOTARY_PROFILE="${RCN_NOTARY_PROFILE:-blueshot-notary}"
ZIP="$ROOT/../web/public/downloads/RightClickNinja-Mac.zip"
PKG="$ROOT/dist/RightClickNinja.pkg"
PKG_DEST="$ROOT/../web/public/downloads/RightClickNinja-Mac.pkg"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")"
EXIFTOOL_VERSION="${RCN_EXIFTOOL_VERSION:-13.59}"

echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/RightClickNinja"

echo "==> ExifTool"
VENDOR="$ROOT/vendor/Image-ExifTool-$EXIFTOOL_VERSION"
if [ ! -x "$VENDOR/exiftool" ]; then
  mkdir -p "$ROOT/vendor"
  TARBALL="$ROOT/vendor/Image-ExifTool-$EXIFTOOL_VERSION.tar.gz"
  if [ ! -f "$TARBALL" ]; then
    echo "    Downloading Image-ExifTool $EXIFTOOL_VERSION"
    if ! curl -fsSL "https://exiftool.org/Image-ExifTool-${EXIFTOOL_VERSION}.tar.gz" -o "$TARBALL"; then
      curl -fsSL "https://downloads.sourceforge.net/project/exiftool/Image-ExifTool-${EXIFTOOL_VERSION}.tar.gz" -o "$TARBALL"
    fi
  fi
  tar -xzf "$TARBALL" -C "$ROOT/vendor"
fi

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/exiftool"
cp "$BIN" "$APP/Contents/MacOS/RightClickNinja"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
rsync -a --delete "$VENDOR/exiftool" "$VENDOR/lib" "$VENDOR/README" "$VENDOR/LICENSE" \
  "$APP/Contents/Resources/exiftool/" 2>/dev/null || {
  cp "$VENDOR/exiftool" "$APP/Contents/Resources/exiftool/exiftool"
  cp -R "$VENDOR/lib" "$APP/Contents/Resources/exiftool/lib"
}
chmod +x "$APP/Contents/Resources/exiftool/exiftool"

echo "==> Icon"
ICONSET="$ROOT/.build/AppIcon.iconset"
rm -rf "$ICONSET"
if swift "$ROOT/Tools/makeicon.swift" "$ICONSET" >/dev/null 2>&1; then
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || echo "   (icns conversion skipped)"
else
  echo "   (icon generation skipped)"
fi

xattr -cr "$APP" || true

IDENTITY="${RCN_SIGN_IDENTITY:-${BLUESHOT_SIGN_IDENTITY:-}}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)".*/\1/')" || true
fi

NOTARIZED=0
if [ "$CONFIG" != "release" ]; then
  echo "==> Signing (ad-hoc debug build)"
  codesign --force --sign - "$APP"
elif [ -n "$IDENTITY" ]; then
  echo "==> Signing ($IDENTITY)"
  codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" "$APP/Contents/MacOS/RightClickNinja"
  # ExifTool is a perl tree; sign the launcher script's container by signing the app.
  codesign --force --options runtime --timestamp \
    --sign "$IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"

  if [ "${RCN_SKIP_NOTARIZE:-0}" = "1" ]; then
    echo "==> Notarizing (skipped: RCN_SKIP_NOTARIZE=1)"
  else
    echo "==> Notarizing (profile: $NOTARY_PROFILE) — this takes a few minutes"
    SUBMIT="$ROOT/.build/RightClickNinja-notarize.zip"
    rm -f "$SUBMIT"
    ditto -c -k --keepParent "$APP" "$SUBMIT"
    if ! xcrun notarytool submit "$SUBMIT" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 45m; then
      echo
      echo "Notarization failed. If the profile is missing, create it once with:"
      echo "  xcrun notarytool store-credentials $NOTARY_PROFILE \\"
      echo "    --apple-id johnnyoutlawllc@gmail.com --team-id 2J69KHU242 --password <app-specific-password>"
      exit 1
    fi
    rm -f "$SUBMIT"
    echo "==> Stapling"
    xcrun stapler staple "$APP"
    NOTARIZED=1
  fi
else
  echo "==> Signing (ad-hoc — no Developer ID Application certificate found)"
  codesign --force --sign - "$APP"
fi

echo "==> Verifying Gatekeeper policy"
spctl --assess --type execute --verbose=4 "$APP" || echo "   (Gatekeeper would block this build)"

echo "==> Zip for the website"
mkdir -p "$(dirname "$ZIP")"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Building installer package"
PKG_IDENTITY="${RCN_PKG_SIGN_IDENTITY:-${BLUESHOT_PKG_SIGN_IDENTITY:-}}"
if [ -z "$PKG_IDENTITY" ]; then
  PKG_IDENTITY="$(security find-identity -v -p basic 2>/dev/null \
    | grep 'Developer ID Installer' | head -1 | sed -E 's/.*"(.*)".*/\1/')" || true
fi

PKGROOT="$ROOT/.build/pkgroot"
rm -rf "$PKGROOT"
mkdir -p "$PKGROOT/Applications"
cp -R "$APP" "$PKGROOT/Applications/Right Click Ninja.app"

COMPONENT_PLIST="$ROOT/.build/pkg-component.plist"
pkgbuild --analyze --root "$PKGROOT" "$COMPONENT_PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT_PLIST"

rm -f "$PKG"
PKG_ARGS=(--root "$PKGROOT" --component-plist "$COMPONENT_PLIST"
  --identifier com.johnnyoutlaw.rightclickninja.pkg --version "$VERSION")
PKG_NOTARIZED=0
if [ "$CONFIG" = "release" ] && [ -n "$PKG_IDENTITY" ]; then
  echo "    Signing ($PKG_IDENTITY)"
  PKG_ARGS+=(--sign "$PKG_IDENTITY")
  pkgbuild "${PKG_ARGS[@]}" "$PKG"

  if [ "${RCN_SKIP_NOTARIZE:-0}" = "1" ]; then
    echo "    Notarizing (skipped: RCN_SKIP_NOTARIZE=1)"
  else
    echo "    Notarizing (profile: $NOTARY_PROFILE) — this takes a few minutes"
    if ! xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 45m; then
      echo "Package notarization failed."
      exit 1
    fi
    echo "    Stapling"
    xcrun stapler staple "$PKG"
    PKG_NOTARIZED=1
  fi
else
  echo "    Building unsigned"
  pkgbuild "${PKG_ARGS[@]}" "$PKG"
fi

mkdir -p "$(dirname "$PKG_DEST")"
cp -f "$PKG" "$PKG_DEST"

echo
echo "Built: $APP"
echo "Zip:   $ZIP"
echo "Pkg:   $PKG"
if [ "$NOTARIZED" = "1" ]; then
  echo "App signed and notarized — opens with a double-click on any Mac."
elif [ -n "$IDENTITY" ] && [ "$CONFIG" = "release" ]; then
  echo "App signed but NOT notarized — Gatekeeper will still warn on other Macs."
else
  echo "App ad-hoc signed — this build is for this machine."
fi
if [ "$PKG_NOTARIZED" = "1" ]; then
  echo "Pkg signed and notarized — installs with a double-click on any Mac."
fi
echo "Run it with:  open \"$APP\""

#!/bin/zsh
# Packs the Release build into a disk image: Dotfolio.app next to a link to
# /Applications, so installing is a drag. No third-party tools (hdiutil).
#
#   scripts/make-dmg.sh 2.4.2
#   → build/Dotfolio-2.4.2.dmg
#
# Build the Release app first (CLAUDE.md → Releases, step 6). The image is
# not signed or notarized yet: that needs a Developer ID certificate.
set -euo pipefail

version=${1:?usage: scripts/make-dmg.sh <version>}
root=${0:A:h:h}
app="$root/build/release/Build/Products/Release/Dotfolio.app"
stage="$root/build/dmg-stage"
dmg="$root/build/Dotfolio-$version.dmg"

[[ -d $app ]] || { print -u2 "No Release build at $app"; exit 1; }
built=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
[[ $built == $version ]] || { print -u2 "The Release build is $built, not $version"; exit 1; }

rm -rf "$stage" "$dmg"
mkdir -p "$stage"
ditto "$app" "$stage/Dotfolio.app"
ln -s /Applications "$stage/Applications"

# macOS 27 calls hdiutil deprecated (in favor of `diskutil image`) but it
# still works everywhere; drop that warning and verify's "checksum … is
# VALID" line, keep real errors.
quiet() { "$@" > /dev/null 2> >(grep -v -e "is deprecated" -e "is VALID" >&2) }

quiet hdiutil create -volname "Dotfolio $version" -srcfolder "$stage" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$dmg"
rm -rf "$stage"

quiet hdiutil verify "$dmg"
print "$dmg"

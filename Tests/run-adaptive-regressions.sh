#!/bin/sh
# Geometry checks run on the Mac without loading the device-only Parsec SDK.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/openparsec-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
	"$ROOT/OpenParsec/AdaptiveGeometry.swift" \
	"$ROOT/Tests/AdaptiveRegressionTests.swift" -o "$WORK/regressions"
"$WORK/regressions"
/usr/bin/plutil -lint "$ROOT/OpenParsec/Info.plist" "$ROOT/OpenParsec.xcodeproj/project.pbxproj"

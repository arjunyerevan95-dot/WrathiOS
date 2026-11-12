#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ART="$ROOT/Artifacts/input-integration"
mkdir -p "$ART"
# Preserve UI screenshots even when a behavioral assertion fails.
trap 'xcrun xcresulttool export attachments --path "$ART/InputTests.xcresult" --output-path "$ART/screenshots" 2>/dev/null || true' EXIT
python3 scripts/materialize_sdl_ios_patches.py
cmake -S Derived/SDL2-ios -B Derived/deps-build/iphonesimulator/SDL2 \
 -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
 -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" -DCMAKE_OSX_DEPLOYMENT_TARGET=16.3 \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$ROOT/Derived/deps/iphonesimulator" \
 -DCMAKE_INSTALL_LIBDIR=lib -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF -DSDL_TESTS=OFF \
 -DSDL_INSTALL_TESTS=OFF -DSDL2_DISABLE_SDL2MAIN=ON -DSDL_WERROR=OFF
cmake --build Derived/deps-build/iphonesimulator/SDL2 --target install --parallel 3
xcodegen generate --spec project-input-harness.yml
DEVICE="$(xcrun simctl list devices available -j | python3 -c 'import sys,json;d=json.load(sys.stdin);print(next(v["udid"] for k,vs in d["devices"].items() if "iOS" in k for v in vs if v.get("isAvailable") and "iPhone" in v["name"]))')"
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool NO
xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b
xcodebuild -project WrathInputHarness.xcodeproj -scheme WrathInputHarness \
 -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath DerivedData/InputHarness \
 -resultBundlePath "$ART/InputTests.xcresult" -parallel-testing-enabled NO \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 90 -maximum-test-execution-time-allowance 120 \
 ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$ART/xcodebuild.log"
CONTAINER="$(xcrun simctl get_app_container "$DEVICE" com.arjukstudios.wrath.inputharness data)"
cp "$CONTAINER"/Documents/harness-*.json "$ART/"
python3 - "$ART" <<'PY'
from pathlib import Path
import json,sys
p=Path(sys.argv[1])
assert json.loads((p/'harness-manual.json').read_text())['typed']=='Wrath14'
assert json.loads((p/'harness-profile.json').read_text())['typed']=='Profile14'
assert json.loads((p/'harness-manual.json').read_text())['accepts']>0
game=json.loads((p/'harness-game.json').read_text())
assert game['gameplay'] is True
assert game['fireDown']>0 and game['fireUp']>0 and game['jumpDown']>0 and game['look']>0, game
print('Real UIKit/SDL keyboard visibility, manual/profile text delivery and sustained gameplay control tests passed')
PY
xcrun xcresulttool export attachments --path "$ART/InputTests.xcresult" --output-path "$ART/screenshots" || true

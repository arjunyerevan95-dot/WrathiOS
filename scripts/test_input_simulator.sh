#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ART="$ROOT/Artifacts/input-integration"
mkdir -p "$ART"
# Preserve UI screenshots even when a behavioral assertion fails.
collect_evidence() {
 xcrun xcresulttool export attachments --path "$ART/InputTests.xcresult" --output-path "$ART/screenshots" 2>/dev/null || true
 if [[ -n "${DEVICE:-}" ]]; then
  local container
  container="$(xcrun simctl get_app_container "$DEVICE" com.arjukstudios.wrath.inputharness data 2>/dev/null)" || return 0
  cp "$container"/Documents/*.json "$ART/" 2>/dev/null || true
 fi
}
cleanup() {
 local status=$?
 collect_evidence
 if [[ -n "${DEVICE:-}" ]]; then
  xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1 || true
  xcrun simctl delete "$DEVICE" >/dev/null 2>&1 || true
 fi
 return "$status"
}
trap cleanup EXIT
python3 scripts/materialize_sdl_ios_patches.py
cmake -S Derived/SDL2-ios -B Derived/deps-build/iphonesimulator/SDL2 \
 -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
 -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" -DCMAKE_OSX_DEPLOYMENT_TARGET=16.3 \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$ROOT/Derived/deps/iphonesimulator" \
 -DCMAKE_INSTALL_LIBDIR=lib -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF -DSDL_TESTS=OFF \
 -DSDL_INSTALL_TESTS=OFF -DSDL2_DISABLE_SDL2MAIN=ON -DSDL_WERROR=OFF
cmake --build Derived/deps-build/iphonesimulator/SDL2 --target install --parallel 3
xcodegen generate --spec project-input-harness.yml
# XCTest needs a fresh UI session, not an arbitrary preinstalled simulator.
# Match both the installed device type and the active Xcode SDK. A newer
# global runtime may boot while XCTest's older accessibility agent stalls.
xcrun simctl list -j > "$ART/simulators.json"
SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"
printf '%s\n' "$SDK_VERSION" > "$ART/simulator-sdk-version.txt"
XCODE_DEVELOPER_PATH="${DEVELOPER_DIR:-$(xcode-select -p)}"
if [[ "$XCODE_DEVELOPER_PATH" == *.app ]]; then XCODE_DEVELOPER_PATH+="/Contents/Developer"; fi
printf '%s\n' "$XCODE_DEVELOPER_PATH" > "$ART/xcode-developer-path.txt"
read -r RUNTIME DEVICE_TYPE < <(python3 - "$ART/simulators.json" "$SDK_VERSION" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
sdk=tuple(map(int,sys.argv[2].split('.')[:2]))
r=sorted((x for x in j['runtimes'] if x.get('isAvailable') and x['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-') and tuple(map(int,x['version'].split('.')[:2]))==sdk),key=lambda x:tuple(map(int,x['version'].split('.'))))
assert r, f'An available iOS runtime matching Simulator SDK {sys.argv[2]} is required'
pairs=[(runtime['identifier'],device['deviceTypeIdentifier'])
       for runtime in r for device in j['devices'].get(runtime['identifier'],[])
       if device.get('isAvailable') and device.get('deviceTypeIdentifier')
       and device.get('name','').startswith('iPhone')]
assert pairs, 'An available compatible iPhone/runtime pair is required'
print(*pairs[-1])
PY
)
DEVICE="$(xcrun simctl create "WRATH-input-tests-$$" "$DEVICE_TYPE" "$RUNTIME")"
echo "Input UI simulator: $DEVICE ($DEVICE_TYPE, $RUNTIME)"
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool NO
xcrun simctl boot "$DEVICE"
# Bring up Simulator's UI session before XCTest waits for accessibility.
open -a "$XCODE_DEVELOPER_PATH/Applications/Simulator.app" --args -CurrentDeviceUDID "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
FILTER=()
if [[ "${WRATH_UI_SCOPE:-all}" == editor ]]; then
 FILTER=(-only-testing:InputUITests/InputUITests/testEditableLayoutPersistsAndResets -only-testing:InputUITests/InputUITests/testEditorPinchPreservesPositionAndPersistsSize -only-testing:InputUITests/InputUITests/testGameplayClusterSurvivesRepeatedFrames)
fi
xcodebuild -project WrathInputHarness.xcodeproj -scheme WrathInputHarness \
 -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath DerivedData/InputHarness \
 -resultBundlePath "$ART/InputTests.xcresult" -parallel-testing-enabled NO \
 -test-timeouts-enabled YES -default-test-execution-time-allowance 90 -maximum-test-execution-time-allowance 180 \
 "${FILTER[@]}" ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO test 2>&1 | tee "$ART/xcodebuild.log"
CONTAINER="$(xcrun simctl get_app_container "$DEVICE" com.arjukstudios.wrath.inputharness data)"
cp "$CONTAINER"/Documents/harness-*.json "$ART/"
python3 - "$ART" <<'PY'
from pathlib import Path
import json,sys,os
p=Path(sys.argv[1])
if os.environ.get('WRATH_UI_SCOPE','all')!='editor':
 assert json.loads((p/'harness-manual.json').read_text())['typed']=='wrath'
 assert json.loads((p/'harness-profile.json').read_text())['typed']=='profile'
 assert json.loads((p/'harness-manual.json').read_text())['accepts']>0
game=json.loads((p/'harness-game.json').read_text())
assert game['gameplay'] is True
assert game['fireDown']>0 and game['fireUp']>0 and game['jumpDown']>0 and game['look']>0 and game['fireLook']>0, game
print('Actual selected UIKit/SDL scope passed:',os.environ.get('WRATH_UI_SCOPE','all'))
PY
xcrun xcresulttool export attachments --path "$ART/InputTests.xcresult" --output-path "$ART/screenshots" || true

#!/bin/bash
# Real simulator GPU probe for only the new ES3 FBO/depth/shadow primitives.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="${WRATH_GLES3_PROBE_OUT:-$ROOT/Artifacts/gles3-probe}"
mkdir -p "$OUT"
APP="$OUT/WrathGLES3Probe.app"
mkdir -p "$APP"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
[[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || { echo "Unsupported simulator host arch $ARCH" >&2; exit 1; }
xcrun --sdk iphonesimulator clang -fobjc-arc -fmodules -Wall -Wextra -Werror -Wno-deprecated-declarations -target "$ARCH-apple-ios17.0-simulator" -isysroot "$SDK" "$ROOT/Tests/GLES3/main.m" -framework UIKit -framework Foundation -framework QuartzCore -framework OpenGLES -o "$APP/WrathGLES3Probe"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.arjukstudios.wrathios.gles3probe</string>
<key>CFBundleExecutable</key><string>WrathGLES3Probe</string><key>CFBundleName</key><string>WrathGLES3Probe</string>
<key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string><key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UILaunchScreen</key><dict/><key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
xcrun simctl list -j > "$OUT/simulators.json"
read -r RUNTIME DEVICE < <(python3 - "$OUT/simulators.json" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
r=sorted((x for x in j['runtimes'] if x.get('isAvailable') and x['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')),key=lambda x:tuple(map(int,x['version'].split('.'))))
assert r, 'An available iOS runtime is required'
# Use a known compatible existing runtime/type pairing, not the last globally
# advertised device type (which can require a newer runtime than installed).
pairs=[(runtime['identifier'],device['deviceTypeIdentifier'])
       for runtime in r for device in j['devices'].get(runtime['identifier'],[])
       if device.get('isAvailable') and device.get('deviceTypeIdentifier')
       and device.get('name','').startswith('iPhone')]
assert pairs, 'An available compatible iPhone/runtime pair is required'
print(*pairs[-1])
PY
)
UDID=$(xcrun simctl create "WRATH-GLES3-probe-$$" "$DEVICE" "$RUNTIME")
cleanup(){ xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true; }
trap cleanup EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.arjukstudios.wrathios.gles3probe
CONTAINER=$(xcrun simctl get_app_container "$UDID" com.arjukstudios.wrathios.gles3probe data)
python3 - "$CONTAINER/Documents/gles3-probe.json" "$OUT/gles3-probe.json" <<'PY'
import json,pathlib,sys,time,shutil
p=pathlib.Path(sys.argv[1]); deadline=time.monotonic()+120
while not p.exists() and time.monotonic()<deadline: time.sleep(.5)
assert p.exists(), 'GPU probe produced no receipt within120s'
shutil.copyfile(p,sys.argv[2]);j=json.loads(p.read_text());print(json.dumps(j,indent=2))
assert j.get('passed') is True, j.get('error','probe failed')
required={'rgba8-depth16-complete','rgba8-depth24stencil8-complete','depth-only-essl100-draw','raw-depth-r-manual-pcf-pixel','nonzero-uikit-restore-resize-present'}
assert required<=set(j.get('checks',[])), 'Missing actual GPU checks'
PY

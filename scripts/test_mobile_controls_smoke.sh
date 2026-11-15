#!/usr/bin/env bash
# One bounded native smoke for the changed settings, Artifact UI and AA copy.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
OUT="$ROOT/Artifacts/mobile-controls"
mkdir -p "$OUT"
python3 scripts/materialize_sdl_ios_patches.py
python3 scripts/prepare_mobile_smoke_shader.py
cmake -S Derived/SDL2-ios -B Derived/deps-build/iphonesimulator/SDL2 \
 -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator \
 -DCMAKE_OSX_ARCHITECTURES="$(uname -m)" -DCMAKE_OSX_DEPLOYMENT_TARGET=16.3 \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$ROOT/Derived/deps/iphonesimulator" \
 -DCMAKE_INSTALL_LIBDIR=lib -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF -DSDL_TESTS=OFF \
 -DSDL_INSTALL_TESTS=OFF -DSDL2_DISABLE_SDL2MAIN=ON -DSDL_WERROR=OFF > "$OUT/sdl-configure.log" 2>&1
cmake --build Derived/deps-build/iphonesimulator/SDL2 --target install --parallel 3 > "$OUT/sdl-build.log" 2>&1
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
ARCH=$(uname -m)
APP="$OUT/WrathMobileSmoke.app"
mkdir -p "$APP"
xcrun --sdk iphonesimulator clang++ -std=c++20 -fobjc-arc -fmodules -Wall -Wextra -Werror \
 -Wno-deprecated-declarations -DSDL_MAIN_HANDLED=1 -DWRATH_IOS_GLES3=1 -DWRATH_IOS_GATE5C=1 \
 -target "$ARCH-apple-ios16.3-simulator" -isysroot "$SDK" \
 -I Gate5C -I "$OUT" -I Derived/deps/iphonesimulator/include/SDL2 \
 Tests/InputHarness/MobileSmoke.mm Gate5C/WrathSemanticMenuBridge.mm \
 -L Derived/deps/iphonesimulator/lib -lSDL2 -liconv \
 -framework UIKit -framework Foundation -framework QuartzCore -framework OpenGLES \
 -framework CoreGraphics -framework CoreMotion -framework CoreVideo -framework CoreHaptics \
 -framework AVFoundation -framework AudioToolbox -framework CoreAudio -framework GameController \
 -framework Metal -framework CoreBluetooth -framework Security -framework SystemConfiguration \
 -o "$APP/WrathMobileSmoke" 2>&1 | tee "$OUT/native-compile.log"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.arjukstudios.wrath.mobilesmoke</string>
<key>CFBundleExecutable</key><string>WrathMobileSmoke</string><key>CFBundleName</key><string>WrathMobileSmoke</string>
<key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>16.3</string><key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UILaunchScreen</key><dict/><key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
xcrun simctl list -j > "$OUT/simulators.json"
SDK_VERSION=$(xcrun --sdk iphonesimulator --show-sdk-version)
read -r RUNTIME DEVICE_TYPE < <(python3 - "$OUT/simulators.json" "$SDK_VERSION" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]));sdk=tuple(map(int,sys.argv[2].split('.')[:2]))
r=[x for x in j['runtimes'] if x.get('isAvailable') and x['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-') and tuple(map(int,x['version'].split('.')[:2]))==sdk]
pairs=[(runtime['identifier'],d['deviceTypeIdentifier']) for runtime in r for d in j['devices'].get(runtime['identifier'],[]) if d.get('isAvailable') and d.get('deviceTypeIdentifier') and d.get('name','').startswith('iPhone')]
assert pairs,'An available iPhone/runtime pairing matching the active SDK is required'
print(*pairs[-1])
PY
)
DEVICE=$(xcrun simctl create "WRATH-mobile-smoke-$$" "$DEVICE_TYPE" "$RUNTIME")
cleanup(){ xcrun simctl shutdown "$DEVICE" >/dev/null 2>&1 || true; xcrun simctl delete "$DEVICE" >/dev/null 2>&1 || true; }
trap cleanup EXIT
xcrun simctl boot "$DEVICE"
xcrun simctl bootstatus "$DEVICE" -b
xcrun simctl install "$DEVICE" "$APP"
xcrun simctl launch "$DEVICE" com.arjukstudios.wrath.mobilesmoke
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" com.arjukstudios.wrath.mobilesmoke data)
python3 - "$CONTAINER/Documents/mobile-smoke.json" "$OUT/mobile-smoke.json" <<'PY'
import json,pathlib,shutil,sys,time
p=pathlib.Path(sys.argv[1]);deadline=time.monotonic()+60
while not p.exists() and time.monotonic()<deadline:time.sleep(.25)
assert p.exists(),'Changed-path native smoke produced no receipt within 60s'
shutil.copyfile(p,sys.argv[2]);j=json.loads(p.read_text());print(json.dumps(j,indent=2))
assert j['passed'] is True,j.get('error','Native smoke failed')
assert len(j['checks'])==6,j
PY

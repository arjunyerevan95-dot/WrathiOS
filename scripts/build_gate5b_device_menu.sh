#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData/Gate5B"
ARTIFACT_DIR="$ROOT_DIR/Artifacts/gate5b-menu-input"
LOG="$ARTIFACT_DIR/xcodebuild.log"
PROJECT="$ROOT_DIR/WrathiOSGate5B.xcodeproj"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug-iphoneos/WrathiOSGate5B.app"
BINARY="$APP_BUNDLE/WrathiOSGate5B"
PACKAGE_ROOT="$ROOT_DIR/Derived/gate5b-package"
IPA="$ARTIFACT_DIR/WrathiOSGate5B-v7-unsigned.ipa"

rm -rf "$ARTIFACT_DIR" "$DERIVED_DATA" "$PROJECT" "$PACKAGE_ROOT"
mkdir -p "$ARTIFACT_DIR"

for file in \
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libSDL2.a" \
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libfreetype.a" \
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libogg.a" \
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libvorbis.a" \
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libvorbisfile.a"; do
    [[ -f "$file" ]] || { echo "error: missing Gate 5B link input: $file" >&2; exit 2; }
done
command -v xcodegen >/dev/null 2>&1 || { echo "error: xcodegen is required" >&2; exit 2; }

cd "$ROOT_DIR"
python3 scripts/test_gate5b_input_contract.py | tee "$ARTIFACT_DIR/input-source-contract.txt"
bash scripts/test_gate5b_input_math.sh
WRATH_ENGINE_BUILD_FLAVOR=gate5b python3 scripts/build_gate2_engine_archive.py
xcodegen generate --spec project-gate5b.yml

set -o pipefail
xcodebuild \
    -project WrathiOSGate5B.xcodeproj \
    -scheme WrathiOSGate5B \
    -configuration Debug \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tee "$LOG"

[[ -d "$APP_BUNDLE" && -f "$BINARY" ]] || { echo "error: Gate 5B app was not produced" >&2; exit 1; }

file "$BINARY" | tee "$ARTIFACT_DIR/file.txt"
lipo -info "$BINARY" | tee "$ARTIFACT_DIR/architecture.txt"
otool -L "$BINARY" | tee "$ARTIFACT_DIR/dynamic-dependencies.txt"
nm -gU "$BINARY" > "$ARTIFACT_DIR/global-symbols.txt"
plutil -p "$APP_BUNDLE/Info.plist" > "$ARTIFACT_DIR/Info.plist.txt"
strings -a "$BINARY" > "$ARTIFACT_DIR/strings.txt"
find "$APP_BUNDLE" -print | sed "s#^$APP_BUNDLE#.#" | sort > "$ARTIFACT_DIR/bundle-inventory.txt"

grep -q 'arm64' "$ARTIFACT_DIR/architecture.txt"
required_symbols=(
    '_Host_Main$'
    '_SDL_Init$'
    '_SDL_GL_CreateContext$'
    '_WrathIOSRuntimeStage$'
    '_WrathIOSRuntimeAbort$'
    '_WrathIOSInputSetMode$'
    '_WrathIOSInputFingerDown$'
    '_WrathIOSInputFingerMotion$'
    '_WrathIOSInputFingerUp$'
    '_WrathIOSInputConsumeMenuPosition$'
    '_WrathIOSInputConsumeMenuButtonPhase$'
    '_WrathIOSInputConsumeGameplayLook$'
    '_WrathIOSInputReset$'
    '_WrathIOSInputEnteredForeground$'
    '_OBJC_CLASS_\$_WrathRuntime$'
    '_OBJC_CLASS_\$_WrathDataImporter$'
    '_OBJC_CLASS_\$_WrathImportViewController$'
)
for symbol in "${required_symbols[@]}"; do
    grep -Eq "$symbol" "$ARTIFACT_DIR/global-symbols.txt" || {
        echo "error: Gate 5B binary is missing symbol pattern: $symbol" >&2
        exit 1
    }
done

required_markers=(
    'Gate 5B mode-specific input bridge selected'
    'Gate 5B input mode changed'
    'Gate 5B menu touch began'
    'Gate 5B menu absolute position updated'
    'Gate 5B menu tap emitted'
    'Gate 5B gameplay aim touch began'
    'Gate 5B gameplay swipe movement emitted'
    'Gate 5B gameplay aim state reset'
    'Gate 5B gyro started'
    'Gate 5B gyro delta applied'
    'Gate 5B gyro suspended'
    'Gate 5B gyro baseline reset'
    'Gate 5B input state reset'
    'Gate 5B runtime returned to foreground'
    'Gate 5B foreground first frame'
    'absolute logical cursor positioned under the primary finger'
    'origin established in the rightmost 65 percent; camera unchanged'
    'no click or fire event emitted'
    'Launch WRATH'
    'Choose WRATH Folder'
    'Remove Imported Data'
    'Main menu reached'
    'Audio initialization passed'
    '<private-path>'
)
for marker in "${required_markers[@]}"; do
    grep -Fq "$marker" "$ARTIFACT_DIR/strings.txt" || {
        echo "error: Gate 5B binary is missing contract marker: $marker" >&2
        exit 1
    }
done
printf '%s\n' "${required_markers[@]}" > "$ARTIFACT_DIR/input-runtime-contract.txt"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Info.plist")"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Info.plist")"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Info.plist")"
launch_storyboard="$(/usr/libexec/PlistBuddy -c 'Print :UILaunchStoryboardName' "$APP_BUNDLE/Info.plist")"
[[ "$bundle_id" == 'com.arjukstudios.wrathios.gate3' ]] || {
    echo "error: unexpected Gate 5B bundle identifier: $bundle_id" >&2; exit 1;
}
[[ "$short_version" == '0.0.7' && "$build_version" == '7' ]] || {
    echo "error: unexpected Gate 5B version: $short_version ($build_version)" >&2; exit 1;
}
[[ "$launch_storyboard" == 'LaunchScreen' ]] || { echo "error: adaptive launch storyboard missing" >&2; exit 1; }
find "$APP_BUNDLE" -type d -name 'LaunchScreen.storyboardc' -print -quit | grep -q .

python3 - "$APP_BUNDLE/Info.plist" <<'PY'
import plistlib
from pathlib import Path
import sys
with Path(sys.argv[1]).open("rb") as handle:
    info = plistlib.load(handle)
expected = ["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
for key in ("UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~ipad"):
    if info.get(key) != expected:
        raise SystemExit(f"error: {key} is not landscape-only: {info.get(key)!r}")
print("validated landscape-only declarations")
PY

python3 - "$ARTIFACT_DIR/dynamic-dependencies.txt" <<'PY' | tee "$ARTIFACT_DIR/dynamic-dependency-audit.txt"
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()[1:]
paths = [line.strip().split()[0] for line in lines if line.strip()]
invalid = [path for path in paths if not path.startswith(("/System/Library/Frameworks/", "/usr/lib/"))]
if invalid:
    raise SystemExit("error: non-system dynamic dependencies: " + ", ".join(invalid))
print(f"validated {len(paths)} system dynamic dependencies")
PY
grep -q '/System/Library/Frameworks/CoreMotion.framework/CoreMotion' \
    "$ARTIFACT_DIR/dynamic-dependencies.txt" || {
    echo "error: Core Motion is not linked into the Gate 5B binary" >&2
    exit 1
}

python3 - "$APP_BUNDLE" <<'PY' | tee "$ARTIFACT_DIR/commercial-data-audit.txt"
from pathlib import Path
import sys
root = Path(sys.argv[1])
archive_suffixes = {".pak", ".pk3", ".pk4", ".wad", ".gro"}
sentinels = {"progs.dat", "csprogs.dat", "menu.dat"}
bad = []
for path in root.rglob("*"):
    relative = path.relative_to(root)
    lowered_parts = {part.lower() for part in relative.parts}
    if path.is_file() and (path.suffix.lower() in archive_suffixes or path.name.lower() in sentinels or
                           "kp1" in lowered_parts or "gamedata" in lowered_parts):
        bad.append(relative.as_posix())
if bad:
    raise SystemExit("error: commercial-data paths bundled: " + ", ".join(bad))
print("commercial WRATH files: absent")
PY

if codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
    echo "error: Gate 5B CI bundle unexpectedly has a valid signature" >&2
    exit 1
fi
echo 'unsigned CI bundle confirmed' > "$ARTIFACT_DIR/signing-status.txt"

mkdir -p "$PACKAGE_ROOT/Payload"
ditto "$APP_BUNDLE" "$PACKAGE_ROOT/Payload/WrathiOSGate5B.app"
rm -rf "$PACKAGE_ROOT/Payload/WrathiOSGate5B.app/_CodeSignature"
rm -f "$PACKAGE_ROOT/Payload/WrathiOSGate5B.app/embedded.mobileprovision"
(
    cd "$PACKAGE_ROOT"
    /usr/bin/zip -qry "$IPA" Payload
)

[[ -s "$IPA" ]] || { echo "error: Gate 5B IPA was not produced" >&2; exit 1; }
/usr/bin/unzip -tq "$IPA" > "$ARTIFACT_DIR/ipa-validation.txt"
/usr/bin/unzip -Z1 "$IPA" | sort > "$ARTIFACT_DIR/ipa-inventory.txt"
if grep -Eq '(^|/)(_CodeSignature/|embedded\.mobileprovision$)' "$ARTIFACT_DIR/ipa-inventory.txt"; then
    echo "error: Gate 5B IPA contains signing material" >&2
    exit 1
fi

shasum -a 256 "$BINARY" "$IPA" > "$ARTIFACT_DIR/SHA256SUMS.txt"
cp "$BINARY" "$ARTIFACT_DIR/WrathiOSGate5B-arm64"
cp docs/GATE5B_DEVICE_CHECKLIST.md "$ARTIFACT_DIR/device-test-checklist.md"
cp docs/GATE5B_MENU_INPUT.md "$ARTIFACT_DIR/input-architecture.md"
cp Artifacts/gate5b-input-math/summary.txt "$ARTIFACT_DIR/input-math-tests.txt"
cp Artifacts/engine-patches/report.json "$ARTIFACT_DIR/engine-patch-report.json"
cp Artifacts/gate5b-engine-archive/report.json "$ARTIFACT_DIR/engine-archive-report.json"

ipa_size="$(stat -f '%z' "$IPA")"
ipa_sha256="$(shasum -a 256 "$IPA" | awk '{print $1}')"
cat > "$ARTIFACT_DIR/summary.md" <<EOF
# Gate 5B direct-touch, swipe-look, and gyro device build

- Target: arm64-apple-ios16.3
- Bundle identifier: $bundle_id (unchanged)
- Version: $short_version ($build_version)
- IPA: $(basename "$IPA")
- IPA size: $ipa_size bytes
- IPA SHA-256: $ipa_sha256
- Menu input: direct absolute touch with frame-separated click
- Gameplay input: right-side relative swipe-look at the authentic mouse-look boundary
- Gyroscope: Core Motion device rotation, landscape mapped and additive to swipe
- SDL synthetic touch-to-mouse path: disabled
- Mode-transition and lifecycle reset contracts: embedded
- WRATH engine, SDL2, audio, Host_Main, and Gate 4 importer: retained
- Dynamic dependencies: system-only
- Adaptive launch storyboard: packaged
- Orientation: landscape-only
- Commercial WRATH data: absent
- Provisioning profile and code signature: absent
- ZIP integrity: passed
- Gameplay movement and firing controls: absent
- Physical menu, swipe, gyro, and lifecycle result: not established by CI
EOF

cat "$ARTIFACT_DIR/summary.md"
cat "$ARTIFACT_DIR/SHA256SUMS.txt"
echo "Gate 5B device build and packaging validation passed"

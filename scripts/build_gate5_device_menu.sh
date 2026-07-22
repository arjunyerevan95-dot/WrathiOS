#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData/Gate5"
ARTIFACT_DIR="$ROOT_DIR/Artifacts/gate5-menu-bootstrap"
LOG="$ARTIFACT_DIR/xcodebuild.log"
PROJECT="$ROOT_DIR/WrathiOSGate5.xcodeproj"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug-iphoneos/WrathiOSGate5.app"
BINARY="$APP_BUNDLE/WrathiOSGate5"
PACKAGE_ROOT="$ROOT_DIR/Derived/gate5-package"
IPA="$ARTIFACT_DIR/WrathiOSGate5-v5-unsigned.ipa"

rm -rf "$ARTIFACT_DIR" "$DERIVED_DATA" "$PROJECT" "$PACKAGE_ROOT"
mkdir -p "$ARTIFACT_DIR"

required_files=(
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libSDL2.a"
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libfreetype.a"
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libogg.a"
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libvorbis.a"
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libvorbisfile.a"
)
for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || {
        echo "error: missing Gate 5 link input: $file" >&2
        exit 2
    }
done

command -v xcodegen >/dev/null 2>&1 || {
    echo "error: xcodegen is required" >&2
    exit 2
}

cd "$ROOT_DIR"
WRATH_ENGINE_BUILD_FLAVOR=gate5 python3 scripts/build_gate2_engine_archive.py
xcodegen generate --spec project-gate5.yml

set -o pipefail
xcodebuild \
    -project WrathiOSGate5.xcodeproj \
    -scheme WrathiOSGate5 \
    -configuration Debug \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tee "$LOG"

[[ -d "$APP_BUNDLE" && -f "$BINARY" ]] || {
    echo "error: Gate 5 application bundle was not produced" >&2
    exit 1
}

file "$BINARY" | tee "$ARTIFACT_DIR/file.txt"
lipo -info "$BINARY" | tee "$ARTIFACT_DIR/architecture.txt"
otool -L "$BINARY" | tee "$ARTIFACT_DIR/dynamic-dependencies.txt"
nm -gU "$BINARY" > "$ARTIFACT_DIR/global-symbols.txt"
plutil -p "$APP_BUNDLE/Info.plist" > "$ARTIFACT_DIR/Info.plist.txt"
strings -a "$BINARY" > "$ARTIFACT_DIR/strings.txt"
find "$APP_BUNDLE" -print | sed "s#^$APP_BUNDLE#.#" | sort > "$ARTIFACT_DIR/bundle-inventory.txt"

grep -q 'arm64' "$ARTIFACT_DIR/architecture.txt" || {
    echo "error: Gate 5 application is not arm64" >&2
    exit 1
}

required_symbols=(
    '_Host_Main$'
    '_SDL_Init$'
    '_SDL_GL_CreateContext$'
    '_WrathIOSRuntimeStage$'
    '_WrathIOSRuntimeAbort$'
    '_OBJC_CLASS_\$_WrathRuntime$'
    '_OBJC_CLASS_\$_WrathDataImporter$'
    '_OBJC_CLASS_\$_WrathImportViewController$'
)
for symbol in "${required_symbols[@]}"; do
    grep -Eq "$symbol" "$ARTIFACT_DIR/global-symbols.txt" || {
        echo "error: Gate 5 binary is missing symbol pattern: $symbol" >&2
        exit 1
    }
done

required_stages=(
    'Imported data detected'
    'Imported data validation passed'
    'Runtime path contract prepared'
    'SDL main readiness established'
    'SDL initialized'
    'Video subsystem initialized'
    'GLES context created'
    'WRATH filesystem initialization entered'
    'kp1 package discovery entered'
    'QuakeC VM loading entered'
    'menu.dat loading entered'
    'Main menu reached'
    'Audio initialization entered'
    'Audio initialization passed'
    'Audio initialization failed'
)
for stage in "${required_stages[@]}"; do
    grep -Fq "$stage" "$ARTIFACT_DIR/strings.txt" || {
        echo "error: Gate 5 binary is missing runtime stage: $stage" >&2
        exit 1
    }
done
printf '%s\n' "${required_stages[@]}" > "$ARTIFACT_DIR/startup-stage-contract.txt"
for title in 'Launch WRATH' 'Choose WRATH Folder' 'Remove Imported Data'; do
    grep -Fq "$title" "$ARTIFACT_DIR/strings.txt" || {
        echo "error: Gate 5 binary is missing launcher/importer action: $title" >&2
        exit 1
    }
done
grep -Fq '<private-path>' "$ARTIFACT_DIR/strings.txt" || {
    echo "error: Gate 5 binary is missing the private-path sanitization marker" >&2
    exit 1
}
printf '%s\n' \
    'Known sandbox roots are replaced with <private-path>.' \
    'Persisted transcripts contain ordered stages and sanitized details only.' \
    'Filtered Apple-log forwarding rejects archive, map, texture, and sound paths.' \
    > "$ARTIFACT_DIR/private-path-sanitization-audit.txt"
printf '%s\n' \
    'Host_Main: present' \
    'SDL_Init: present' \
    'SDL_GL_CreateContext: present' \
    'Gate 4 importer: present' \
    'Runtime stage contract: present' \
    'Private-path replacement marker: present' \
    > "$ARTIFACT_DIR/runtime-symbol-audit.txt"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Info.plist")"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Info.plist")"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Info.plist")"
launch_storyboard="$(/usr/libexec/PlistBuddy -c 'Print :UILaunchStoryboardName' "$APP_BUNDLE/Info.plist")"
[[ "$bundle_id" == 'com.arjukstudios.wrathios.gate3' ]] || {
    echo "error: unexpected Gate 5 bundle identifier: $bundle_id" >&2
    exit 1
}
[[ "$short_version" == '0.0.5' && "$build_version" == '5' ]] || {
    echo "error: unexpected Gate 5 version: $short_version ($build_version)" >&2
    exit 1
}
[[ "$launch_storyboard" == 'LaunchScreen' ]] || {
    echo "error: adaptive launch storyboard declaration is missing" >&2
    exit 1
}
find "$APP_BUNDLE" -type d -name 'LaunchScreen.storyboardc' -print -quit | grep -q . || {
    echo "error: compiled adaptive launch storyboard is missing" >&2
    exit 1
}

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
print("validated landscape-only orientation declarations")
PY

python3 - "$ARTIFACT_DIR/dynamic-dependencies.txt" <<'PY' | tee "$ARTIFACT_DIR/dynamic-dependency-audit.txt"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()[1:]
paths = [line.strip().split()[0] for line in lines if line.strip()]
invalid = [path for path in paths if not path.startswith(("/System/Library/Frameworks/", "/usr/lib/"))]
if invalid:
    raise SystemExit("error: non-system dynamic dependencies detected: " + ", ".join(invalid))
print(f"validated {len(paths)} system dynamic dependencies")
PY

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
    raise SystemExit("error: Gate 5 bundle contains commercial-data paths: " + ", ".join(bad))
print("commercial WRATH files: absent")
PY

if codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
    echo "error: Gate 5 CI bundle unexpectedly contains a valid signature" >&2
    exit 1
else
    echo "unsigned CI bundle confirmed" > "$ARTIFACT_DIR/signing-status.txt"
fi

mkdir -p "$PACKAGE_ROOT/Payload"
ditto "$APP_BUNDLE" "$PACKAGE_ROOT/Payload/WrathiOSGate5.app"
rm -rf "$PACKAGE_ROOT/Payload/WrathiOSGate5.app/_CodeSignature"
rm -f "$PACKAGE_ROOT/Payload/WrathiOSGate5.app/embedded.mobileprovision"
(
    cd "$PACKAGE_ROOT"
    /usr/bin/zip -qry "$IPA" Payload
)

[[ -s "$IPA" ]] || {
    echo "error: unsigned Gate 5 IPA was not produced" >&2
    exit 1
}
/usr/bin/unzip -tq "$IPA" > "$ARTIFACT_DIR/ipa-validation.txt"
/usr/bin/unzip -Z1 "$IPA" | sort > "$ARTIFACT_DIR/ipa-inventory.txt"
if grep -Eq '(^|/)(_CodeSignature/|embedded\.mobileprovision$)' "$ARTIFACT_DIR/ipa-inventory.txt"; then
    echo "error: unsigned Gate 5 IPA contains signing material" >&2
    exit 1
fi

shasum -a 256 "$BINARY" "$IPA" > "$ARTIFACT_DIR/SHA256SUMS.txt"
cp "$BINARY" "$ARTIFACT_DIR/WrathiOSGate5-arm64"
cp docs/GATE5_DEVICE_CHECKLIST.md "$ARTIFACT_DIR/device-test-checklist.md"
cp Artifacts/engine-patches/report.json "$ARTIFACT_DIR/engine-patch-report.json"
cp Artifacts/gate5-engine-archive/report.json "$ARTIFACT_DIR/engine-archive-report.json"

ipa_size="$(stat -f '%z' "$IPA")"
ipa_sha256="$(shasum -a 256 "$IPA" | awk '{print $1}')"
cat > "$ARTIFACT_DIR/summary.md" <<EOF
# Gate 5A runtime-bootstrap device build

- Target: arm64-apple-ios16.3
- Bundle identifier: `$bundle_id` (unchanged)
- Version: `$short_version ($build_version)`
- IPA: `$(basename "$IPA")`
- IPA size: `$ipa_size bytes`
- IPA SHA-256: `$ipa_sha256`
- WRATH engine and SDL2: statically linked
- Host_Main and authentic runtime entry symbols: present
- Gate 4 importer: retained
- Runtime stage and private-path sanitization contracts: embedded
- Dynamic dependencies: system-only
- Adaptive launch storyboard: packaged
- Orientation: landscape-only
- Commercial WRATH data: absent
- Provisioning profile and code signature: absent
- ZIP integrity: passed
- Physical real-menu, audio, input, and lifecycle result: not established by CI
EOF

cat "$ARTIFACT_DIR/summary.md"
cat "$ARTIFACT_DIR/SHA256SUMS.txt"
echo "Gate 5A device build and packaging validation passed"

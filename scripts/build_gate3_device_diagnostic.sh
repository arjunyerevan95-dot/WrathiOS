#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData/Gate3"
ARTIFACT_DIR="$ROOT_DIR/Artifacts/gate3-device-diagnostic"
LOG="$ARTIFACT_DIR/xcodebuild.log"
PROJECT="$ROOT_DIR/WrathiOSGate3.xcodeproj"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug-iphoneos/WrathiOSGate3.app"
BINARY="$APP_BUNDLE/WrathiOSGate3"
PACKAGE_ROOT="$ROOT_DIR/Derived/gate3-package"
IPA="$ARTIFACT_DIR/WrathiOSGate3-unsigned.ipa"

mkdir -p "$ARTIFACT_DIR"
rm -rf "$DERIVED_DATA" "$PROJECT" "$PACKAGE_ROOT"

required_files=(
    "$ROOT_DIR/Derived/gate2-engine-archive/libwrath-engine.a"
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libSDL2.a"
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libfreetype.a"
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libogg.a"
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libvorbis.a"
    "$ROOT_DIR/Derived/deps/iphoneos/lib/libvorbisfile.a"
)

for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || {
        echo "error: missing Gate 3 link input: $file" >&2
        exit 2
    }
done

command -v xcodegen >/dev/null 2>&1 || {
    echo "error: xcodegen is required" >&2
    exit 2
}

cd "$ROOT_DIR"
xcodegen generate --spec project-gate3.yml

set -o pipefail
xcodebuild \
    -project WrathiOSGate3.xcodeproj \
    -scheme WrathiOSGate3 \
    -configuration Debug \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tee "$LOG"

[[ -d "$APP_BUNDLE" && -f "$BINARY" ]] || {
    echo "error: Gate 3 application bundle was not produced" >&2
    exit 1
}

file "$BINARY" | tee "$ARTIFACT_DIR/file.txt"
lipo -info "$BINARY" | tee "$ARTIFACT_DIR/architecture.txt"
otool -L "$BINARY" | tee "$ARTIFACT_DIR/dynamic-dependencies.txt"
nm -gU "$BINARY" > "$ARTIFACT_DIR/global-symbols.txt"
plutil -p "$APP_BUNDLE/Info.plist" > "$ARTIFACT_DIR/Info.plist.txt"
strings -a "$BINARY" > "$ARTIFACT_DIR/strings.txt"

architecture="$(cat "$ARTIFACT_DIR/architecture.txt")"
[[ "$architecture" == *"arm64"* ]] || {
    echo "error: Gate 3 application is not arm64" >&2
    exit 1
}

for symbol in '_Host_Main$' '_SDL_GL_CreateContext$' '_buildstring$' 'WrathGraphicsDiagnosticStart'; do
    grep -Eq "$symbol" "$ARTIFACT_DIR/global-symbols.txt" || {
        echo "error: linked application is missing required symbol pattern: $symbol" >&2
        exit 1
    }
done

grep -q 'Gate 3 graphics diagnostic' "$ARTIFACT_DIR/strings.txt" || {
    echo "error: Gate 3 diagnostic marker was not embedded in the executable" >&2
    exit 1
}

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Info.plist")"
[[ "$bundle_id" == "com.arjukstudios.wrathios.gate3" ]] || {
    echo "error: unexpected Gate 3 bundle identifier: $bundle_id" >&2
    exit 1
}

python3 - "$ARTIFACT_DIR/dynamic-dependencies.txt" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()[1:]
paths = [line.strip().split()[0] for line in lines if line.strip()]
allowed_prefixes = ("/System/Library/Frameworks/", "/usr/lib/")
invalid = [path for path in paths if not path.startswith(allowed_prefixes)]
if invalid:
    print("error: non-system dynamic dependencies detected:", file=sys.stderr)
    for path in invalid:
        print(f"  {path}", file=sys.stderr)
    raise SystemExit(1)
print(f"validated {len(paths)} system dynamic dependencies")
PY

if find "$APP_BUNDLE" -type f \( -iname '*.pak' -o -iname '*.pk3' -o -iname '*.pk4' -o -iname '*.wad' \) -print -quit | grep -q .; then
    echo "error: Gate 3 bundle unexpectedly contains commercial-style game archives" >&2
    exit 1
fi

if codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
    echo "error: CI diagnostic bundle unexpectedly contains a valid signature" >&2
    exit 1
else
    echo "unsigned CI bundle confirmed" > "$ARTIFACT_DIR/signing-status.txt"
fi

mkdir -p "$PACKAGE_ROOT/Payload"
ditto "$APP_BUNDLE" "$PACKAGE_ROOT/Payload/WrathiOSGate3.app"
rm -rf "$PACKAGE_ROOT/Payload/WrathiOSGate3.app/_CodeSignature"
rm -f "$PACKAGE_ROOT/Payload/WrathiOSGate3.app/embedded.mobileprovision"
(
    cd "$PACKAGE_ROOT"
    /usr/bin/zip -qry "$IPA" Payload
)

[[ -s "$IPA" ]] || {
    echo "error: unsigned Gate 3 IPA was not produced" >&2
    exit 1
}

/usr/bin/unzip -tq "$IPA" > "$ARTIFACT_DIR/ipa-validation.txt"
shasum -a 256 "$BINARY" "$IPA" > "$ARTIFACT_DIR/SHA256SUMS.txt"
cp "$BINARY" "$ARTIFACT_DIR/WrathiOSGate3-arm64"

cat > "$ARTIFACT_DIR/device-test-checklist.md" <<'EOF'
# Gate 3 physical-device checklist

1. Sign and install `WrathiOSGate3-unsigned.ipa` through the tester's own sideloading workflow.
2. Launch in landscape and verify a large RGB triangle renders behind the diagnostic panel.
3. Confirm the panel reports an active SDL2/OpenGL ES context and non-zero drawable dimensions.
4. Confirm the safe-area values are visible and the panel is not clipped by the Dynamic Island or home indicator.
5. Background the app, wait at least three seconds, and return.
6. Confirm rendering resumes and `Foreground recoveries` increases to at least 1.
7. Force-quit and relaunch twice. Confirm `Launch count` increases and context creation succeeds each time.
8. Capture a screenshot after the foreground-recovery test.

Do not add or import WRATH game data for this gate. Runtime engine startup remains disabled.
EOF

cat > "$ARTIFACT_DIR/summary.md" <<EOF
# Gate 3 device graphics diagnostic build

- Target: arm64-apple-ios16.3
- WRATH engine archive: force-loaded, runtime startup disabled
- SDL2: statically linked
- OpenGL ES framework: system-linked
- Diagnostic entry point: present
- Non-system dynamic dependencies: none
- Commercial game data: absent
- Packaging: complete unsigned IPA for external signing

CI proves compilation, linkage, bundle integrity, and the presence of the diagnostic path. Physical-device evidence is still required for context creation, rendering, drawable sizing, safe-area layout, repeated launch, and foreground recovery.
EOF

echo "Gate 3 device diagnostic build and unsigned packaging validation passed"

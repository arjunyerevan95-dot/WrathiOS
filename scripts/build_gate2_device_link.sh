#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData/Gate2"
ARTIFACT_DIR="$ROOT_DIR/Artifacts/gate2-device-link"
LOG="$ARTIFACT_DIR/xcodebuild.log"
PROJECT="$ROOT_DIR/WrathiOSGate2.xcodeproj"
BINARY="$DERIVED_DATA/Build/Products/Debug-iphoneos/WrathiOSGate2.app/WrathiOSGate2"

mkdir -p "$ARTIFACT_DIR"
rm -rf "$DERIVED_DATA" "$PROJECT"

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
        echo "error: missing Gate 2 link input: $file" >&2
        exit 2
    }
done

command -v xcodegen >/dev/null 2>&1 || {
    echo "error: xcodegen is required" >&2
    exit 2
}

cd "$ROOT_DIR"
xcodegen generate --spec project-gate2.yml

set -o pipefail
xcodebuild \
    -project WrathiOSGate2.xcodeproj \
    -scheme WrathiOSGate2 \
    -configuration Debug \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tee "$LOG"

[[ -f "$BINARY" ]] || {
    echo "error: Gate 2 application binary was not produced" >&2
    exit 1
}

file "$BINARY" | tee "$ARTIFACT_DIR/file.txt"
lipo -info "$BINARY" | tee "$ARTIFACT_DIR/architecture.txt"
otool -L "$BINARY" | tee "$ARTIFACT_DIR/dynamic-dependencies.txt"
nm -gU "$BINARY" > "$ARTIFACT_DIR/global-symbols.txt"

architecture="$(cat "$ARTIFACT_DIR/architecture.txt")"
[[ "$architecture" == *"arm64"* ]] || {
    echo "error: Gate 2 application is not arm64" >&2
    exit 1
}

grep -q ' _buildstring$' "$ARTIFACT_DIR/global-symbols.txt" || {
    echo "error: linked application does not expose the WRATH buildstring symbol" >&2
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

cp "$BINARY" "$ARTIFACT_DIR/WrathiOSGate2-arm64"

cat > "$ARTIFACT_DIR/summary.md" <<EOF
# Gate 2 device static-link result

- Target: arm64-apple-ios16.3
- WRATH engine archive: force-loaded
- SDL2 archive: force-loaded
- FreeType: statically linked
- Ogg/Vorbis: statically linked
- Engine build diagnostic symbol: present
- Non-system dynamic dependencies: none
- Runtime engine startup: intentionally disabled

This establishes the compile and static-link portion of Gate 2. Physical-device launch evidence is still required before the gate can be declared fully passed.
EOF

echo "Gate 2 device static-link validation passed"

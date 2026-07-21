#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/Vendor/freetype"
BUILD_DIR="$ROOT_DIR/Derived/deps-build/iphoneos/freetype"
PREFIX="$ROOT_DIR/Derived/deps/iphoneos"
ARTIFACT_DIR="$ROOT_DIR/Artifacts/gate2-freetype"
LOG="$ARTIFACT_DIR/build.log"

mkdir -p "$ARTIFACT_DIR" "$PREFIX"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

exec > >(tee "$LOG") 2>&1

[[ -d "$SOURCE/.git" ]] || {
    echo "error: missing pinned FreeType checkout" >&2
    exit 2
}

cmake -S "$SOURCE" -B "$BUILD_DIR" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.3 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DFT_DISABLE_ZLIB=TRUE \
    -DFT_DISABLE_BZIP2=TRUE \
    -DFT_DISABLE_PNG=TRUE \
    -DFT_DISABLE_HARFBUZZ=TRUE \
    -DFT_DISABLE_BROTLI=TRUE \
    -DSKIP_INSTALL_HEADERS=OFF \
    -DSKIP_INSTALL_LIBRARIES=OFF

cmake --build "$BUILD_DIR" --config Release --target install --parallel 3

archive="$PREFIX/lib/libfreetype.a"
header="$PREFIX/include/freetype2/ft2build.h"

[[ -f "$archive" ]] || {
    echo "error: missing expected FreeType archive: $archive" >&2
    exit 1
}
[[ -f "$header" ]] || {
    echo "error: missing expected FreeType header: $header" >&2
    exit 1
}

info="$(lipo -info "$archive")"
echo "$info"
[[ "$info" == *"arm64"* ]] || {
    echo "error: FreeType archive is not arm64" >&2
    exit 1
}

member_count="$(xcrun ar -t "$archive" | wc -l | tr -d ' ')"
cp "$archive" "$ARTIFACT_DIR/"

cat > "$ARTIFACT_DIR/inventory.md" <<EOF
# Gate 2 FreeType inventory

- Version: 2.14.0
- Target: arm64-apple-ios16.3
- Archive: \`Derived/deps/iphoneos/lib/libfreetype.a\`
- Members: $member_count
- Architecture: \`$info\`
- External optional dependencies: disabled
EOF

echo "Gate 2 FreeType built and verified"

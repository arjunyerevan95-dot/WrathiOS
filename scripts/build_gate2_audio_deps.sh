#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OGG_SOURCE="$ROOT_DIR/Vendor/ogg"
VORBIS_SOURCE="$ROOT_DIR/Vendor/vorbis"
BUILD_ROOT="$ROOT_DIR/Derived/deps-build/iphoneos"
PREFIX="$ROOT_DIR/Derived/deps/iphoneos"
ARTIFACT_DIR="$ROOT_DIR/Artifacts/gate2-audio-deps"
LOG="$ARTIFACT_DIR/build.log"

mkdir -p "$ARTIFACT_DIR"
rm -rf "$BUILD_ROOT" "$PREFIX"
mkdir -p "$BUILD_ROOT" "$PREFIX"

exec > >(tee "$LOG") 2>&1

for source in "$OGG_SOURCE" "$VORBIS_SOURCE"; do
    [[ -d "$source/.git" ]] || {
        echo "error: missing pinned dependency checkout: $source" >&2
        exit 2
    }
done

common_cmake=(
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
    -DCMAKE_SYSTEM_NAME=iOS
    -DCMAKE_OSX_SYSROOT=iphoneos
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.3
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
    -DCMAKE_INSTALL_LIBDIR=lib
    -DBUILD_SHARED_LIBS=OFF
)

cmake -S "$OGG_SOURCE" -B "$BUILD_ROOT/ogg" \
    "${common_cmake[@]}" \
    -DBUILD_TESTING=OFF \
    -DINSTALL_DOCS=OFF \
    -DINSTALL_PKG_CONFIG_MODULE=OFF
cmake --build "$BUILD_ROOT/ogg" --config Release --target install --parallel 3

cmake -S "$VORBIS_SOURCE" -B "$BUILD_ROOT/vorbis" \
    "${common_cmake[@]}" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DOGG_LIBRARY="$PREFIX/lib/libogg.a" \
    -DOGG_INCLUDE_DIR="$PREFIX/include" \
    -DINSTALL_CMAKE_PACKAGE_MODULE=OFF
cmake --build "$BUILD_ROOT/vorbis" --config Release --target install --parallel 3

required_archives=(
    "$PREFIX/lib/libogg.a"
    "$PREFIX/lib/libvorbis.a"
    "$PREFIX/lib/libvorbisfile.a"
)

{
    echo "# Gate 2 audio dependency inventory"
    echo
    echo "- Target: arm64-apple-ios16.3"
    echo "- Prefix: ${PREFIX#$ROOT_DIR/}"
    echo
    echo "## Archives"
    echo
} > "$ARTIFACT_DIR/inventory.md"

for archive in "${required_archives[@]}"; do
    [[ -f "$archive" ]] || {
        echo "error: missing expected archive: $archive" >&2
        exit 1
    }
    info="$(lipo -info "$archive")"
    echo "$info"
    [[ "$info" == *"arm64"* ]] || {
        echo "error: archive is not arm64: $archive" >&2
        exit 1
    }
    member_count="$(xcrun ar -t "$archive" | wc -l | tr -d ' ')"
    printf -- '- `%s`: %s members; `%s`\n' "${archive#$ROOT_DIR/}" "$member_count" "$info" >> "$ARTIFACT_DIR/inventory.md"
done

cp "$PREFIX/lib/libogg.a" "$ARTIFACT_DIR/"
cp "$PREFIX/lib/libvorbis.a" "$ARTIFACT_DIR/"
cp "$PREFIX/lib/libvorbisfile.a" "$ARTIFACT_DIR/"

echo "Gate 2 audio dependencies built and verified"

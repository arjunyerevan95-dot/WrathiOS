#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDL_VENDOR="$ROOT_DIR/Vendor/SDL2"
SDL_SOURCE="$ROOT_DIR/Derived/SDL2-ios"
BUILD_DIR="$ROOT_DIR/Derived/deps-build/iphoneos/SDL2"
PREFIX="$ROOT_DIR/Derived/deps/iphoneos"
ARTIFACT_DIR="$ROOT_DIR/Artifacts/gate2-sdl"
LOG="$ARTIFACT_DIR/build.log"

mkdir -p "$ARTIFACT_DIR" "$PREFIX"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

exec > >(tee "$LOG") 2>&1

[[ -d "$SDL_VENDOR/.git" ]] || {
    echo "error: missing pinned SDL2 checkout" >&2
    exit 2
}

python3 "$ROOT_DIR/scripts/materialize_sdl_ios_patches.py"
[[ -f "$SDL_SOURCE/src/video/uikit/SDL_uikitwindow.m" ]] || {
    echo "error: SDL2 iOS derived source was not materialized" >&2
    exit 2
}

cmake -S "$SDL_SOURCE" -B "$BUILD_DIR" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.3 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DSDL_SHARED=OFF \
    -DSDL_STATIC=ON \
    -DSDL_TEST=OFF \
    -DSDL_TESTS=OFF \
    -DSDL_INSTALL_TESTS=OFF \
    -DSDL2_DISABLE_SDL2MAIN=ON \
    -DSDL_WERROR=OFF

cmake --build "$BUILD_DIR" --config Release --target install --parallel 3

archive="$PREFIX/lib/libSDL2.a"
[[ -f "$archive" ]] || {
    echo "error: missing expected SDL archive: $archive" >&2
    exit 1
}

info="$(lipo -info "$archive")"
echo "$info"
[[ "$info" == *"arm64"* ]] || {
    echo "error: SDL archive is not arm64" >&2
    exit 1
}

member_count="$(xcrun ar -t "$archive" | wc -l | tr -d ' ')"
cp "$archive" "$ARTIFACT_DIR/"
shasum -a 256 \
    "$SDL_SOURCE/src/video/uikit/SDL_uikitwindow.m" \
    > "$ARTIFACT_DIR/patched-source-SHA256.txt"

git -C "$SDL_VENDOR" diff --quiet --exit-code || {
    echo "error: pinned SDL2 vendor checkout was modified" >&2
    exit 1
}

cat > "$ARTIFACT_DIR/inventory.md" <<EOF
# Gate 2 SDL inventory

- Target: arm64-apple-ios16.3
- Archive: \`Derived/deps/iphoneos/lib/libSDL2.a\`
- Members: $member_count
- Architecture: \`$info\`
- SDL2main: disabled; UIKit owns the application entry point
- Source: pinned SDL2 2.32.10 materialized under \`Derived/SDL2-ios\`
- iOS adaptation: attach the SDL UIWindow to the active UIWindowScene and derive initial geometry from that scene-backed window
- Vendor checkout: verified clean after patch materialization
EOF

echo "Gate 2 SDL built and verified"

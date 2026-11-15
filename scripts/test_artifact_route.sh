#!/usr/bin/env bash
# Keep the fixture on the same SDL2 pin as the app, never SDL3 compatibility.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
OUT="$ROOT/Artifacts/artifact-route"
PREFIX="$ROOT/Derived/deps/host-artifact-route"
mkdir -p "$OUT"
cmake -S Vendor/SDL2 -B Derived/deps-build/host-artifact-route \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" \
 -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF -DSDL_TESTS=OFF -DSDL_INSTALL_TESTS=OFF \
 -DSDL_VIDEO=OFF -DSDL_AUDIO=OFF -DSDL_RENDER=OFF -DSDL_HAPTIC=OFF -DSDL_SENSOR=OFF -DSDL_POWER=OFF \
 > "$OUT/sdl-configure.log" 2>&1
cmake --build Derived/deps-build/host-artifact-route --target install --parallel 3 > "$OUT/sdl-build.log" 2>&1
export WRATH_TEST_SDL_FLAGS="$("$PREFIX/bin/sdl2-config" --cflags --libs) -Wl,-rpath,$PREFIX/lib"
python3 Tests/Gate5C/test_controller_route.py 2>&1 | tee "$OUT/routing-test.log"

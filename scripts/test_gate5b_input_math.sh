#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/Artifacts/gate5b-input-math"
TEST_BINARY="$OUTPUT_DIR/WrathIOSInputMathTests"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

clang++ \
    -std=c++17 \
    -Wall \
    -Wextra \
    -Werror \
    -I"$ROOT_DIR/Gate5" \
    "$ROOT_DIR/Gate5/WrathIOSInputMath.cpp" \
    "$ROOT_DIR/Tests/WrathIOSInputMathTests.cpp" \
    -o "$TEST_BINARY"

"$TEST_BINARY"
echo "Gate 5B input coordinate and gyro mapping tests: passed" | tee "$OUTPUT_DIR/summary.txt"

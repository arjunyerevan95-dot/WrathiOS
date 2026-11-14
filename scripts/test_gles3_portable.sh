#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p Artifacts/gles3-portable
python3 scripts/materialize_engine_patches.py
python3 Tests/Gate5C/test_gles3_wiring.py
for name in WrathEditorPinchTests WrathReadableDimensionsTests; do
 "${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror -IGate5C "Tests/Gate5C/$name.cpp" -o "Artifacts/gles3-portable/$name"
 "Artifacts/gles3-portable/$name"
done
python3 Tests/Gate5C/test_controller_route.py

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="$ROOT_DIR/Artifacts/gate5c-semantic-tests"
TEST_BINARY="$ARTIFACT_DIR/WrathSemanticMenuModelTests"

rm -rf "$ARTIFACT_DIR"
mkdir -p "$ARTIFACT_DIR"

"${CXX:-c++}" \
    -std=c++20 \
    -Wall -Wextra -Werror \
    -I"$ROOT_DIR/Gate5C" \
    "$ROOT_DIR/Gate5C/WrathSemanticMenuModel.cpp" \
    "$ROOT_DIR/Tests/Gate5C/WrathSemanticMenuModelTests.cpp" \
    -o "$TEST_BINARY"

"$TEST_BINARY" | tee "$ARTIFACT_DIR/results.txt"

"${CXX:-c++}" -std=c++20 -Wall -Wextra -Werror -I"$ROOT_DIR/Gate5C" \
    "$ROOT_DIR/Tests/Gate5C/WrathTouchInputTests.cpp" -o "$ARTIFACT_DIR/WrathTouchInputTests"
"$ARTIFACT_DIR/WrathTouchInputTests" | tee "$ARTIFACT_DIR/native-touch-results.txt"

python3 "$ROOT_DIR/scripts/materialize_gate5c_menu_qc.py"
python3 "$ROOT_DIR/Tests/Gate5C/test_nested_menu_geometry.py"
python3 "$ROOT_DIR/Tests/Gate5C/test_menu_bytecode_contract.py"
test -s "$ROOT_DIR/Gate5C/Resources/wrathios-menu.dat"
actual_sha="$(shasum -a 256 "$ROOT_DIR/Gate5C/Resources/wrathios-menu.dat" | awk '{print $1}')"
expected_sha="f10318db61dc037ead5228b222fa4c0dc7ef8fee5cacc76174b3a62286ab317c"
[[ "$actual_sha" == "$expected_sha" ]] || {
    echo "error: semantic menu bytecode checksum mismatch: $actual_sha" >&2
    exit 1
}

grep -Fq 'wrathios_semantic_entry(chain, master_position, tsize' \
    "$ROOT_DIR/Derived/wrath-qc-gate5c/uielement.qc"
grep -Fq 'wrathios_semantic_end(ui_hover)' \
    "$ROOT_DIR/Derived/wrath-qc-gate5c/menuqc/menu.qc"

cat > "$ARTIFACT_DIR/summary.md" <<EOF
# Gate 5C semantic menu host checks

- Coordinate conversion: passed
- Reverse-order semantic hit testing: passed
- Disabled/invisible rejection: passed
- Miss and source-derived hit slop: passed
- Snapshot replacement: passed
- Position-before-hover-before-click sequencing: passed
- Mode reset/inactive state: passed
- Pinned QC hook materialization: passed
- Derived menu bytecode SHA-256: $actual_sha
- Physical menu touch quality: device-unverified
EOF

cat "$ARTIFACT_DIR/summary.md"

python3 "$ROOT_DIR/scripts/test_gate5c_control_contract.py"

python3 "$ROOT_DIR/Tests/Gate5C/test_controller_route.py"
python3 "$ROOT_DIR/Tests/Gate5C/test_upstream_controller_handlers.py"

"${CXX:-c++}" -std=c++20 -Wall -Wextra -Werror -I"$ROOT_DIR/Gate5C" "$ROOT_DIR/Tests/Gate5C/WrathReadableDimensionsTests.cpp" -o "$ARTIFACT_DIR/WrathReadableDimensionsTests"
"$ARTIFACT_DIR/WrathReadableDimensionsTests" | tee "$ARTIFACT_DIR/readability-results.txt"

python3 "$ROOT_DIR/Tests/Gate5C/test_backend_selection.py"

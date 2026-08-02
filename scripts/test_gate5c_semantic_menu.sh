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

python3 "$ROOT_DIR/scripts/materialize_gate5c_menu_qc.py"
test -s "$ROOT_DIR/Gate5C/Resources/wrathios-menu.dat"
actual_sha="$(shasum -a 256 "$ROOT_DIR/Gate5C/Resources/wrathios-menu.dat" | awk '{print $1}')"
expected_sha="3d848d8988952cff025a167e52574ff0a70c142c8aa9d934d0df9313b045ee2b"
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

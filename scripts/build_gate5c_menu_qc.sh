#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$ROOT/Derived/fteqcc-source"
PIN=f09ac7cccd2d713ddf881d3f1324703082c2cfe4
mkdir -p "$ROOT/Derived" "$ROOT/Artifacts/gate5c-qc-patches"
if [[ ! -d "$COMPILER/.git" ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/fte-team/fteqw.git "$COMPILER"
  git -C "$COMPILER" checkout --detach "$PIN"
fi
[[ "$(git -C "$COMPILER" rev-parse HEAD)" == "$PIN" ]] || { echo 'Unexpected compiler revision' >&2; exit 1; }
PATCH="$ROOT/config/qc/fteqcc-pragma-once.patch"
if git -C "$COMPILER" apply --check "$PATCH"; then
  git -C "$COMPILER" apply "$PATCH"
else
  git -C "$COMPILER" apply --reverse --check "$PATCH"
fi
make -C "$COMPILER/engine/qclib" -j2 qcc
python3 "$ROOT/scripts/materialize_gate5c_menu_qc.py"
(cd "$ROOT/Derived/wrath-qc-gate5c/menuqc" && "$COMPILER/engine/qclib/fteqcc.bin" -Tq1) > "$ROOT/Artifacts/gate5c-qc-patches/compiler-linux.log" 2>&1
cp "$ROOT/Derived/menu.dat" "$ROOT/Gate5C/Resources/wrathios-menu.dat"
sha256sum "$ROOT/Gate5C/Resources/wrathios-menu.dat"

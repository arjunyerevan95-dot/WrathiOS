#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$ROOT_DIR/Artifacts/gate4-data-contract"
CLI="$WORK_DIR/wrath-data-contract"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

clang++ -std=c++20 -Wall -Wextra -Werror \
  "$ROOT_DIR/Gate4/WrathDataContract.cpp" \
  "$ROOT_DIR/Tests/Gate4/WrathDataContractCLI.cpp" \
  -o "$CLI"

python3 - "$WORK_DIR" <<'PY'
from pathlib import Path
import os
import sys
import zipfile

root = Path(sys.argv[1])

valid = root / "valid-install" / "kp1"
valid.mkdir(parents=True)
with zipfile.ZipFile(valid / "pak000.pk3", "w", compression=zipfile.ZIP_DEFLATED) as archive:
    archive.writestr("progs.dat", b"synthetic")
    archive.writestr("csprogs.dat", b"synthetic")
    archive.writestr("menu.dat", b"synthetic")
    archive.writestr("maps/synthetic.bsp", b"synthetic")
    archive.writestr("textures/synthetic.tga", b"synthetic")

loose = root / "loose-kp1"
loose.mkdir()
for name in ("progs.dat", "csprogs.dat", "menu.dat"):
    (loose / name).write_bytes(b"synthetic")
(loose / "maps").mkdir()
(loose / "maps" / "synthetic.bsp").write_bytes(b"synthetic")

missing = root / "missing" / "kp1"
missing.mkdir(parents=True)
with zipfile.ZipFile(missing / "pak000.pk3", "w") as archive:
    archive.writestr("progs.dat", b"synthetic")
    archive.writestr("csprogs.dat", b"synthetic")

unsafe = root / "unsafe" / "kp1"
unsafe.mkdir(parents=True)
with zipfile.ZipFile(unsafe / "pak000.pk3", "w") as archive:
    archive.writestr("../escape", b"synthetic")
    archive.writestr("progs.dat", b"synthetic")
    archive.writestr("csprogs.dat", b"synthetic")
    archive.writestr("menu.dat", b"synthetic")

symlinked = root / "symlinked" / "kp1"
symlinked.mkdir(parents=True)
for name in ("progs.dat", "csprogs.dat", "menu.dat"):
    (symlinked / name).write_bytes(b"synthetic")
os.symlink(symlinked / "progs.dat", symlinked / "alias.dat")
PY

"$CLI" "$WORK_DIR/valid-install" | tee "$WORK_DIR/valid.txt"
grep -q '^compatible=1$' "$WORK_DIR/valid.txt"
grep -q '^packages=1$' "$WORK_DIR/valid.txt"

"$CLI" "$WORK_DIR/loose-kp1" | tee "$WORK_DIR/loose.txt"
grep -q '^compatible=1$' "$WORK_DIR/loose.txt"

if "$CLI" "$WORK_DIR/missing" > "$WORK_DIR/missing.txt"; then
  echo "error: incomplete data unexpectedly passed" >&2
  exit 1
fi
grep -q 'menu.dat' "$WORK_DIR/missing.txt"

if "$CLI" "$WORK_DIR/unsafe" > "$WORK_DIR/unsafe.txt"; then
  echo "error: unsafe PK3 unexpectedly passed" >&2
  exit 1
fi
grep -q 'unsafe path' "$WORK_DIR/unsafe.txt"

if "$CLI" "$WORK_DIR/symlinked" > "$WORK_DIR/symlinked.txt"; then
  echo "error: symlinked data unexpectedly passed" >&2
  exit 1
fi
grep -q 'Symbolic links' "$WORK_DIR/symlinked.txt"

cat > "$WORK_DIR/summary.md" <<'EOF'
# Gate 4 data-contract test evidence

- Valid PK3 layout: passed
- Valid loose layout: passed
- Missing menu.dat: rejected
- Traversal-bearing PK3: rejected
- Symbolic link: rejected
EOF

echo "Gate 4 data-contract tests passed"

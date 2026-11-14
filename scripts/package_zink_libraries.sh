#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$1"
EVIDENCE="$2"
INPUT="$ROOT/Derived/zink-input.ipa"
OUT="$ROOT/Derived/zink-verified"
if [[ ! -d "$OUT" ]]; then
  url="$(python3 -c 'import json;print(json.load(open("scripts/zink-native-inputs.json"))["source_ipa_url"])')"
  curl --fail --location --retry 3 "$url" -o "$INPUT"
  python3 "$ROOT/scripts/zink-extract_inputs.py" "$INPUT" "$OUT"
fi
(cd "$OUT" && shasum -a 256 -c SHA256SUMS)
mkdir -p "$APP/Frameworks" "$EVIDENCE/zink"
for lib in libOSMesa.dylib libMoltenVK.dylib; do
  lipo "$OUT/$lib" -verify_arch arm64
  otool -L "$OUT/$lib" > "$EVIDENCE/zink/$lib.dependencies.txt"
  python3 - "$EVIDENCE/zink/$lib.dependencies.txt" <<'PY'
from pathlib import Path
import sys
lines=Path(sys.argv[1]).read_text().splitlines()[2:]
for line in lines:
    name=line.strip().split(' (',1)[0]
    if name and not name.startswith(('/usr/lib/','/System/Library/Frameworks/')):
        raise SystemExit('Unexpected dependency: '+name)
PY
  cp "$OUT/$lib" "$APP/Frameworks/$lib"
  codesign --force --sign - "$APP/Frameworks/$lib"
  codesign --verify --strict "$APP/Frameworks/$lib"
done
cp "$OUT/SOURCE_NOTICES.txt" "$APP/Zink-NOTICES.txt"
cp "$OUT/provenance.json" "$OUT/SHA256SUMS" "$EVIDENCE/zink/"
shasum -a 256 "$APP/Frameworks/"*.dylib > "$EVIDENCE/zink/packaged-SHA256SUMS"
echo 'Experimental desktop GL >=2.1 only after runtime validation. CPU readback presentation. Not device validated.' > "$EVIDENCE/zink/status.txt"

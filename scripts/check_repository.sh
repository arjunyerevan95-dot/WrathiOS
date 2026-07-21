#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
    README.md
    COPYING
    project.yml
    project-gate3.yml
    App/Info.plist
    App/main.mm
    Platform/WrathEngineBridge.mm
    Platform/WrathGraphicsDiagnostic.h
    Platform/WrathGraphicsDiagnostic.mm
    scripts/upstream.env
    scripts/validate_engine_manifest.py
    scripts/materialize_sdl_ios_patches.py
    scripts/build_gate2_sdl.sh
    scripts/build_gate3_device_diagnostic.sh
    config/engine/source_dispositions.json
    config/engine/ios_upstream_sources.txt
    docs/PORTING_PLAN.md
    docs/ASSET_POLICY.md
    docs/GATE1_SOURCE_INVENTORY.md
    docs/GATE3_GRAPHICS_DIAGNOSTIC.md
)

for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || {
        echo "error: missing required file: $file" >&2
        exit 1
    }
done

if git grep -nE '(^|/)(kp1|GameData)/|\.(pak|pk3|pk4|wad)$' -- ':!docs/*' ':!README.md' ':!.gitignore' >/dev/null 2>&1; then
    echo "error: repository appears to reference a prohibited commercial-data path outside documentation" >&2
    git grep -nE '(^|/)(kp1|GameData)/|\.(pak|pk3|pk4|wad)$' -- ':!docs/*' ':!README.md' ':!.gitignore' || true
    exit 1
fi

python3 - <<'PY'
import plistlib
from pathlib import Path
with Path("App/Info.plist").open("rb") as handle:
    plistlib.load(handle)
print("validated App/Info.plist")
PY

bash -n scripts/build_gate2_sdl.sh
bash -n scripts/build_gate3_device_diagnostic.sh
python3 -m py_compile scripts/materialize_sdl_ios_patches.py
python3 scripts/validate_engine_manifest.py

echo "repository checks passed"

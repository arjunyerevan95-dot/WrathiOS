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
    App/LaunchScreen.storyboard
    App/main.mm
    Platform/WrathEngineBridge.mm
    Platform/WrathGraphicsDiagnostic.h
    Platform/WrathGraphicsDiagnostic.mm
    scripts/upstream.env
    scripts/validate_engine_manifest.py
    scripts/materialize_sdl_ios_patches.py
    scripts/materialize_gate3_platform.py
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
import xml.etree.ElementTree as ET
from pathlib import Path

with Path("App/Info.plist").open("rb") as handle:
    plist = plistlib.load(handle)

expected = {
    "CFBundleDisplayName": "WrathiOS G3 v2",
    "CFBundleShortVersionString": "0.0.2",
    "CFBundleVersion": "2",
    "UILaunchStoryboardName": "LaunchScreen",
}
for key, value in expected.items():
    if plist.get(key) != value:
        raise SystemExit(f"error: {key} must be {value!r}, found {plist.get(key)!r}")

ET.parse("App/LaunchScreen.storyboard")
print("validated versioned App/Info.plist and LaunchScreen.storyboard")
PY

bash -n scripts/build_gate2_sdl.sh
bash -n scripts/build_gate3_device_diagnostic.sh
python3 -m py_compile scripts/materialize_sdl_ios_patches.py scripts/materialize_gate3_platform.py
python3 scripts/materialize_gate3_platform.py

grep -q 'WrathGate3LaunchCountV2' Derived/gate3-platform/WrathGraphicsDiagnostic.mm || {
    echo "error: Gate 3 derived counter namespace was not materialized" >&2
    exit 1
}
grep -q 'Host scene:' Derived/gate3-platform/WrathGraphicsDiagnostic.mm || {
    echo "error: Gate 3 UIKit geometry telemetry was not materialized" >&2
    exit 1
}

python3 scripts/validate_engine_manifest.py

echo "repository checks passed"

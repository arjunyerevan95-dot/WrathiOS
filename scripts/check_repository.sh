#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_files=(
    README.md
    COPYING
    project.yml
    project-gate2.yml
    project-gate3.yml
    project-gate4.yml
    App/Info.plist
    App/Gate4Info.plist
    App/LaunchScreen.storyboard
    App/main.mm
    Platform/WrathEngineBridge.mm
    Platform/WrathGraphicsDiagnostic.h
    Platform/WrathGraphicsDiagnostic.mm
    Gate4/WrathDataContract.hpp
    Gate4/WrathDataContract.cpp
    Gate4/WrathDataImporter.h
    Gate4/WrathDataImporter.mm
    Gate4/WrathImportViewController.h
    Gate4/WrathImportViewController.mm
    Gate4/AppDelegate.h
    Gate4/AppDelegate.mm
    Gate4/main.mm
    Tests/Gate4/WrathDataContractCLI.cpp
    scripts/upstream.env
    scripts/validate_engine_manifest.py
    scripts/materialize_sdl_ios_patches.py
    scripts/materialize_gate3_platform.py
    scripts/build_gate2_sdl.sh
    scripts/build_gate3_device_diagnostic.sh
    scripts/build_gate4_device_importer.sh
    scripts/test_gate4_data_contract.sh
    config/engine/source_dispositions.json
    config/engine/ios_upstream_sources.txt
    docs/PORTING_PLAN.md
    docs/ASSET_POLICY.md
    docs/GATE1_SOURCE_INVENTORY.md
    docs/GATE3_GRAPHICS_DIAGNOSTIC.md
    docs/GATE4_LICENSED_DATA_IMPORT.md
)

for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || {
        echo "error: missing required file: $file" >&2
        exit 1
    }
done

# Reject actual tracked commercial-data paths or archive files. Source and test
# code may name these formats because Gate 4 must validate them.
if git ls-files | grep -Ei '(^|/)(kp1|GameData)(/|$)|\.(pak|pk3|pk4|wad)$' >/dev/null; then
    echo "error: repository contains a tracked commercial-data path or archive" >&2
    git ls-files | grep -Ei '(^|/)(kp1|GameData)(/|$)|\.(pak|pk3|pk4|wad)$' || true
    exit 1
fi

for spec in project.yml project-gate2.yml project-gate3.yml; do
    grep -q 'INFOPLIST_FILE: App/Info.plist' "$spec" || {
        echo "error: $spec does not consume the committed Info.plist" >&2
        exit 1
    }
    if grep -Eq '^[[:space:]]+info:[[:space:]]*$' "$spec"; then
        echo "error: $spec lets XcodeGen overwrite the committed Info.plist" >&2
        exit 1
    fi
done

grep -q 'INFOPLIST_FILE: App/Gate4Info.plist' project-gate4.yml || {
    echo "error: Gate 4 does not consume its committed Info.plist" >&2
    exit 1
}
if grep -Eq '^[[:space:]]+info:[[:space:]]*$' project-gate4.yml; then
    echo "error: Gate 4 lets XcodeGen overwrite its committed Info.plist" >&2
    exit 1
fi

python3 - <<'PY'
import plistlib
import xml.etree.ElementTree as ET
from pathlib import Path

with Path("App/Info.plist").open("rb") as handle:
    gate3 = plistlib.load(handle)
with Path("App/Gate4Info.plist").open("rb") as handle:
    gate4 = plistlib.load(handle)

expected_gate3 = {
    "CFBundleDisplayName": "WrathiOS G3 v2",
    "CFBundleShortVersionString": "0.0.2",
    "CFBundleVersion": "2",
    "UILaunchStoryboardName": "LaunchScreen",
}
expected_gate4 = {
    "CFBundleDisplayName": "WrathiOS Import",
    "CFBundleShortVersionString": "0.0.3",
    "CFBundleVersion": "3",
    "UILaunchStoryboardName": "LaunchScreen",
}
for name, plist, expected in (("Gate 3", gate3, expected_gate3), ("Gate 4", gate4, expected_gate4)):
    for key, value in expected.items():
        if plist.get(key) != value:
            raise SystemExit(f"error: {name} {key} must be {value!r}, found {plist.get(key)!r}")

ET.parse("App/LaunchScreen.storyboard")
print("validated Gate 3 and Gate 4 plists plus LaunchScreen.storyboard")
PY

bash -n scripts/build_gate2_sdl.sh
bash -n scripts/build_gate3_device_diagnostic.sh
bash -n scripts/build_gate4_device_importer.sh
bash -n scripts/test_gate4_data_contract.sh
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

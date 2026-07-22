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
    project-gate5.yml
    project-gate5b.yml
    App/Info.plist
    App/Gate4Info.plist
    App/Gate5Info.plist
    App/Gate5BInfo.plist
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
    Gate5/WrathRuntimeHooks.h
    Gate5/WrathRuntime.h
    Gate5/WrathRuntime.mm
    Gate5/AppDelegate.h
    Gate5/AppDelegate.mm
    Gate5/main.mm
    Tests/Gate4/WrathDataContractCLI.cpp
    scripts/upstream.env
    scripts/validate_engine_manifest.py
    scripts/materialize_sdl_ios_patches.py
    scripts/materialize_gate3_platform.py
    scripts/build_gate2_sdl.sh
    scripts/build_gate3_device_diagnostic.sh
    scripts/build_gate4_device_importer.sh
    scripts/build_gate5_device_menu.sh
    scripts/build_gate5b_device_menu.sh
    scripts/test_gate5b_input_contract.py
    scripts/test_gate4_data_contract.sh
    config/engine/source_dispositions.json
    config/engine/ios_upstream_sources.txt
    docs/PORTING_PLAN.md
    docs/ASSET_POLICY.md
    docs/GATE1_SOURCE_INVENTORY.md
    docs/GATE3_GRAPHICS_DIAGNOSTIC.md
    docs/GATE4_LICENSED_DATA_IMPORT.md
    docs/GATE4_DEVICE_CHECKLIST.md
    docs/GATE5_RUNTIME_BOOTSTRAP.md
    docs/GATE5_DEVICE_CHECKLIST.md
    docs/GATE5B_MENU_INPUT.md
    docs/GATE5B_DEVICE_CHECKLIST.md
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

grep -q 'INFOPLIST_FILE: App/Gate5Info.plist' project-gate5.yml || {
    echo "error: Gate 5 does not consume its committed Info.plist" >&2
    exit 1
}
if grep -Eq '^[[:space:]]+info:[[:space:]]*$' project-gate5.yml; then
    echo "error: Gate 5 lets XcodeGen overwrite its committed Info.plist" >&2
    exit 1
fi

grep -q 'INFOPLIST_FILE: App/Gate5BInfo.plist' project-gate5b.yml || {
    echo "error: Gate 5B does not consume its committed Info.plist" >&2
    exit 1
}
if grep -Eq '^[[:space:]]+info:[[:space:]]*$' project-gate5b.yml; then
    echo "error: Gate 5B lets XcodeGen overwrite its committed Info.plist" >&2
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
with Path("App/Gate5Info.plist").open("rb") as handle:
    gate5 = plistlib.load(handle)
with Path("App/Gate5BInfo.plist").open("rb") as handle:
    gate5b = plistlib.load(handle)

expected_gate3 = {
    "CFBundleDisplayName": "WrathiOS G3 v2",
    "CFBundleShortVersionString": "0.0.2",
    "CFBundleVersion": "2",
    "UILaunchStoryboardName": "LaunchScreen",
}
expected_gate4 = {
    "CFBundleDisplayName": "WrathiOS Import",
    "CFBundleShortVersionString": "0.0.4",
    "CFBundleVersion": "4",
    "UILaunchStoryboardName": "LaunchScreen",
}
expected_gate5 = {
    "CFBundleDisplayName": "WrathiOS G5",
    "CFBundleShortVersionString": "0.0.5",
    "CFBundleVersion": "5",
    "UILaunchStoryboardName": "LaunchScreen",
}
expected_gate5b = {
    "CFBundleDisplayName": "WrathiOS G5B",
    "CFBundleShortVersionString": "0.0.6",
    "CFBundleVersion": "6",
    "UILaunchStoryboardName": "LaunchScreen",
}
for name, plist, expected in (("Gate 3", gate3, expected_gate3), ("Gate 4", gate4, expected_gate4), ("Gate 5", gate5, expected_gate5), ("Gate 5B", gate5b, expected_gate5b)):
    for key, value in expected.items():
        if plist.get(key) != value:
            raise SystemExit(f"error: {name} {key} must be {value!r}, found {plist.get(key)!r}")

ET.parse("App/LaunchScreen.storyboard")
print("validated Gate 3 through Gate 5B plists plus LaunchScreen.storyboard")
PY

bash -n scripts/build_gate2_sdl.sh
bash -n scripts/build_gate3_device_diagnostic.sh
bash -n scripts/build_gate4_device_importer.sh
bash -n scripts/build_gate5_device_menu.sh
bash -n scripts/build_gate5b_device_menu.sh
bash -n scripts/test_gate4_data_contract.sh
python3 -m py_compile scripts/materialize_sdl_ios_patches.py scripts/materialize_gate3_platform.py
python3 -m py_compile scripts/build_gate2_engine_archive.py scripts/materialize_engine_patches.py
python3 scripts/test_gate5b_input_contract.py
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

gate4_source="Gate4/WrathImportViewController.mm"
for title in "Choose WRATH Folder" "Remove Imported Data"; do
    grep -Fq "$title" "$gate4_source" || {
        echo "error: Gate 4 source is missing action title: $title" >&2
        exit 1
    }
done

required_gate4_statuses=(
    "No imported data"
    "Invalid folder rejected"
    "Source data validation passed"
    "Copy in progress"
    "Post-copy validation passed"
    "Imported data available after relaunch"
    "Imported data removed"
)
for status in "${required_gate4_statuses[@]}"; do
    grep -Fq "$status" Gate4/WrathImportViewController.mm Gate4/WrathDataImporter.mm || {
        echo "error: Gate 4 source is missing acceptance status: $status" >&2
        exit 1
    }
done

grep -q 'configurationUpdateHandler' "$gate4_source" || {
    echo "error: Gate 4 buttons do not define configuration state handling" >&2
    exit 1
}
grep -q 'baseForegroundColor' "$gate4_source" || {
    echo "error: Gate 4 buttons do not define readable configuration foreground colors" >&2
    exit 1
}
if grep -Eq 'self\.(chooseButton|removeButton)\.configuration\.(title|baseForegroundColor|cornerStyle)[[:space:]]*=' "$gate4_source"; then
    echo "error: Gate 4 mutates an already-assigned button configuration without reapplying it" >&2
    exit 1
fi

required_gate5_stages=(
    "Imported data detected"
    "Imported data validation passed"
    "Runtime path contract prepared"
    "SDL main readiness established"
    "SDL initialized"
    "Video subsystem initialized"
    "GLES context created"
    "WRATH filesystem initialization entered"
    "kp1 package discovery entered"
    "QuakeC VM loading entered"
    "menu.dat loading entered"
    "Main menu reached"
    "Audio initialization entered"
    "Audio initialization passed"
    "Audio initialization failed"
)
for stage in "${required_gate5_stages[@]}"; do
    grep -Fq "$stage" Gate5/WrathRuntime.mm config/engine/ios_source_patches.json || {
        echo "error: Gate 5 source is missing runtime stage: $stage" >&2
        exit 1
    }
done

grep -Fq 'Launch WRATH' Gate4/WrathImportViewController.mm || {
    echo "error: Gate 5 launch action is missing" >&2
    exit 1
}
grep -Fq 'SDL_iPhoneSetEventPump(SDL_TRUE)' Gate5/WrathRuntime.mm || {
    echo "error: Gate 5 does not enable SDL's UIKit event pump around Host_Main" >&2
    exit 1
}
grep -Fq 'Host_Main();' Gate5/WrathRuntime.mm || {
    echo "error: Gate 5 does not invoke the authentic WRATH runtime" >&2
    exit 1
}
grep -Fq '<private-path>' Gate5/WrathRuntime.mm || {
    echo "error: Gate 5 private-path sanitizer marker is missing" >&2
    exit 1
}
grep -Fq 'WRATH_ENGINE_BUILD_FLAVOR=gate5' scripts/build_gate5_device_menu.sh || {
    echo "error: Gate 5 device build does not select the instrumented engine archive" >&2
    exit 1
}
grep -Fq 'WRATH_ENGINE_BUILD_FLAVOR=gate5b' scripts/build_gate5b_device_menu.sh || {
    echo "error: Gate 5B device build does not select the deterministic-input engine archive" >&2
    exit 1
}

echo "repository checks passed"

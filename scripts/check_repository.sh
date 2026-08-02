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
    project-gate5c.yml
    App/Info.plist
    App/Gate4Info.plist
    App/Gate5Info.plist
    App/Gate5CInfo.plist
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
    Gate5C/WrathSemanticMenuBridge.h
    Gate5C/WrathSemanticMenuBridge.mm
    Gate5C/WrathSemanticMenuModel.hpp
    Gate5C/WrathSemanticMenuModel.cpp
    Gate5C/Resources/wrathios-menu.dat
    Tests/Gate5C/WrathSemanticMenuModelTests.cpp
    Tests/Gate4/WrathDataContractCLI.cpp
    scripts/upstream.env
    scripts/validate_engine_manifest.py
    scripts/materialize_sdl_ios_patches.py
    scripts/materialize_gate3_platform.py
    scripts/build_gate2_sdl.sh
    scripts/build_gate3_device_diagnostic.sh
    scripts/build_gate4_device_importer.sh
    scripts/build_gate5_device_menu.sh
    scripts/build_gate5c_device_semantic_menu.sh
    scripts/materialize_gate5c_menu_qc.py
    scripts/test_gate5c_semantic_menu.sh
    scripts/test_gate4_data_contract.sh
    config/engine/source_dispositions.json
    config/engine/ios_upstream_sources.txt
    config/qc/ios_semantic_menu_patches.json
    docs/PORTING_PLAN.md
    docs/ASSET_POLICY.md
    docs/GATE1_SOURCE_INVENTORY.md
    docs/GATE3_GRAPHICS_DIAGNOSTIC.md
    docs/GATE4_LICENSED_DATA_IMPORT.md
    docs/GATE4_DEVICE_CHECKLIST.md
    docs/GATE5_RUNTIME_BOOTSTRAP.md
    docs/GATE5_DEVICE_CHECKLIST.md
    docs/GATE5C_SEMANTIC_MENU_TOUCH.md
    docs/GATE5C_DEVICE_CHECKLIST.md
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

grep -q 'INFOPLIST_FILE: App/Gate5CInfo.plist' project-gate5c.yml || {
    echo "error: Gate 5C does not consume its committed Info.plist" >&2
    exit 1
}
if grep -Eq '^[[:space:]]+info:[[:space:]]*$' project-gate5c.yml; then
    echo "error: Gate 5C lets XcodeGen overwrite its committed Info.plist" >&2
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
with Path("App/Gate5CInfo.plist").open("rb") as handle:
    gate5c = plistlib.load(handle)

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
expected_gate5c = {
    "CFBundleDisplayName": "WrathiOS G5C",
    "CFBundleShortVersionString": "0.0.11",
    "CFBundleVersion": "11",
    "UILaunchStoryboardName": "LaunchScreen",
}
for name, plist, expected in (("Gate 3", gate3, expected_gate3), ("Gate 4", gate4, expected_gate4), ("Gate 5", gate5, expected_gate5), ("Gate 5C", gate5c, expected_gate5c)):
    for key, value in expected.items():
        if plist.get(key) != value:
            raise SystemExit(f"error: {name} {key} must be {value!r}, found {plist.get(key)!r}")

ET.parse("App/LaunchScreen.storyboard")
print("validated Gate 3, Gate 4, Gate 5, and Gate 5C plists plus LaunchScreen.storyboard")
PY

bash -n scripts/build_gate2_sdl.sh
bash -n scripts/build_gate3_device_diagnostic.sh
bash -n scripts/build_gate4_device_importer.sh
bash -n scripts/build_gate5_device_menu.sh
bash -n scripts/build_gate5c_device_semantic_menu.sh
bash -n scripts/test_gate5c_semantic_menu.sh
bash -n scripts/test_gate4_data_contract.sh
python3 -m py_compile scripts/materialize_sdl_ios_patches.py scripts/materialize_gate3_platform.py
python3 -m py_compile scripts/build_gate2_engine_archive.py scripts/materialize_engine_patches.py scripts/materialize_gate5c_menu_qc.py
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

grep -Fq 'GATE 5C · SEMANTIC MENU TOUCH' Gate4/WrathImportViewController.mm || {
    echo "error: Gate 5C visible launcher provenance is missing" >&2
    exit 1
}
grep -Fq '0.0.11 (11) · based on Gate 5A main 538a61f · semantic adapter contract v1' Gate4/WrathImportViewController.mm || {
    echo "error: Gate 5C visible version/base provenance is missing" >&2
    exit 1
}
grep -Fq 'WRATHIOS_GATE5C_SEMANTIC_MENU_TOUCH_V1' Gate4/WrathImportViewController.mm || {
    echo "error: Gate 5C binary-safe contract marker is missing" >&2
    exit 1
}

grep -Fq 'wrathios_semantic_entry(chain, master_position, tsize' config/qc/ios_semantic_menu_patches.json || {
    echo "error: Gate 5C does not export authentic QC semantic bounds" >&2
    exit 1
}
grep -Fq 'WrathIOSGate5CNextButtonEvent' config/engine/ios_source_patches.json || {
    echo "error: Gate 5C authentic pointer-hover-click bridge is missing" >&2
    exit 1
}
grep -Fq 'WRATH_ENGINE_BUILD_FLAVOR=gate5c' scripts/build_gate5c_device_semantic_menu.sh || {
    echo "error: Gate 5C build does not select its isolated engine archive" >&2
    exit 1
}

python3 - <<'PY'
from hashlib import sha256
from pathlib import Path

path = Path("Gate5C/Resources/wrathios-menu.dat")
expected = "3d848d8988952cff025a167e52574ff0a70c142c8aa9d934d0df9313b045ee2b"
actual = sha256(path.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"error: Gate 5C derived menu bytecode checksum mismatch: {actual}")
print("validated Gate 5C pinned derived menu bytecode")
PY

if grep -ERni 'CMMotionManager|swipe[-_ ]?look|virtual[ _-]?joystick|fire[ _-]?button' Gate5C Tests/Gate5C; then
    echo "error: excluded keyboard/gyro/swipe/gameplay controls entered Gate 5C" >&2
    exit 1
fi

echo "repository checks passed"

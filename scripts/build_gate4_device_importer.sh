#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData/Gate4"
ARTIFACT_DIR="$ROOT_DIR/Artifacts/gate4-device-importer"
LOG="$ARTIFACT_DIR/xcodebuild.log"
PROJECT="$ROOT_DIR/WrathiOSGate4.xcodeproj"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug-iphoneos/WrathiOSGate4.app"
BINARY="$APP_BUNDLE/WrathiOSGate4"
PACKAGE_ROOT="$ROOT_DIR/Derived/gate4-package"
IPA="$ARTIFACT_DIR/WrathiOSGate4-v4-unsigned.ipa"

mkdir -p "$ARTIFACT_DIR"
rm -rf "$DERIVED_DATA" "$PROJECT" "$PACKAGE_ROOT"

command -v xcodegen >/dev/null 2>&1 || {
  echo "error: xcodegen is required" >&2
  exit 2
}

cd "$ROOT_DIR"
xcodegen generate --spec project-gate4.yml

set -o pipefail
xcodebuild \
  -project WrathiOSGate4.xcodeproj \
  -scheme WrathiOSGate4 \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "$LOG"

[[ -d "$APP_BUNDLE" && -f "$BINARY" ]] || {
  echo "error: Gate 4 application bundle was not produced" >&2
  exit 1
}

file "$BINARY" | tee "$ARTIFACT_DIR/file.txt"
lipo -info "$BINARY" | tee "$ARTIFACT_DIR/architecture.txt"
otool -L "$BINARY" | tee "$ARTIFACT_DIR/dynamic-dependencies.txt"
nm -gU "$BINARY" > "$ARTIFACT_DIR/global-symbols.txt"
plutil -p "$APP_BUNDLE/Info.plist" > "$ARTIFACT_DIR/Info.plist.txt"
strings -a "$BINARY" > "$ARTIFACT_DIR/strings.txt"
find "$APP_BUNDLE" -print | sed "s#^$APP_BUNDLE#.#" | sort > "$ARTIFACT_DIR/bundle-inventory.txt"

architecture="$(cat "$ARTIFACT_DIR/architecture.txt")"
[[ "$architecture" == *"arm64"* ]] || {
  echo "error: Gate 4 application is not arm64" >&2
  exit 1
}

grep -q '_OBJC_CLASS_$_WrathImportViewController' "$ARTIFACT_DIR/global-symbols.txt" || {
  echo "error: Gate 4 importer view-controller class is missing" >&2
  exit 1
}
grep -q '_OBJC_CLASS_$_WrathDataImporter' "$ARTIFACT_DIR/global-symbols.txt" || {
  echo "error: Gate 4 importer service class is missing" >&2
  exit 1
}
for title in 'Choose WRATH Folder' 'Remove Imported Data'; do
  grep -Fq "$title" "$ARTIFACT_DIR/strings.txt" || {
    echo "error: Gate 4 binary is missing visible button title: $title" >&2
    exit 1
  }
done
for sentinel in progs.dat csprogs.dat menu.dat; do
  grep -q "$sentinel" "$ARTIFACT_DIR/strings.txt" || {
    echo "error: Gate 4 binary is missing sentinel marker: $sentinel" >&2
    exit 1
  }
done

if grep -Eq '_Host_Main$|_SDL_Init$' "$ARTIFACT_DIR/global-symbols.txt"; then
  echo "error: Gate 4 must not link or start the WRATH runtime" >&2
  exit 1
fi
printf '%s\n' 'Host_Main: absent' 'SDL_Init: absent' > "$ARTIFACT_DIR/runtime-symbol-audit.txt"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_BUNDLE/Info.plist")"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Info.plist")"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_BUNDLE/Info.plist")"
launch_storyboard="$(/usr/libexec/PlistBuddy -c 'Print :UILaunchStoryboardName' "$APP_BUNDLE/Info.plist")"
[[ "$bundle_id" == "com.arjukstudios.wrathios.gate3" ]] || {
  echo "error: unexpected Gate 4 bundle identifier: $bundle_id" >&2
  exit 1
}
[[ "$short_version" == "0.0.4" ]] || {
  echo "error: unexpected Gate 4 short version: $short_version" >&2
  exit 1
}
[[ "$build_version" == "4" ]] || {
  echo "error: unexpected Gate 4 build version: $build_version" >&2
  exit 1
}
[[ "$launch_storyboard" == "LaunchScreen" ]] || {
  echo "error: unexpected Gate 4 launch storyboard declaration: $launch_storyboard" >&2
  exit 1
}
launch_storyboard_path="$(find "$APP_BUNDLE" -type d -name 'LaunchScreen.storyboardc' -print -quit)"
[[ -n "$launch_storyboard_path" ]] || {
  echo "error: compiled LaunchScreen.storyboardc is missing from the Gate 4 bundle" >&2
  cat "$ARTIFACT_DIR/bundle-inventory.txt" >&2
  exit 1
}
printf '%s\n' "${launch_storyboard_path#"$APP_BUNDLE"/}" > "$ARTIFACT_DIR/launch-storyboard-location.txt"

python3 - "$APP_BUNDLE/Info.plist" <<'PY'
import plistlib
from pathlib import Path
import sys

with Path(sys.argv[1]).open("rb") as handle:
    info = plistlib.load(handle)
expected = ["UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]
for key in ("UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~ipad"):
    if info.get(key) != expected:
        raise SystemExit(f"error: {key} is not landscape-only: {info.get(key)!r}")
print("validated landscape-only orientation declarations")
PY

python3 - "$ARTIFACT_DIR/dynamic-dependencies.txt" <<'PY' | tee "$ARTIFACT_DIR/dynamic-dependency-audit.txt"
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()[1:]
paths = [line.strip().split()[0] for line in lines if line.strip()]
allowed = ("/System/Library/Frameworks/", "/usr/lib/")
invalid = [path for path in paths if not path.startswith(allowed)]
if invalid:
    print("error: non-system dynamic dependencies detected:", file=sys.stderr)
    for path in invalid:
        print(f"  {path}", file=sys.stderr)
    raise SystemExit(1)
print(f"validated {len(paths)} system dynamic dependencies")
PY

python3 - "$APP_BUNDLE" <<'PY' | tee "$ARTIFACT_DIR/commercial-data-audit.txt"
from pathlib import Path
import sys

root = Path(sys.argv[1])
archive_suffixes = {".pak", ".pk3", ".pk4", ".wad", ".gro"}
sentinels = {"progs.dat", "csprogs.dat", "menu.dat"}
commercial_paths = []
for path in root.rglob("*"):
    relative = path.relative_to(root)
    lowered_parts = {part.lower() for part in relative.parts}
    if (path.is_file() and (
        path.suffix.lower() in archive_suffixes
        or path.name.lower() in sentinels
        or "kp1" in lowered_parts
        or "gamedata" in lowered_parts
    )):
        commercial_paths.append(relative.as_posix())
if commercial_paths:
    print("error: Gate 4 bundle contains commercial-data paths:", file=sys.stderr)
    for path in commercial_paths:
        print(f"  {path}", file=sys.stderr)
    raise SystemExit(1)
print("commercial WRATH files: absent")
PY

if codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1; then
  echo "error: CI importer unexpectedly contains a valid signature" >&2
  exit 1
else
  echo "unsigned CI bundle confirmed" > "$ARTIFACT_DIR/signing-status.txt"
fi

mkdir -p "$PACKAGE_ROOT/Payload"
ditto "$APP_BUNDLE" "$PACKAGE_ROOT/Payload/WrathiOSGate4.app"
rm -rf "$PACKAGE_ROOT/Payload/WrathiOSGate4.app/_CodeSignature"
rm -f "$PACKAGE_ROOT/Payload/WrathiOSGate4.app/embedded.mobileprovision"
(
  cd "$PACKAGE_ROOT"
  /usr/bin/zip -qry "$IPA" Payload
)

[[ -s "$IPA" ]] || {
  echo "error: unsigned Gate 4 IPA was not produced" >&2
  exit 1
}
/usr/bin/unzip -tq "$IPA" > "$ARTIFACT_DIR/ipa-validation.txt"
/usr/bin/unzip -Z1 "$IPA" | sort > "$ARTIFACT_DIR/ipa-inventory.txt"
if grep -Eq '(^|/)(_CodeSignature/|embedded\.mobileprovision$)' "$ARTIFACT_DIR/ipa-inventory.txt"; then
  echo "error: unsigned Gate 4 IPA contains signing material" >&2
  exit 1
fi
shasum -a 256 "$BINARY" "$IPA" > "$ARTIFACT_DIR/SHA256SUMS.txt"
cp "$BINARY" "$ARTIFACT_DIR/WrathiOSGate4-arm64"

ipa_size="$(stat -f '%z' "$IPA")"
ipa_sha256="$(shasum -a 256 "$IPA" | awk '{print $1}')"

cat > "$ARTIFACT_DIR/device-test-checklist.md" <<'EOF'
# Gate 4 physical-device checklist

1. Install `WrathiOSGate4-v4-unsigned.ipa` through the existing Gate 3 App ID without deleting the app first.
2. Launch with no imported data. Capture **No imported data** and both readable button titles.
3. Select an unrelated or invalid folder and capture **Invalid folder rejected**.
4. Select the licensed WRATH root containing `kp1`, or `kp1` itself.
5. Observe **Source data validation passed** and capture **Copy in progress** with the completed source-validation line.
6. Capture **Post-copy validation passed** with profile, file count, package count, size, sentinels, and **Imported during this session**.
7. Force-quit and relaunch. Without selecting the source again, capture **Imported data available after relaunch** and **Detected at launch**.
8. Tap **Remove Imported Data**, confirm, and capture **Imported data removed**.
9. Confirm the removal action is no longer exposed and the screen explicitly reports that no imported data remains.
10. Force-quit and relaunch once more; capture **No imported data** to prove removal persisted.

Do not attach imported files, package listings containing private paths, or the app container to issues or CI artifacts.
EOF

cat > "$ARTIFACT_DIR/summary.md" <<EOF
# Gate 4 device importer build

- Target: arm64-apple-ios16.3
- Bundle ID: \`$bundle_id\` (reuses the existing diagnostic App ID)
- Version: \`$short_version ($build_version)\`
- IPA: \`$(basename "$IPA")\`
- IPA size: \`$ipa_size bytes\`
- IPA SHA-256: \`$ipa_sha256\`
- Runtime engine startup: absent
- Validation profile: \`wrath-1.1.2-qc-layout-v1\`
- Required sentinels: \`progs.dat\`, \`csprogs.dat\`, \`menu.dat\`
- Supported package indexes: PK3 and Quake PAK
- Launch storyboard: \`${launch_storyboard_path#"$APP_BUNDLE"/}\`
- Orientation: landscape-only
- Non-system dynamic dependencies: none
- Bundle inventory: commercial-data and signing-material audit passed
- Commercial data in IPA: absent
- Provisioning profile: absent
- ZIP integrity: passed
- Packaging: unsigned IPA for external signing
EOF

cat "$ARTIFACT_DIR/summary.md"
cat "$ARTIFACT_DIR/SHA256SUMS.txt"
echo "Gate 4 device importer build and packaging validation passed"

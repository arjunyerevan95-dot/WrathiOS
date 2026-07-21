#!/usr/bin/env python3
"""Compile the Gate 1 source graph into an arm64 iPhoneOS static archive."""

from __future__ import annotations

import json
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "Vendor" / "wrath-darkplaces"
PATCHED_ENGINE = ROOT / "Derived" / "wrath-darkplaces-ios"
SDL = ROOT / "Vendor" / "SDL2"
DEPS_PREFIX = ROOT / "Derived" / "deps" / "iphoneos"
MANIFEST = ROOT / "config" / "engine" / "ios_upstream_sources.txt"
BUILD_DIR = ROOT / "Derived" / "gate2-engine-archive"
OBJECT_DIR = BUILD_DIR / "objects"
ARTIFACT_DIR = ROOT / "Artifacts" / "gate2-engine-archive"
ENGINE_PREFIX = "Vendor/wrath-darkplaces/"
ENGINE_COMMIT = "f6862f628d6ddc133a9ef67bc4631b6137809772"


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, check=False)


def main() -> int:
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    if BUILD_DIR.exists():
        shutil.rmtree(BUILD_DIR)
    OBJECT_DIR.mkdir(parents=True)

    required = [
        ENGINE / ".git",
        SDL / "include" / "SDL.h",
        DEPS_PREFIX / "include" / "ogg" / "ogg.h",
        DEPS_PREFIX / "include" / "vorbis" / "vorbisfile.h",
        DEPS_PREFIX / "lib" / "libogg.a",
        DEPS_PREFIX / "lib" / "libvorbis.a",
        DEPS_PREFIX / "lib" / "libvorbisfile.a",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.exists()]
    if missing:
        message = "missing Gate 2 prerequisites: " + ", ".join(missing)
        (ARTIFACT_DIR / "build.log").write_text(message + "\n", encoding="utf-8")
        print(f"error: {message}", file=sys.stderr)
        return 2

    materialize = run([sys.executable, str(ROOT / "scripts" / "materialize_engine_patches.py")])
    if materialize.returncode:
        message = materialize.stderr or materialize.stdout
        (ARTIFACT_DIR / "build.log").write_text(message, encoding="utf-8")
        print(message, file=sys.stderr)
        return 2

    sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"])
    clang = run(["xcrun", "--sdk", "iphoneos", "--find", "clang"])
    ar = run(["xcrun", "--sdk", "iphoneos", "--find", "ar"])
    if sdk.returncode or clang.returncode or ar.returncode:
        message = sdk.stderr or clang.stderr or ar.stderr
        (ARTIFACT_DIR / "build.log").write_text(message, encoding="utf-8")
        print(message, file=sys.stderr)
        return 2

    sdk_path = sdk.stdout.strip()
    clang_path = clang.stdout.strip()
    ar_path = ar.stdout.strip()
    common = [
        clang_path,
        "-arch", "arm64",
        "-isysroot", sdk_path,
        "-miphoneos-version-min=16.3",
        "-std=gnu17",
        "-O0",
        "-g0",
        "-fno-common",
        "-Wno-deprecated-declarations",
        "-DWRATH_IOS=1",
        "-D__IPHONEOS__=1",
        "-DUSE_GLES2=1",
        "-DCONFIG_MENU=1",
        "-D_FILE_OFFSET_BITS=64",
        "-D__KERNEL_STRICT_NAMES=1",
        f"-DSVNREVISION={ENGINE_COMMIT}",
        "-DBUILDTYPE=ios_gate2",
        f"-I{ENGINE}",
        f"-I{SDL / 'include'}",
        f"-I{DEPS_PREFIX / 'include'}",
    ]

    manifest_paths = [
        line.strip()
        for line in MANIFEST.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    results: list[dict[str, object]] = []
    transcript = [materialize.stdout.strip()]
    object_paths: list[Path] = []

    for index, manifest_path in enumerate(manifest_paths):
        if not manifest_path.startswith(ENGINE_PREFIX):
            raise ValueError(f"unexpected engine manifest path: {manifest_path}")
        relative = Path(manifest_path.removeprefix(ENGINE_PREFIX))
        patched_source = PATCHED_ENGINE / relative
        source = patched_source if patched_source.is_file() else ENGINE / relative
        object_path = OBJECT_DIR / f"{index:03d}-{relative.stem}.o"
        command = [*common, "-c", str(source), "-o", str(object_path)]
        completed = run(command)
        status = "pass" if completed.returncode == 0 else "fail"
        if completed.returncode == 0:
            object_paths.append(object_path)
        results.append({
            "source": manifest_path,
            "compiled_source": str(source.relative_to(ROOT)),
            "patched": patched_source.is_file(),
            "object": str(object_path.relative_to(ROOT)),
            "status": status,
            "returncode": completed.returncode,
            "command": shlex.join(command),
            "stdout": completed.stdout,
            "stderr": completed.stderr,
        })
        line = f"[{status}] {manifest_path}"
        transcript.append(line)
        print(line)

    failed = [item for item in results if item["status"] == "fail"]
    report: dict[str, object] = {
        "schema_version": 1,
        "target": "arm64-apple-ios16.3",
        "engine_commit": ENGINE_COMMIT,
        "summary": {
            "total": len(results),
            "compiled": len(object_paths),
            "failed": len(failed),
        },
        "results": results,
    }

    if failed:
        (ARTIFACT_DIR / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        (ARTIFACT_DIR / "build.log").write_text("\n".join(transcript) + "\n", encoding="utf-8")
        print(f"error: {len(failed)} engine units failed object compilation", file=sys.stderr)
        return 1

    archive = BUILD_DIR / "libwrath-engine.a"
    archive_command = [ar_path, "rcs", str(archive), *(str(path) for path in object_paths)]
    archived = run(archive_command)
    if archived.returncode:
        transcript.extend([shlex.join(archive_command), archived.stdout, archived.stderr])
        (ARTIFACT_DIR / "build.log").write_text("\n".join(transcript) + "\n", encoding="utf-8")
        print(archived.stderr, file=sys.stderr)
        return 1

    lipo = run(["lipo", "-info", str(archive)])
    members = run([ar_path, "-t", str(archive)])
    undefined = run(["nm", "-u", str(archive)])
    if lipo.returncode or members.returncode or undefined.returncode:
        message = lipo.stderr or members.stderr or undefined.stderr
        print(message, file=sys.stderr)
        return 1

    member_names = [line for line in members.stdout.splitlines() if line.strip()]
    undefined_lines = [line.rstrip() for line in undefined.stdout.splitlines() if line.strip()]
    report["archive"] = {
        "path": str(archive.relative_to(ROOT)),
        "architecture": lipo.stdout.strip(),
        "member_count": len(member_names),
        "undefined_symbol_lines": len(undefined_lines),
    }
    (ARTIFACT_DIR / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    (ARTIFACT_DIR / "members.txt").write_text("\n".join(member_names) + "\n", encoding="utf-8")
    (ARTIFACT_DIR / "undefined-symbols.txt").write_text("\n".join(undefined_lines) + "\n", encoding="utf-8")
    transcript.append(shlex.join(archive_command))
    transcript.append(lipo.stdout.strip())
    transcript.append(f"archive members: {len(member_names)}")
    transcript.append(f"undefined symbol lines: {len(undefined_lines)}")
    (ARTIFACT_DIR / "build.log").write_text("\n".join(transcript) + "\n", encoding="utf-8")
    shutil.copy2(archive, ARTIFACT_DIR / archive.name)

    summary = [
        "# Gate 2 engine archive",
        "",
        f"- Compiled units: {len(object_paths)}/{len(results)}",
        f"- Archive members: {len(member_names)}",
        f"- Architecture: `{lipo.stdout.strip()}`",
        f"- Undefined-symbol output lines: {len(undefined_lines)}",
        "",
        "The archive is not a Gate 2 pass by itself. The next experiment must force-load it into the iOS application and resolve the recorded platform and dependency symbols.",
    ]
    (ARTIFACT_DIR / "summary.md").write_text("\n".join(summary) + "\n", encoding="utf-8")
    print(f"built {archive.name} with {len(member_names)} arm64 members")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Compile every Gate 2 WRATH source unit against the iPhoneOS SDK.

This is a diagnostic precursor to the static-link gate. It deliberately records
all translation-unit failures rather than stopping at the first compiler error.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "Vendor" / "wrath-darkplaces"
SDL = ROOT / "Vendor" / "SDL"
MANIFEST = ROOT / "config" / "engine" / "ios_upstream_sources.txt"
OUTPUT_DIR = ROOT / "Artifacts" / "gate2-compile-probe"


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, capture_output=True, check=False)


def main() -> int:
    if not ENGINE.is_dir() or not SDL.is_dir():
        print("error: pinned upstream checkouts are missing; run scripts/fetch_upstream.sh", file=sys.stderr)
        return 2

    sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"])
    clang = run(["xcrun", "--sdk", "iphoneos", "--find", "clang"])
    if sdk.returncode or clang.returncode:
        print(sdk.stderr or clang.stderr, file=sys.stderr)
        return 2

    sdk_path = sdk.stdout.strip()
    clang_path = clang.stdout.strip()
    sources = [
        line.strip()
        for line in MANIFEST.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    common = [
        clang_path,
        "-arch", "arm64",
        "-isysroot", sdk_path,
        "-miphoneos-version-min=16.3",
        "-std=gnu17",
        "-fsyntax-only",
        "-Wno-deprecated-declarations",
        "-DWRATH_IOS=1",
        "-D__IPHONEOS__=1",
        "-DUSE_GLES2=1",
        "-DCONFIG_MENU=1",
        "-D_FILE_OFFSET_BITS=64",
        "-D__KERNEL_STRICT_NAMES=1",
        f"-I{ENGINE}",
        f"-I{SDL / 'include'}",
    ]

    results: list[dict[str, object]] = []
    for relative in sources:
        source = ENGINE / relative
        command = [*common, str(source)]
        completed = run(command)
        results.append({
            "source": relative,
            "status": "pass" if completed.returncode == 0 else "fail",
            "returncode": completed.returncode,
            "command": shlex.join(command),
            "stdout": completed.stdout,
            "stderr": completed.stderr,
        })
        print(f"[{results[-1]['status']}] {relative}")

    passed = sum(item["status"] == "pass" for item in results)
    failed = len(results) - passed
    report = {
        "schema_version": 1,
        "target": "arm64-apple-ios16.3",
        "sdk_path": sdk_path,
        "engine_commit": run(["git", "-C", str(ENGINE), "rev-parse", "HEAD"]).stdout.strip(),
        "sdl_commit": run(["git", "-C", str(SDL), "rev-parse", "HEAD"]).stdout.strip(),
        "summary": {"total": len(results), "passed": passed, "failed": failed},
        "results": results,
    }
    (OUTPUT_DIR / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Gate 2 arm64 compile probe",
        "",
        f"- Total units: {len(results)}",
        f"- Passed: {passed}",
        f"- Failed: {failed}",
        "",
        "## Failed units",
        "",
    ]
    for item in results:
        if item["status"] == "fail":
            first_error = next(
                (line.strip() for line in str(item["stderr"]).splitlines() if "error:" in line),
                "compiler failed without an error line",
            )
            lines.append(f"- `{item['source']}`: {first_error}")
    (OUTPUT_DIR / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"Gate 2 probe complete: {passed}/{len(results)} units passed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())

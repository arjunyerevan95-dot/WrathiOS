#!/usr/bin/env python3
"""Materialize provenance-checked iOS patches without modifying Vendor/."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / "Vendor" / "wrath-darkplaces"
PATCH_SPEC = ROOT / "config" / "engine" / "ios_source_patches.json"
OUTPUT = ROOT / "Derived" / "wrath-darkplaces-ios"
REPORT = ROOT / "Artifacts" / "engine-patches" / "report.json"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_head(path: Path) -> str:
    completed = subprocess.run(
        ["git", "-C", str(path), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode:
        raise RuntimeError(completed.stderr.strip() or "unable to read upstream revision")
    return completed.stdout.strip()


def main() -> int:
    if not (UPSTREAM / ".git").is_dir():
        print("error: missing pinned WRATH checkout", file=sys.stderr)
        return 2

    spec = json.loads(PATCH_SPEC.read_text(encoding="utf-8"))
    actual_commit = git_head(UPSTREAM)
    expected_commit = spec["upstream_commit"]
    if actual_commit != expected_commit:
        print(
            f"error: patch specification expects {expected_commit}, found {actual_commit}",
            file=sys.stderr,
        )
        return 2

    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True)
    REPORT.parent.mkdir(parents=True, exist_ok=True)

    records: list[dict[str, object]] = []
    try:
        for patch in spec["patches"]:
            relative = Path(patch["path"])
            source = UPSTREAM / relative
            destination = OUTPUT / relative
            original_bytes = source.read_bytes()
            text = original_bytes.decode("utf-8")
            replacement_records = []

            for replacement in patch["replacements"]:
                old = replacement["old"]
                new = replacement["new"]
                occurrences = text.count(old)
                if occurrences != 1:
                    raise RuntimeError(
                        f"{relative}: expected one occurrence of patch anchor, found {occurrences}"
                    )
                text = text.replace(old, new, 1)
                replacement_records.append({
                    "old_sha256": sha256(old.encode("utf-8")),
                    "new_sha256": sha256(new.encode("utf-8")),
                })

            destination.parent.mkdir(parents=True, exist_ok=True)
            patched_bytes = text.encode("utf-8")
            destination.write_bytes(patched_bytes)
            records.append({
                "path": relative.as_posix(),
                "reason": patch["reason"],
                "source_sha256": sha256(original_bytes),
                "patched_sha256": sha256(patched_bytes),
                "replacements": replacement_records,
            })
    except (KeyError, OSError, RuntimeError, UnicodeDecodeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    report = {
        "schema_version": 1,
        "upstream_commit": actual_commit,
        "patch_spec": str(PATCH_SPEC.relative_to(ROOT)),
        "patched_files": records,
    }
    REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"materialized {len(records)} patched engine files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

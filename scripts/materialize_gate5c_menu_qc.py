#!/usr/bin/env python3
"""Materialize provenance-checked Gate 5C menu QC hooks without editing Vendor/."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / "Vendor" / "wrath-qc"
SPEC = ROOT / "config" / "qc" / "ios_semantic_menu_patches.json"
OUTPUT = ROOT / "Derived" / "wrath-qc-gate5c"
REPORT = ROOT / "Artifacts" / "gate5c-qc-patches" / "report.json"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    if not (UPSTREAM / ".git").is_dir():
        print("error: missing pinned WRATH QC checkout", file=sys.stderr)
        return 2
    head = subprocess.run(
        ["git", "-C", str(UPSTREAM), "rev-parse", "HEAD"],
        text=True,
        capture_output=True,
        check=False,
    )
    if head.returncode:
        print(head.stderr, file=sys.stderr)
        return 2
    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    actual = head.stdout.strip()
    if actual != spec["upstream_commit"]:
        print(f"error: expected QC {spec['upstream_commit']}, found {actual}", file=sys.stderr)
        return 2

    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    shutil.copytree(UPSTREAM, OUTPUT, ignore=shutil.ignore_patterns(".git"))
    records = []
    try:
        for patch in spec["patches"]:
            relative = Path(patch["path"])
            source = UPSTREAM / relative
            destination = OUTPUT / relative
            original = source.read_bytes()
            text = original.decode("utf-8").replace("\r\n", "\n")
            replacements = []
            for replacement in patch["replacements"]:
                old = replacement["old"]
                new = replacement["new"]
                occurrences = text.count(old)
                if occurrences != 1:
                    raise RuntimeError(
                        f"{relative}: expected one occurrence of patch anchor, found {occurrences}"
                    )
                text = text.replace(old, new, 1)
                replacements.append({
                    "old_sha256": digest(old.encode()),
                    "new_sha256": digest(new.encode()),
                })
            patched = text.encode("utf-8")
            destination.write_bytes(patched)
            records.append({
                "path": relative.as_posix(),
                "reason": patch["reason"],
                "source_sha256": digest(original),
                "patched_sha256": digest(patched),
                "replacements": replacements,
            })
    except (KeyError, OSError, RuntimeError, UnicodeDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps({
        "schema_version": 1,
        "upstream_commit": actual,
        "patch_spec": str(SPEC.relative_to(ROOT)),
        "patched_files": records,
    }, indent=2) + "\n", encoding="utf-8")
    print(f"materialized {len(records)} Gate 5C QC files from {actual}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

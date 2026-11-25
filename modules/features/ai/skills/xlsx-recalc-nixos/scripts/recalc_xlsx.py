#!/usr/bin/env python3
"""Recalculate all formulas of an .xlsx with headless LibreOffice (NixOS-safe).

Why this exists: the anthropic xlsx skill's recalc.py installs a Basic macro
into a fresh LibreOffice profile.  On NixOS the profile template is copied out
of /nix/store with read-only modes, so the macro file cannot be created
("Permission denied: .../user/basic/Standard/Module1.xba").  This script does
the same steps with a chmod in between and then scans the result for Excel
error values.

Usage:
    python3 recalc_xlsx.py BOOK.xlsx [--timeout 240] [--profile DIR]

Prints JSON: {"status": "success"|"errors_found", "total_formulas": N,
"total_errors": N, "error_summary": {"#NAME?": [...], ...}} or {"error": "..."}.
The workbook is rewritten IN PLACE - run it on a copy if you need the original.
Run with openpyxl available, e.g.
    nix-shell -p "python3.withPackages (ps: [ps.openpyxl])" --run "python3 recalc_xlsx.py BOOK.xlsx"
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

MACRO = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE script:module PUBLIC "-//OpenOffice.org//DTD OfficeDocument 1.0//EN" "module.dtd">
<script:module xmlns:script="http://openoffice.org/2000/script" script:name="Module1" script:language="StarBasic">
    Sub RecalculateAndSave()
      ThisComponent.calculateAll()
      ThisComponent.store()
      ThisComponent.close(True)
    End Sub
</script:module>"""

ERRORS = ["#VALUE!", "#DIV/0!", "#REF!", "#NAME?", "#NULL!", "#NUM!", "#N/A"]


def stamp(path):
    st = os.stat(path)
    return (st.st_mtime_ns, st.st_size)


def make_writable(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        for d in dirnames:
            os.chmod(os.path.join(dirpath, d), 0o755)
        for f in filenames:
            os.chmod(os.path.join(dirpath, f), 0o644)


def recalc(target: Path, profile: Path, timeout: int) -> dict:
    if shutil.which("soffice") is None:
        return {"error": "soffice not found on PATH; LibreOffice is required"}
    env = os.environ.copy()
    env["SAL_USE_VCLPLUGIN"] = "svp"
    profile.mkdir(parents=True, exist_ok=True)
    url = profile.resolve().as_uri()
    try:
        subprocess.run(
            ["soffice", "--headless", "--terminate_after_init", f"-env:UserInstallation={url}"],
            env=env, capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {"error": "LibreOffice timed out creating its profile"}
    make_writable(profile)
    macro_dir = profile / "user" / "basic" / "Standard"
    if not macro_dir.exists():
        return {"error": f"LibreOffice did not create a usable profile under {profile}"}
    (macro_dir / "Module1.xba").write_text(MACRO)
    before = stamp(target)
    cmd = ["soffice", "--headless", "--norestore", f"-env:UserInstallation={url}",
           "vnd.sun.star.script:Standard.Module1.RecalculateAndSave?language=Basic&location=application",
           str(target.resolve())]
    if shutil.which("timeout"):
        cmd = ["timeout", str(timeout)] + cmd
    try:
        r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=timeout + 15)
    except subprocess.TimeoutExpired:
        return {"error": f"LibreOffice timed out after {timeout}s; formulas were NOT recalculated"}
    if r.returncode == 124:
        return {"error": f"LibreOffice timed out after {timeout}s; formulas were NOT recalculated"}
    if r.returncode != 0:
        return {"error": f"LibreOffice failed: {(r.stderr or '').strip()[-500:] or r.returncode}"}
    if stamp(target) == before:
        return {"error": "LibreOffice exited cleanly but never rewrote the file (another soffice instance running?)"}
    return scan(target)


def scan(target: Path) -> dict:
    import openpyxl  # imported late so the error message above stays useful

    wb_f = openpyxl.load_workbook(target)
    wb_v = openpyxl.load_workbook(target, data_only=True)
    total = 0
    summary: dict[str, list[str]] = {}
    for ws in wb_f.worksheets:
        wv = wb_v[ws.title]
        for row in ws.iter_rows():
            for c in row:
                if isinstance(c.value, str) and c.value.startswith("="):
                    total += 1
                    v = wv[c.coordinate].value
                    if isinstance(v, str) and v in ERRORS:
                        summary.setdefault(v, []).append(f"{ws.title}!{c.coordinate}")
    n_err = sum(len(v) for v in summary.values())
    return {
        "status": "errors_found" if n_err else "success",
        "total_formulas": total,
        "total_errors": n_err,
        "error_summary": {k: v[:100] for k, v in summary.items()},
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("xlsx")
    ap.add_argument("--timeout", type=int, default=240)
    ap.add_argument("--profile", help="directory for the throwaway LibreOffice profile")
    a = ap.parse_args()
    target = Path(a.xlsx)
    if not target.exists():
        print(json.dumps({"error": f"{target} does not exist"}))
        sys.exit(2)
    if a.profile:
        profile = Path(a.profile)
        result = recalc(target, profile, a.timeout)
    else:
        base = os.environ.get("TMPDIR") or str(target.resolve().parent)
        with tempfile.TemporaryDirectory(prefix="lo_profile_", dir=base, ignore_cleanup_errors=True) as d:
            result = recalc(target, Path(d), a.timeout)
    print(json.dumps(result, indent=1, ensure_ascii=False))
    sys.exit(1 if "error" in result else 0)


if __name__ == "__main__":
    main()

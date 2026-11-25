---
name: xlsx-recalc-nixos
description: Recalculate every formula in an .xlsx with headless LibreOffice on this NixOS workstation and report formula errors. Use this whenever an openpyxl-written workbook needs cached values (pandas / data_only reads show None), whenever the anthropic xlsx skill's recalc.py fails with "Permission denied … Module1.xba", and before delivering any spreadsheet that contains formulas — even if the user only says "check the numbers" or "make sure the sheet works".
---

# xlsx formula recalculation on NixOS

`openpyxl` writes formulas without cached results. Anything that reads cached
values (pandas, `load_workbook(data_only=True)`, Nextcloud previews) then sees
`None`, and a typo like `=SUMIF(…)` against a missing sheet is invisible until
someone opens the file. Recalculating with LibreOffice fixes both: it computes
every cell, rewrites the file in place, and lets you scan for `#NAME?`, `#REF!`
and friends before the user ever sees them.

## Why the stock recalc.py breaks here

The anthropic xlsx skill ships `scripts/recalc.py`. On this host it always
fails with `Could not install the recalculation macro: [Errno 13] Permission
denied: …/user/basic/Standard/Module1.xba`. LibreOffice bootstraps a fresh user
profile by copying templates out of `/nix/store`, keeping their read-only
modes, so Python cannot create the macro file inside it. Nothing is wrong with
the workbook; retrying or changing TMPDIR alone does not help.

`scripts/recalc_xlsx.py` does the same job with one extra step: initialise the
profile, `chmod -R u+w` it, then install and run the macro.

## Usage

```bash
# openpyxl is not installed globally on NixOS — run through nix-shell.
nix-shell -p "python3.withPackages (ps: [ps.openpyxl])" --run \
  "python3 ~/.claude/skills/xlsx-recalc-nixos/scripts/recalc_xlsx.py /path/to/book.xlsx"
```

Options: `--timeout SECONDS` (default 240; a 20k-formula workbook takes ~30 s),
`--profile DIR` (where the throwaway LibreOffice profile lives; defaults to a
`lo_profile` directory under `$TMPDIR` or the file's directory).

Output is JSON on stdout: `status` (`success` | `errors_found`), `total_formulas`,
`total_errors`, and an `error_summary` mapping each error type to the cells
that show it. A result with an `error` key means nothing was recalculated.

## Working rules

- Recalculate a copy, not the only version of the user's file; the script
  rewrites its argument in place.
- `errors_found` exits 0 like `success` does — read the JSON, do not trust the
  exit code.
- A clean recalc proves formulas *evaluate*, not that they are *right*. After
  recalculating, read a handful of results back with
  `load_workbook(path, data_only=True)` and compare against values you computed
  independently.
- LibreOffice re-saves the file. Comments, merged cells, column widths and
  number formats survive (verified on the Kegel-Statistik workbook), but if the
  workbook came from Excel with exotic features, diff the important cells
  before and after.
- Keep `TMPDIR` on a writable path (the session scratchpad is fine). The
  `/tmp/nix-shell-*` directory nix-shell exports is not writable for soffice.
- Run the script with plain `python3`, not `python3 -I`: it imports nothing
  from the file's directory, but `-I` also drops the script directory from
  `sys.path`.

## Verifying values afterwards

```python
import openpyxl
wb = openpyxl.load_workbook(path, data_only=True)   # cached values only
ws = wb['Sheet']
print(ws['B10'].value)                                # None → not recalculated
```

Two loads are needed to see formulas *and* values (`data_only=True` strips the
formulas; never save that workbook).

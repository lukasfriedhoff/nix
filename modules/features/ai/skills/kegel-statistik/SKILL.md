---
name: kegel-statistik
description: Transcribe a KC DKKN Kegelabend (photos of the Kegelbuch page or a handwritten Zettel) into the Kegel-Statistik workbook in Nextcloud, add new players, refresh the "Statistik seit JHV" tab, and recalc/verify the xlsx. Use this whenever the user mentions Kegeln, Kegelabend, Kegelclub, KC DKKN, Strafen/Schimpfwörter/Rinnen tallies, the kasse statistics spreadsheet, Jahreshauptversammlung stats, or photos under Documents/kcdkkn — even if they only say "add this to the statistik" or paste a directory listing of pictures.
---

# KC DKKN Kegel-Statistik

Lukas keeps the penalty bookkeeping of his Kegelclub ("Der Klügere kippt nach")
in `~/Nextcloud/Documents/kcdkkn/kasse/KC DKKN Statistik 24&25&26.xlsx`. After
each Kegelabend someone photographs the Kegelbuch page (or a Zettel when the
book was missing) and the tallies have to land in the sheet. The sheet is the
club's cash truth, so every number must be traceable to the photo and every
guess must be visible. Read `references/workbook-layout.md` once per session
for the geometry, conventions and decision log; the scripts in `scripts/`
discover rows and columns themselves, so never hardcode cell addresses.

Run scripts through `scripts/run.sh` (wraps `nix-shell` with openpyxl +
Pillow; NixOS has no global Python packages): `scripts/run.sh add_evening.py …`.

## Workflow for a new evening

1. **Inspect first.** `run.sh inspect_workbook.py` prints the player blocks,
   the column pairs with their dates, which pair the new evening will use,
   and whether the file still has cached values. If the pictures directory is
   mentioned, list it and read every image — a listing usually means "here
   are the new photos".
2. **Read the photos carefully.** Book photos are usually rotated; make them
   upright (`photo_tools.py rotate … --deg -90` for text reading bottom-to-top)
   and zoom (`grid`, `crop`). For tallies, build side-by-side column strips
   from the thick Schimpfwörter line downwards (`strips`) and count rows per
   player. The Schimpfwörter row is two ruled lines tall and pages curve into
   the spine, so a stroke that looks like Taxipauschale at the label can sit
   in Kugel aus der Bahn at the player's column. When a stroke straddles a
   boundary, measure (`lines`) and assign it to the row its top starts in —
   that is how the scribes write. Count tally groups as 4 strokes + a
   diagonal = 5. Resolve nicknames with the alias table in the reference.
3. **Date the evening.** The book header says `Kegelabend am: dd.mm.yy`. A
   Zettel usually has no date; evenings are every four weeks on a Friday, so
   infer the slot from the previous evening and say so. If the inferred date
   could be wrong, enter it anyway (relabeling one header is cheap) and name
   the assumption prominently in the reply.
4. **Map amounts to categories honestly.** Zettel often list money, not
   categories ("5 €, 0,5 €"). Pick the most frequent matching category
   (historically: 5 € → Vergessen (Pin), 0,50 € → Schimpfwörter, 2 € → Kugel
   aus der Bahn, 1 € → Rinne 1EUR) and attach a cell comment naming the
   alternatives. Amounts the price list cannot express (10-ct Rinnen) go into
   the Notizen cell with the exact figures, never into a wrong row.
5. **Write the spec and enter it.** Everyone present goes under `players`
   (an empty object for a present player without penalties); everyone else
   gets the absence Pauschale automatically, because that is the sheet's
   convention for all evenings since 08/2025. New players go into
   `new_players`; use `no_pauschale` only when the user says a player does not
   owe it. Run `add_evening.py SPEC.json --dry-run`, read the plan, then
   `--out <scratch>/new.xlsx`. The original is never written by the scripts.
6. **Recalculate and verify.** Recalculate the output with the
   `xlsx-recalc-nixos` skill (`add_evening` leaves formulas uncached). Then
   `verify_evening.py new.xlsx --date … --diff <original>`: it prints every
   player's entries and prices for the evening, the Summe Kegeln, notes and
   comments, and lists any changed cell outside the evening's columns (a
   new player block shows up as an expected row shift). Zero unexpected
   changes is the bar.
7. **Install.** Copy the verified file over the original only after keeping a
   backup (`.bak.xlsx` exists; Nextcloud also versions). Then refresh the
   statistics tab if one exists (see below), recalc and verify again.
8. **Report.** State per player what was entered, the evening's Summe
   Kegeln, the date used, and a bullet list of assumptions (with the cell
   each one lives in). The user corrects from that list, so make it complete
   and short.

## Spec format

```json
{
  "date": "2026-11-06",
  "source": "Buch S. 97",
  "players": {
    "John":  {"Schimpfwörter": 2, "Kugel aus der Bahn": 1},
    "Fochi": {"pin": 1},
    "Lucky": {}
  },
  "comments": {"John/Kugel aus der Bahn": "Strich auf der Zeilengrenze Kugel/Taxi, Kugel angenommen"},
  "new_players": ["Sven"],
  "no_pauschale": [],
  "note": "Nur 2 Spiele: Paddy 8, Timo 7. Oben notiert: 'Marius 20 Euro'."
}
```

Categories accept short forms (`pin`, `kugel`, `handy`, `leine`, `taxi`,
`rinne 50`, `rinne 1`, `pauschale`, …); players accept book nicknames.

## Statistics tab

`build_stats.py --out … [--from DATE --to DATE] [--name …] [--title …]`
rebuilds a formula-only tab (Kennzahlen, Könige, a Kegler table with
attendance and per-category totals, a Kegelabende table, helper matrices).
Period defaults to every dated column pair; seasons run from one
Jahreshauptversammlung to the next (last JHV: 18.07.2025). Attendance derives
from the Pauschale convention plus a blue `aktiv ab` input column (a player
counts from the first evening with any entry; override with
`--active-from Name=YYYY-MM-DD`). After rebuilding, recalc and spot-check a
few numbers against values you compute independently with openpyxl — a
clean recalc only proves the formulas evaluate.

## Things that have gone wrong before

- Entering 0 for a present player hides them from attendance; leave the cell
  empty and mention them in the Notizen instead.
- The printed book says Taxipauschale 3 €; the price list says 5 €. The sheet
  wins, say it in the report when it matters.
- `D3` is a text date; every other header is a real date. The scripts parse
  both; hand-written formulas must too.
- The anthropic xlsx skill's recalc.py fails on this host (read-only
  LibreOffice profile) — always use `xlsx-recalc-nixos`.
- Nextcloud sync can lag; check the file's mtime before and after writing,
  and never leave the workbook with uncached formulas (the previews go blank).

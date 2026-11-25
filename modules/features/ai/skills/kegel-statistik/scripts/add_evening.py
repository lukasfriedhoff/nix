#!/usr/bin/env python3
"""Enter one Kegelabend into the Kegel-Statistik workbook from a JSON spec.

Usage:
    python3 add_evening.py SPEC.json --out OUT.xlsx [--workbook PATH] [--dry-run]

The original workbook is never modified; the result goes to --out (recalculate
it afterwards, verify, then copy it over the original keeping a backup).

Spec (JSON):
{
  "date": "2026-11-06",                     # ISO or dd.mm.yyyy; picks/creates the column pair
  "source": "Buch S. 97",                   # free text, goes into the Notizen cell
  "players": {                              # everyone who was PRESENT, with their penalties
    "John":  {"Schimpfwörter": 2, "Kugel aus der Bahn": 1},
    "Lucky": {}                             # present, nothing bookable
  },
  "comments": {"John/Kugel aus der Bahn": "Strich liegt auf der Zeilengrenze …"},
  "new_players": ["Sven"],                  # blocks appended before Summe Kegeln (if missing)
  "no_pauschale": ["Sven"],                 # absent players who should NOT get the 10 € Pauschale
  "note": "free text appended to the Notizen cell",
  "author": "Übertrag Buch (2026-11-10)"    # comment author (optional)
}

Player names accept the book nicknames (Fochi, Luchy, Schenho, Schlauti, …);
penalty names accept short forms (pin, kugel, handy, taxi, rinne 50, …).
Absent = every known player not listed under "players" -> Strafen Pauschale = 1,
which is the sheet's convention (verified over every evening since 08/2025).
"""

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

from kegel_lib import (
    DEFAULT_PRICE_SHEET,
    DEFAULT_SHEET,
    DEFAULT_WORKBOOK,
    PAUSCHALE,
    add_player_block,
    clone_pair,
    load,
    norm,
    parse_date,
    set_count,
    write_note,
)
from openpyxl.utils import get_column_letter as L


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("spec")
    ap.add_argument("--workbook", default=str(DEFAULT_WORKBOOK))
    ap.add_argument("--out", help="output path (required unless --dry-run)")
    ap.add_argument("--sheet", default=DEFAULT_SHEET)
    ap.add_argument("--price-sheet", default=DEFAULT_PRICE_SHEET)
    ap.add_argument("--dry-run", action="store_true", help="print the planned writes, save nothing")
    a = ap.parse_args()
    if not a.dry_run and not a.out:
        ap.error("--out is required (the original is never written)")
    if a.out and Path(a.out).resolve() == Path(a.workbook).resolve():
        ap.error("--out must differ from --workbook")

    spec = json.loads(Path(a.spec).read_text())
    date = parse_date(spec["date"])
    if not date:
        sys.exit(f"unparseable date {spec['date']!r}")
    author = spec.get("author") or f"Übertrag ({dt.date.today().isoformat()})"
    wb, lay = load(a.workbook, a.sheet, a.price_sheet)
    plan = []
    new_names = {norm(n): n for n in spec.get("new_players", [])}

    def canon(player):
        """Sheet name for a (nick)name; in a dry run new players have no block yet."""
        try:
            return lay.canonical_player(player)
        except KeyError:
            if a.dry_run and norm(player) in new_names:
                return new_names[norm(player)]
            raise

    # 1. new players
    for name in spec.get("new_players", []):
        try:
            lay.block_row(name)
            plan.append(f"player {name!r} already exists - nothing added")
        except KeyError:
            if not a.dry_run:
                row = add_player_block(lay, name)
                plan.append(f"added player block {name!r} at row {row}")
            else:
                plan.append(f"would add player block {name!r} after {lay.blocks[-1][0]!r}")

    # 2. column pair for the date
    col = lay.pair_for_date(date)
    if col is None:
        last = lay.last_dated_pair()
        last_date = lay.date_of_pair(last) if last else None
        if last_date and date < last_date:
            sys.exit(
                f"{date.date()} lies before the last evening {last_date.date()} and has no column; "
                "add the header date manually or pick the right empty pair first"
            )
        col = lay.next_free_pair()
        if col not in [c for c, _ in lay.pairs]:
            if not a.dry_run:
                clone_pair(lay, lay.pairs[-1][0], col)
            plan.append(f"cloned pair {L(lay.pairs[-1][0])}/{L(lay.pairs[-1][0] + 1)} -> {L(col)}/{L(col + 1)}")
        if not a.dry_run:
            lay.ws.cell(3, col).value = date
            lay.ws.cell(3, col).number_format = lay.ws.cell(3, lay.pairs[0][0] + 2).number_format
        plan.append(f"header {L(col)}3 = {date.date()}")
    else:
        if lay.pair_has_data(col):
            sys.exit(f"pair {L(col)} ({date.date()}) already holds data - refusing to overwrite")
        plan.append(f"using existing empty pair {L(col)}/{L(col + 1)} dated {date.date()}")

    # 3. penalties of present players
    present = set()
    comments = {f"{norm(k.split('/')[0])}/{norm(k.split('/')[1])}": v for k, v in spec.get("comments", {}).items()}
    for player, pens in spec.get("players", {}).items():
        name = canon(player)
        present.add(norm(name))
        for label, n in (pens or {}).items():
            if not n:
                continue
            key = f"{norm(player)}/{norm(label)}"
            cm = comments.pop(key, None) or comments.pop(f"{norm(name)}/{norm(label)}", None)
            label_txt = lay.labels[lay.pen_index(label)]
            if a.dry_run and norm(name) in new_names and norm(name) not in [norm(b) for b, _ in lay.blocks]:
                plan.append(f"{L(col)}(new block): {name} / {label_txt} = {n}" + ("  [comment]" if cm else ""))
                continue
            r = lay.pen_row(name, label)
            plan.append(f"{L(col)}{r}: {name} / {label_txt} = {n}" + ("  [comment]" if cm else ""))
            if not a.dry_run:
                set_count(lay, col, name, label, n, cm, author)
    if comments:
        sys.exit(f"comments without a matching player/penalty entry: {list(comments)}")

    # 4. Pauschale for absentees
    skip = {norm(canon(p)) for p in spec.get("no_pauschale", [])}
    for name, _ in lay.blocks:
        if norm(name) in present or norm(name) in skip:
            continue
        r = lay.pen_row(name, PAUSCHALE)
        plan.append(f"{L(col)}{r}: {name} / {PAUSCHALE} = 1 (abwesend)")
        if not a.dry_run:
            set_count(lay, col, name, PAUSCHALE, 1)
    for p in skip:
        plan.append(f"no Pauschale for {p} (per spec)")

    # 5. note
    parts = []
    if spec.get("source"):
        parts.append(f"{spec['source']}, Kegelabend {date.strftime('%d.%m.%Y')}.")
    names = ", ".join(canon(p) for p in spec.get("players", {}))
    if names:
        parts.append(f"Anwesend: {names}.")
    if spec.get("note"):
        parts.append(spec["note"])
    if parts:
        plan.append(f"Notizen {L(col)}{lay.notes_row}: {' '.join(parts)[:80]}…")
        if not a.dry_run:
            write_note(lay, col, " ".join(parts))

    print("\n".join(plan))
    if a.dry_run:
        print("\n(dry run - nothing saved)")
        return
    wb.save(a.out)
    print(f"\nsaved {a.out}  (pair {L(col)}/{L(col + 1)}; recalculate + verify before installing)")


if __name__ == "__main__":
    main()

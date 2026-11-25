#!/usr/bin/env python3
"""Show what a column pair computes to, and diff a workbook against the original.

Usage:
    python3 verify_evening.py OUT.xlsx --date 2026-11-06 [--diff ORIGINAL.xlsx]
    python3 verify_evening.py OUT.xlsx --last

Needs cached values: run the recalc first, otherwise every price shows None.
--diff lists every changed cell outside the evening's column pair (a block
insertion shows up as a row shift and is reported as such).
"""

import argparse
import sys

import openpyxl
from kegel_lib import BLOCK_ROWS, DEFAULT_PRICE_SHEET, DEFAULT_SHEET, Layout, load, parse_date
from openpyxl.utils import get_column_letter as L


def show(path, sheet, price_sheet, col):
    wbv, lay = load(path, sheet, price_sheet, data_only=True)
    ws = lay.ws
    d = lay.date_of_pair(col)
    print(f"=== {L(col)}/{L(col + 1)}  {d.date() if d else '(no date)'}")
    total = 0
    for name, b in lay.blocks:
        items = []
        for i in range(len(lay.labels)):
            n = ws.cell(b + 1 + i, col).value
            if n:
                items.append(f"{lay.labels[i]}={n} ({ws.cell(b + 1 + i, col + 1).value} €)")
        s = ws.cell(b + BLOCK_ROWS - 1, col + 1).value
        total += s or 0
        print(f"  {name:12s} {s if s is not None else 'None':>7} | " + "; ".join(items))
    print(f"  Summe Kegeln: {lay.summe_kegeln(col)}   (blocks add up to {total})")
    note = ws.cell(lay.notes_row, col).value
    if note:
        print(f"  Notizen: {note}")
    wbf = openpyxl.load_workbook(path)
    wsf = wbf[sheet]
    cms = [(c.coordinate, c.comment.text) for row in wsf.iter_rows(min_col=col, max_col=col) for c in row if c.comment]
    for coord, text in cms:
        print(f"  comment {coord}: {text}")
    if lay.summe_kegeln(col) is None:
        print("  !! cached values missing - recalculate first (xlsx-recalc-nixos)")


def diff(orig, new, sheet, price_sheet, skip_cols):
    a = openpyxl.load_workbook(orig)
    b = openpyxl.load_workbook(new)
    la, lb = Layout(a, sheet, price_sheet), Layout(b, sheet, price_sheet)
    shift_from, shift = None, lb.sum_row - la.sum_row
    if shift:
        shift_from = la.sum_row - 1
        print(f"  rows >= {shift_from} shifted by {shift} (player block inserted)")
    problems = []
    for name in a.sheetnames:
        wa, wb_ = a[name], b[name]
        for row in wa.iter_rows():
            for c in row:
                if name == sheet and c.column in skip_cols:
                    continue
                r2 = c.row + shift if (shift and c.row >= shift_from) else c.row
                v2 = wb_.cell(r2, c.column).value
                if c.value != v2:
                    if name == sheet and c.row == la.sum_row and isinstance(c.value, str) and isinstance(v2, str) \
                            and v2.startswith(c.value[:-1]):
                        continue  # Summe Kegeln extended by the new block
                    problems.append((name, c.coordinate, c.value, v2))
    print(f"  diff vs original outside {[L(c) for c in skip_cols]}: {len(problems)} unexpected change(s)")
    for p in problems[:20]:
        print("   ", p)
    return not problems


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("workbook")
    ap.add_argument("--date")
    ap.add_argument("--last", action="store_true")
    ap.add_argument("--diff", help="original workbook to compare against")
    ap.add_argument("--sheet", default=DEFAULT_SHEET)
    ap.add_argument("--price-sheet", default=DEFAULT_PRICE_SHEET)
    a = ap.parse_args()
    _, lay = load(a.workbook, a.sheet, a.price_sheet)
    if a.date:
        col = lay.pair_for_date(parse_date(a.date))
        if col is None:
            sys.exit(f"no column pair dated {a.date}")
    else:
        col = lay.last_dated_pair()
    show(a.workbook, a.sheet, a.price_sheet, col)
    ok = True
    if a.diff:
        ok = diff(a.diff, a.workbook, a.sheet, a.price_sheet, {col, col + 1})
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Print the discovered layout of the Kegel-Statistik workbook.

Usage: python3 inspect_workbook.py [--workbook PATH] [--sheet NAME]
Shows sheets, player blocks, column pairs with dates / data flags / Summe
Kegeln (cached values, None if the file was never recalculated), the price
list, and which column pair the next evening would use.
"""

import argparse

from kegel_lib import DEFAULT_PRICE_SHEET, DEFAULT_SHEET, DEFAULT_WORKBOOK, Layout, load
from openpyxl.utils import get_column_letter as L


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workbook", default=str(DEFAULT_WORKBOOK))
    ap.add_argument("--sheet", default=DEFAULT_SHEET)
    ap.add_argument("--price-sheet", default=DEFAULT_PRICE_SHEET)
    a = ap.parse_args()
    wb, lay = load(a.workbook, a.sheet, a.price_sheet)
    wbv, layv = load(a.workbook, a.sheet, a.price_sheet, data_only=True)
    print(f"workbook: {a.workbook}")
    print(f"sheets: {wb.sheetnames}")
    print(f"sheet {a.sheet!r}: dims {lay.ws.dimensions}, merged ranges {len(lay.ws.merged_cells.ranges)}")
    print(f"Summe Kegeln row {lay.sum_row}, Notizen rows {lay.notes_row}-{lay.notes_end}")
    print("\nplayer blocks (name row; penalties +1..+17; Summe +18):")
    for name, row in lay.blocks:
        print(f"  {name:12s} row {row}")
    print("\npenalties (index: label = price):")
    for i, (lab, price) in enumerate(zip(lay.labels, lay.prices)):
        print(f"  {i:2d}: {lab!r} = {price}")
    print("\ncolumn pairs:")
    for c, p in lay.pairs:
        d = lay.date_of_pair(c)
        note = layv.ws.cell(lay.notes_row, c).value
        ds = str(d.date()) if d else "-"
        print(
            f"  {L(c) + '/' + L(p):7s} date {ds:10s}  data {'yes' if lay.pair_has_data(c) else 'no ':3}"
            f"  Summe Kegeln {layv.summe_kegeln(c)!s:>7}  note {'yes' if note else '-'}"
        )
    nxt = lay.next_free_pair()
    exists = any(c == nxt for c, _ in lay.pairs)
    print(f"\nnext evening -> pair {L(nxt)}/{L(nxt + 1)} ({'exists, empty' if exists else 'will be cloned from the last pair'})")


if __name__ == "__main__":
    main()

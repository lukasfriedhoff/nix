#!/usr/bin/env python3
"""(Re)build the formula-driven statistics tab for a range of Kegelabende.

Usage:
    python3 build_stats.py --out OUT.xlsx [--workbook PATH] [--name "Statistik seit JHV 2025"]
        [--title "..."] [--from 2025-08-15] [--to 2026-12-31] [--active-from Marius=2026-09-11 ...]

The tab is formulas only (SUMIF over the source sheet), so later edits of the
source flow in automatically. An existing tab with the same name is replaced.
Layout: Kennzahlen + Könige, Kegler table (one row per block, blue 'aktiv ab'
input column), Kegelabende table (one row per column pair in range), and two
helper matrices feeding the per-evening kings. Column pairs in range must be
contiguous (they are, unless someone reorders the sheet).
"""

import argparse
import datetime as dt
import sys

from kegel_lib import BLOCK_ROWS, DEFAULT_PRICE_SHEET, DEFAULT_SHEET, DEFAULT_WORKBOOK, N_PEN, PAUSCHALE, load, parse_date
from openpyxl.comments import Comment
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter as L

EUR = "#,##0.00\\ [$€-407];[RED]\\-#,##0.00\\ [$€-407]"
DATE = "[$-407]dd/mm/yyyy"
F_BODY = Font(name="Calibri", size=11)
F_B = Font(name="Calibri", size=11, bold=True)
F_H = Font(name="Calibri", size=12, bold=True)
F_T = Font(name="Calibri", size=14, bold=True)
F_IN = Font(name="Calibri", size=11, color="0000FF")
F_NOTE = Font(name="Calibri", size=10, italic=True)
FILL_H = PatternFill("solid", fgColor="F2F2F2")
BOT = Border(bottom=Side(style="thin"))
CENTER_WRAP = Alignment(wrap_text=True, vertical="center", horizontal="center")

# stats column per penalty index (index into the price list); R = Rinnen gesamt
CAT_COLS = {4: "K", 5: "L", 6: "M", 7: "N", 8: "O", 12: "P", 13: "Q", 3: "S", 2: "T", 1: "U", 0: "V",
            9: "W", 10: "X", 11: "Y", 15: "Z", 16: "AA"}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--workbook", default=str(DEFAULT_WORKBOOK))
    ap.add_argument("--out", required=True)
    ap.add_argument("--sheet", default=DEFAULT_SHEET)
    ap.add_argument("--price-sheet", default=DEFAULT_PRICE_SHEET)
    ap.add_argument("--name", default="Statistik seit JHV 2025")
    ap.add_argument("--title", default="KC DKKN – Statistik seit der Jahreshauptversammlung am 18.07.2025")
    ap.add_argument("--from", dest="from_", help="first evening date to include (default: first dated pair)")
    ap.add_argument("--to", help="last evening date to include (default: last dated pair)")
    ap.add_argument("--active-from", action="append", default=[], metavar="PLAYER=DATE",
                    help="override when a player starts counting (default: first evening with any entry)")
    a = ap.parse_args()

    wb, lay = load(a.workbook, a.sheet, a.price_sheet)
    S = f"'{a.sheet}'"
    P = f"'{a.price_sheet}'"
    lo = parse_date(a.from_) if a.from_ else None
    hi = parse_date(a.to) if a.to else None
    sel = [(c, p, lay.date_of_pair(c)) for c, p in lay.pairs if lay.date_of_pair(c)]
    sel = [(c, p, d) for c, p, d in sel if (not lo or d >= lo) and (not hi or d <= hi)]
    if not sel:
        sys.exit("no dated column pairs in range")
    for (c1, _, _), (c2, _, _) in zip(sel, sel[1:]):
        if c2 != c1 + 2:
            sys.exit("selected column pairs are not contiguous")
    first_c, last_c = sel[0][0], sel[-1][0] + 1
    NE, NP = len(sel), len(lay.blocks)
    first_d, last_d = sel[0][2], sel[-1][2]

    # active-from: first evening with any entry per block, overridable
    active = {}
    for name, b in lay.blocks:
        start = None
        for c, _, d in sel:
            if any(isinstance(lay.ws.cell(b + 1 + i, c).value, (int, float)) and lay.ws.cell(b + 1 + i, c).value
                   for i in range(N_PEN)):
                start = d
                break
        active[name] = start or first_d
    for ov in a.active_from:
        k, v = ov.split("=", 1)
        active[lay.canonical_player(k)] = parse_date(v)

    if a.name in wb.sheetnames:
        del wb[a.name]
    ws = wb.create_sheet(a.name)

    def put(cell, v, font=F_BODY, fmt=None, align=None, fill=None, border=None):
        c = ws[cell]
        c.value = v
        c.font = font
        if fmt:
            c.number_format = fmt
        if align:
            c.alignment = align
        if fill:
            c.fill = fill
        if border:
            c.border = border
        return c

    def header(row, labels, start_col=1):
        for j, lbl in enumerate(labels):
            put(f"{L(start_col + j)}{row}", lbl, F_B, fill=FILL_H, border=BOT, align=CENTER_WRAP)
        ws.row_dimensions[row].height = 45

    def rng(col, r1, r2):
        return f"${col}${r1}:${col}${r2}"

    def lab(i):
        return f"{P}!$A${2 + i}"

    # row bookkeeping
    PH, P0 = 15, 16
    P1, PT = P0 + NP - 1, P0 + NP
    EH, E0 = PT + 3, PT + 4
    E1, ET = E0 + NE - 1, E0 + NE
    H1T, H1H, H10 = ET + 3, ET + 4, ET + 5
    H11 = H10 + NP - 1
    H2T, H2H, H20 = H11 + 2, H11 + 3, H11 + 4
    H21 = H20 + NP - 1
    evB, evD, evF = f"$B${E0}:$B${E1}", f"$D${E0}:$D${E1}", f"$F${E0}:$F${E1}"
    H4 = f"{S}!${L(first_c)}$4:${L(last_c)}$4"
    CNT, PRC = f"{S}!${L(first_c)}$4", f"{S}!${L(first_c + 1)}$4"
    PAUSCH = f"{S}!$B${lay.blocks[0][1] + 1 + lay.pauschale_idx}"
    A5 = f"{S}!$A$5:$A${lay.blocks[-1][1] + N_PEN}"
    names = rng("A", P0, P1)

    put("A1", a.title, F_T)
    put("A2", f"Zeitraum {first_d:%d.%m.%Y} – {last_d:%d.%m.%Y} = Kegelabende im Blatt {S} (Spalten {L(first_c)}–{L(last_c)}). "
              f"Alle Werte sind Formeln; Änderungen im Quellblatt fließen automatisch ein. Erstellt {dt.date.today():%d.%m.%Y}.", F_NOTE)

    # Kennzahlen + Könige
    put("A4", "Kennzahlen gesamt", F_H)
    put("D4", "Könige & Rekorde (bei Gleichstand: erster Kegler der Liste)", F_H)
    kpis = [("Kegelabende mit Daten", f'=COUNTIF({evF},">0")', "0"),
            ("Ø Anwesende je Kegelabend", f'=IF(B5>0,SUMIF({evF},">0",{evD})/B5,0)', "0.0"),
            ("Einnahmen gesamt (inkl. Pauschale)", f"=SUM({evF})", EUR),
            ("davon Strafen Pauschale (Abwesenheit)", f"=SUM({rng('G', E0, E1)})", EUR),
            ("Strafen ohne Pauschale", f"=SUM({rng('H', E0, E1)})", EUR),
            ("Schimpfwörter gesamt", f"=SUM({rng('I', E0, E1)})", "0"),
            ("Rinnen gesamt (1 € + 50 ct)", f"=SUM({rng('J', E0, E1)})", "0"),
            ("Kugel aus der Bahn gesamt", f"=SUM({rng('K', E0, E1)})", "0")]
    for j, (l, f, fmt) in enumerate(kpis):
        put(f"A{5 + j}", l)
        put(f"B{5 + j}", f, fmt=fmt)

    def king(col):
        r = rng(col, P0, P1)
        return f'=IF(MAX({r})>0,INDEX({names},MATCH(MAX({r}),{r},0)),"–")', f"=MAX({r})"

    kings = [("Schimpfwort-König", "K", "0", "Schimpfwörter"), ("Rinnen-König", "R", "0", "Rinnen"),
             ("Teuerster Kegler (ohne Pauschale)", "I", EUR, ""), ("Beste Anwesenheit", "D", "0", "Abende anwesend"),
             ("Meiste Fehltage", "E", "0", "Abende"), ("Kugel-aus-der-Bahn-König", "O", "0", "Kugeln"),
             ("Handy-König", "N", "0", "Handy Nutzung")]
    for j, (l, col, fmt, unit) in enumerate(kings):
        f1, f2 = king(col)
        put(f"D{5 + j}", l)
        put(f"E{5 + j}", f1, F_B)
        put(f"F{5 + j}", f2, fmt=fmt)
        put(f"G{5 + j}", unit, F_NOTE)
    put("A13", "Regeln: Abwesend = „Strafen Pauschale“ eingetragen (10 €). Anwesend = mögliche Abende − Abwesend. "
               "Mögliche Abende = Abende mit Daten ab dem Datum in Spalte „aktiv ab“ (blaue Eingabezellen). "
               "Abende ohne Daten zählen nicht.", F_NOTE)

    # Kegler table
    put(f"A{PH - 1}", "Kegler", F_H)
    header(PH, ["Kegler", "aktiv ab", "Abende möglich", "Anwesend", "Abwesend (Pauschale)", "Anwesenheit",
                "Strafen gesamt €", "davon Pauschale €", "Strafen ohne Pauschale €", "Ø € je Abend (anwesend)"])
    for i, col in CAT_COLS.items():
        put(f"{col}{PH}", f"={lab(i)}", F_B, fill=FILL_H, border=BOT, align=CENTER_WRAP)
    for col, text in (("R", "Rinnen gesamt"), ("AB", "Rang € (ohne Pauschale)"), ("AC", "Rang Schimpfwörter")):
        put(f"{col}{PH}", text, F_B, fill=FILL_H, border=BOT, align=CENTER_WRAP)
    ws[f"B{PH}"].comment = Comment("Eingabe: ab diesem Datum zählt der Kegler mit. Abende davor werden weder als "
                                   "anwesend noch als Fehltag gezählt.", "Statistik")
    for n, (name, b) in enumerate(lay.blocks):
        r = P0 + n
        pa, su = b + 1 + lay.pauschale_idx, b + BLOCK_ROWS - 1
        put(f"A{r}", f"={S}!$A${b}", F_B)
        put(f"B{r}", active[name], F_IN, fmt=DATE)
        put(f"C{r}", f'=COUNTIFS({evB},">="&B{r},{evF},">0")', fmt="0")
        put(f"D{r}", f"=C{r}-E{r}", fmt="0")
        put(f"E{r}", f"=SUMIF({H4},{CNT},{S}!${L(first_c)}${pa}:${L(last_c)}${pa})", fmt="0")
        put(f"F{r}", f"=IF(C{r}>0,D{r}/C{r},0)", fmt="0%")
        put(f"G{r}", f"=SUMIF({H4},{PRC},{S}!${L(first_c)}${su}:${L(last_c)}${su})", fmt=EUR)
        put(f"H{r}", f"=E{r}*{PAUSCH}", fmt=EUR)
        put(f"I{r}", f"=G{r}-H{r}", fmt=EUR)
        put(f"J{r}", f"=IF(D{r}>0,I{r}/D{r},0)", fmt=EUR)
        for i, col in CAT_COLS.items():
            rr = b + 1 + i
            put(f"{col}{r}", f"=SUMIF({H4},{CNT},{S}!${L(first_c)}${rr}:${L(last_c)}${rr})", fmt="0")
        put(f"R{r}", f"=P{r}+Q{r}", fmt="0")
        put(f"AB{r}", f"=RANK(I{r},{rng('I', P0, P1)},0)", fmt="0")
        put(f"AC{r}", f"=RANK(K{r},{rng('K', P0, P1)},0)", fmt="0")
    put(f"A{PT}", "Summe", F_B, border=BOT)
    for col in ["C", "D", "E", "G", "H", "I"] + list(CAT_COLS.values()) + ["R"]:
        put(f"{col}{PT}", f"=SUM({rng(col, P0, P1)})", F_B, fmt=(EUR if col in ("G", "H", "I") else "0"), border=BOT)
    put(f"F{PT}", f"=IF(C{PT}>0,D{PT}/C{PT},0)", F_B, fmt="0%", border=BOT)
    put(f"J{PT}", f"=IF(D{PT}>0,I{PT}/D{PT},0)", F_B, fmt=EUR, border=BOT)

    # Kegelabende table
    put(f"A{EH - 1}", "Kegelabende", F_H)
    header(EH, ["Nr", "Datum", "Daten vorhanden", "Anwesend", "Abwesend (Pauschale)", "Strafen gesamt €",
                "davon Pauschale €", "Strafen ohne Pauschale €", "Schimpfwörter", "Rinnen (1 € + 50 ct)",
                "Kugel aus der Bahn", "Teuerster Kegler (ohne Pauschale)", "Betrag €", "Schimpfwort-König des Abends",
                "Schimpfwörter"])
    for k, (c, p, _) in enumerate(sel):
        r, hc = E0 + k, L(2 + k)
        d = f"{S}!{L(c)}$3"
        cnt = f"{S}!{L(c)}$5:{L(c)}${lay.blocks[-1][1] + N_PEN}"
        put(f"A{r}", k + 1, fmt="0")
        put(f"B{r}", f"=IF(ISNUMBER({d}),{d},DATE(VALUE(MID({d},7,4)),VALUE(MID({d},4,2)),VALUE(LEFT({d},2))))", fmt=DATE)
        put(f"C{r}", f'=IF(F{r}>0,"ja","nein")', align=Alignment(horizontal="center"))
        put(f"D{r}", f'=IF(F{r}>0,COUNTIF({rng("B", P0, P1)},"<="&B{r})-E{r},0)', fmt="0")
        put(f"E{r}", f"=SUMIF({A5},{lab(lay.pauschale_idx)},{cnt})", fmt="0")
        put(f"F{r}", f"={S}!{L(p)}${lay.sum_row}", fmt=EUR)
        put(f"G{r}", f"=E{r}*{PAUSCH}", fmt=EUR)
        put(f"H{r}", f"=F{r}-G{r}", fmt=EUR)
        put(f"I{r}", f"=SUMIF({A5},{lab(lay.pen_index('Schimpfwörter'))},{cnt})", fmt="0")
        put(f"J{r}", f"=SUMIF({A5},{lab(lay.pen_index('Rinne 1EUR'))},{cnt})+SUMIF({A5},{lab(lay.pen_index('Rinne 50ct'))},{cnt})", fmt="0")
        put(f"K{r}", f"=SUMIF({A5},{lab(lay.pen_index('Kugel aus der Bahn'))},{cnt})", fmt="0")
        put(f"M{r}", f"=MAX({rng(hc, H10, H11)})", fmt=EUR)
        put(f"L{r}", f'=IF(M{r}>0,INDEX({rng("A", H10, H11)},MATCH(M{r},{rng(hc, H10, H11)},0)),"–")')
        put(f"O{r}", f"=MAX({rng(hc, H20, H21)})", fmt="0")
        put(f"N{r}", f'=IF(O{r}>0,INDEX({rng("A", H20, H21)},MATCH(O{r},{rng(hc, H20, H21)},0)),"–")')
    put(f"A{ET}", "Summe", F_B, border=BOT)
    for col in ["D", "E", "F", "G", "H", "I", "J", "K"]:
        put(f"{col}{ET}", f"=SUM({rng(col, E0, E1)})", F_B, fmt=(EUR if col in ("F", "G", "H") else "0"), border=BOT)

    # helper matrices
    put(f"A{H1T}", "Hilfstabelle 1: Strafen ohne Pauschale je Kegler und Abend (€)", F_H)
    put(f"A{H2T}", "Hilfstabelle 2: Schimpfwörter je Kegler und Abend", F_H)
    schimpf = lay.pen_index("Schimpfwörter")
    for hh, h0, kind in ((H1H, H10, "eur"), (H2H, H20, "cnt")):
        put(f"A{hh}", "Kegler", F_B, fill=FILL_H, border=BOT)
        for k in range(NE):
            put(f"{L(2 + k)}{hh}", f"=B{E0 + k}", F_B, fmt=DATE, fill=FILL_H, border=BOT, align=Alignment(horizontal="center"))
        for n, (name, b) in enumerate(lay.blocks):
            r = h0 + n
            put(f"A{r}", f"=A{P0 + n}")
            for k, (c, p, _) in enumerate(sel):
                if kind == "eur":
                    put(f"{L(2 + k)}{r}", f"={S}!{L(p)}${b + BLOCK_ROWS - 1}-{S}!{L(c)}${b + 1 + lay.pauschale_idx}*{PAUSCH}", fmt=EUR)
                else:
                    put(f"{L(2 + k)}{r}", f"={S}!{L(c)}${b + 1 + schimpf}", fmt="0")

    widths = {"A": 34, "B": 13, "C": 11, "D": 11, "E": 12, "F": 13, "G": 14, "H": 14, "I": 14, "J": 13, "K": 12, "L": 12,
              "M": 12, "N": 12, "O": 12, "P": 10, "Q": 10, "R": 10, "S": 11, "T": 11, "U": 14, "V": 11, "W": 11, "X": 10,
              "Y": 11, "Z": 9, "AA": 9, "AB": 11, "AC": 11}
    for c, w in widths.items():
        ws.column_dimensions[c].width = w
    ws.freeze_panes = "B1"
    ws.sheet_view.zoomScale = 90
    wb.save(a.out)
    print(f"saved {a.out}: tab {a.name!r}, {NE} evenings ({first_d:%d.%m.%Y}–{last_d:%d.%m.%Y}), {NP} players; "
          f"player rows {P0}-{P1}, evening rows {E0}-{E1}. Recalculate before use.")
    for name, d in active.items():
        if d != first_d:
            print(f"  aktiv ab {name}: {d:%d.%m.%Y}")


if __name__ == "__main__":
    main()

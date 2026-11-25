"""Shared helpers for the KC DKKN Kegel-Statistik workbook.

Layout (sheet 'Lukas - Statistik ab 15.08.2025'):
  row 3   : evening date per column pair (merged over the pair; D3 may be TEXT 'dd.mm.yyyy')
  row 4   : 'Anzahl Strafen ' / 'Strafen Preis €' headers (repeated in every block's name row)
  blocks  : one per player, 19 rows: name row, 17 penalty rows (same order as the
            price sheet A2..A18), 'Summe Strafen:' row
  'Summe Kegeln:' row, then merged Notizen cells (one per pair) below it
  columns : pairs (count, price) starting at D/E; price = count * $B<row>

Everything here discovers rows/columns from the sheet instead of hardcoding
them, so adding players or evenings keeps working.
"""

import copy
import datetime as dt
import os
import re
import subprocess
import sys
from pathlib import Path

import openpyxl
from openpyxl.cell.cell import MergedCell
from openpyxl.comments import Comment
from openpyxl.formula.translate import Translator
from openpyxl.styles import Alignment
from openpyxl.utils import get_column_letter as L

DEFAULT_WORKBOOK = Path.home() / "Nextcloud/Documents/kcdkkn/kasse/KC DKKN Statistik 24&25&26.xlsx"
DEFAULT_SHEET = "Lukas - Statistik ab 15.08.2025"
DEFAULT_PRICE_SHEET = "Lukas - Strafen ab 15.08.2025"
PAUSCHALE = "Strafen Pauschale"
N_PEN = 17
BLOCK_ROWS = N_PEN + 2  # name row + penalties + Summe Strafen

# Nicknames as they appear in the book / on Zettel -> sheet block names.
PLAYER_ALIASES = {
    "fochi": "Focki", "focki": "Focki",
    "luchy": "Lucky", "lucky": "Lucky",
    "schenho": "Schenko", "schenko": "Schenko", "schneko": "Schenko",
    "schlauti": "Schloti", "schloti": "Schloti",
    "lukas": "Lukas Fr.", "lukas fr.": "Lukas Fr.", "lukas fr": "Lukas Fr.",
    "robin": "Robin P.", "robin p.": "Robin P.", "robin p": "Robin P.",
    "schmelli": "Schmelzer", "schmelzer": "Schmelzer",
}

# Short category names -> labels in the price sheet (whitespace-normalised).
CATEGORY_ALIASES = {
    "pin": "vergessen (pin)",
    "shirt": "vergessen (shirt)",
    "kutte": "vergessen (kutte, pudel oder buch)",
    "buch": "vergessen (kutte, pudel oder buch)",
    "vergessen": "vergessen (kutte, pudel oder buch)",
    "schimpfwort": "schimpfwörter", "schimpfworte": "schimpfwörter", "schimpfwörter": "schimpfwörter",
    "handy": "handy nutzung", "handy nutzung": "handy nutzung",
    "leine": "leine berührt", "leine berührt": "leine berührt",
    "kugel": "kugel aus der bahn", "kugel aus der bahn": "kugel aus der bahn",
    "taxi": "taxipauschale", "taxipauschale": "taxipauschale",
    "5er": "5 er spiel", "5er spiel": "5 er spiel", "5 er spiel": "5 er spiel",
    "kotzen": "auf die bahn kotzen",
    "rinne 1": "rinne 1eur", "rinne 1eur": "rinne 1eur", "rinne 1€": "rinne 1eur", "rinne 1 €": "rinne 1eur",
    "rinne 50": "rinne 50ct", "rinne 50ct": "rinne 50ct", "rinne 50 ct": "rinne 50ct",
    "pauschale": "strafen pauschale", "strafen pauschale": "strafen pauschale",
    "könig": "könig", "pudel": "pudel",
    "nicht abgestimmt": "nicht abgestimmt", "unachtsamkeit": "unachtsamkeit",
}


def norm(s) -> str:
    return re.sub(r"\s+", " ", str(s if s is not None else "")).strip().lower()


def parse_date(v):
    """Header cells are datetimes except D3 ('15.08.2025' as text)."""
    if isinstance(v, dt.datetime):
        return v
    if isinstance(v, dt.date):
        return dt.datetime(v.year, v.month, v.day)
    if isinstance(v, str):
        m = re.match(r"\s*(\d{1,2})\.(\d{1,2})\.(\d{4})\s*$", v)
        if m:
            return dt.datetime(int(m.group(3)), int(m.group(2)), int(m.group(1)))
        m = re.match(r"\s*(\d{4})-(\d{2})-(\d{2})", v)
        if m:
            return dt.datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    return None


class Layout:
    """Discovered geometry of the statistics sheet."""

    def __init__(self, wb, sheet=DEFAULT_SHEET, price_sheet=DEFAULT_PRICE_SHEET):
        self.wb = wb
        self.sheet = sheet
        self.price_sheet = price_sheet
        self.ws = wb[sheet]
        self.ps = wb[price_sheet]
        self.labels = [str(self.ps.cell(2 + i, 1).value) for i in range(N_PEN)]
        self.prices = [self.ps.cell(2 + i, 2).value for i in range(N_PEN)]
        self.refresh()

    def refresh(self):
        ws = self.ws
        self.blocks = []  # (name, name_row)
        self.sum_row = None
        r = 4
        while r <= ws.max_row:
            a, d = ws.cell(r, 1).value, ws.cell(r, 4).value
            if isinstance(a, str) and not a.startswith("=") and norm(d) == "anzahl strafen":
                self.blocks.append((a.strip(), r))
                r += BLOCK_ROWS
                continue
            if norm(d) == "summe kegeln:":
                self.sum_row = r
                break
            r += 1
        if self.sum_row is None:
            raise RuntimeError("could not find the 'Summe Kegeln:' row")
        self.notes_row = self.sum_row + 1
        self.notes_end = self.notes_row + 7
        for rng in ws.merged_cells.ranges:
            if rng.min_row == self.notes_row and rng.min_col == 4:
                self.notes_end = rng.max_row
        self.pairs = []
        c = 4
        while norm(ws.cell(4, c).value) == "anzahl strafen":
            self.pairs.append((c, c + 1))
            c += 2
        self.pauschale_idx = self.pen_index(PAUSCHALE)

    # ---- lookups -----------------------------------------------------
    def block_row(self, player: str) -> int:
        key = norm(player)
        key = norm(PLAYER_ALIASES.get(key, player))
        for name, row in self.blocks:
            if norm(name) == key:
                return row
        raise KeyError(f"unknown player {player!r}; known: {[n for n, _ in self.blocks]}")

    def canonical_player(self, player: str) -> str:
        key = norm(PLAYER_ALIASES.get(norm(player), player))
        for name, _ in self.blocks:
            if norm(name) == key:
                return name
        raise KeyError(f"unknown player {player!r}; known: {[n for n, _ in self.blocks]}")

    def pen_index(self, label: str) -> int:
        key = norm(label)
        key = CATEGORY_ALIASES.get(key, key)
        for i, lab in enumerate(self.labels):
            if norm(lab) == key:
                return i
        raise KeyError(f"unknown penalty {label!r}; known: {self.labels}")

    def pen_row(self, player: str, label: str) -> int:
        return self.block_row(player) + 1 + self.pen_index(label)

    def date_of_pair(self, c: int):
        return parse_date(self.ws.cell(3, c).value)

    def pair_has_data(self, c: int) -> bool:
        for _, b in self.blocks:
            for i in range(N_PEN):
                v = self.ws.cell(b + 1 + i, c).value
                if isinstance(v, (int, float)) and v:
                    return True
        return False

    def pair_for_date(self, date: dt.datetime):
        for c, _ in self.pairs:
            d = self.date_of_pair(c)
            if d and d.date() == date.date():
                return c
        return None

    def last_dated_pair(self):
        last = None
        for c, _ in self.pairs:
            if self.date_of_pair(c):
                last = c
        return last

    def next_free_pair(self):
        """First column pair after the last dated one (cloned on demand)."""
        last = self.last_dated_pair()
        return (last + 2) if last else 4

    def summe_kegeln(self, c: int):
        return self.ws.cell(self.sum_row, c + 1).value


# ---- mutations -----------------------------------------------------------
def _ensure_merge(ws, r1, c1, r2, c2):
    for rng in ws.merged_cells.ranges:
        if (rng.min_row, rng.min_col, rng.max_row, rng.max_col) == (r1, c1, r2, c2):
            return
    ws.merge_cells(start_row=r1, start_column=c1, end_row=r2, end_column=c2)


def clone_pair(lay: Layout, src_c: int, dst_c: int):
    """Copy a column pair (styles + translated formulas) and clear its data."""
    ws = lay.ws
    for r in range(1, lay.notes_end + 1):
        for off in (0, 1):
            s, d = ws.cell(r, src_c + off), ws.cell(r, dst_c + off)
            try:
                d._style = copy.copy(s._style)
            except Exception:
                pass
            if isinstance(d, MergedCell) or isinstance(s, MergedCell):
                continue
            v = s.value
            if isinstance(v, str) and v.startswith("="):
                v = Translator(v, origin=s.coordinate).translate_formula(d.coordinate)
            d.value = v
            d.comment = None
    ws.cell(3, dst_c).value = None
    for _, b in lay.blocks:
        for i in range(N_PEN):
            ws.cell(b + 1 + i, dst_c).value = None
    ws.cell(lay.notes_row, dst_c).value = None
    _ensure_merge(ws, 3, dst_c, 3, dst_c + 1)
    _ensure_merge(ws, lay.notes_row, dst_c, lay.notes_end, dst_c + 1)
    for off in (0, 1):
        ws.column_dimensions[L(dst_c + off)].width = ws.column_dimensions[L(src_c + off)].width
    lay.refresh()


def add_player_block(lay: Layout, name: str) -> int:
    """Append a player block before 'Summe Kegeln:', shifting the footer down."""
    ws = lay.ws
    shift = BLOCK_ROWS
    move_top = lay.sum_row - 1  # the blank spacer row above 'Summe Kegeln:'
    max_col = ws.max_column
    remerge = []
    for rng in list(ws.merged_cells.ranges):
        if rng.min_row >= move_top:
            remerge.append((rng.min_row + shift, rng.min_col, rng.max_row + shift, rng.max_col))
            ws.unmerge_cells(str(rng))
    heights = {r: ws.row_dimensions[r].height for r in range(move_top, lay.notes_end + 1)}
    ws.move_range(f"A{move_top}:{L(max_col)}{lay.notes_end}", rows=shift, cols=0, translate=False)
    for r1, c1, r2, c2 in remerge:
        ws.merge_cells(start_row=r1, start_column=c1, end_row=r2, end_column=c2)
    for r, h in heights.items():
        ws.row_dimensions[r + shift].height = h

    tpl_name, tpl = lay.blocks[-1]
    new = tpl + BLOCK_ROWS
    for i in range(BLOCK_ROWS):
        ws.row_dimensions[new + i].height = ws.row_dimensions[tpl + i].height
        for c in range(1, max_col + 1):
            s, d = ws.cell(tpl + i, c), ws.cell(new + i, c)
            if isinstance(d, MergedCell) or isinstance(s, MergedCell):
                continue
            d._style = copy.copy(s._style)
            d.value = None
            d.comment = None
    ws.cell(new, 1).value = name
    for i in range(N_PEN):
        ws.cell(new + 1 + i, 1).value = f"=A{5 + i}"
        ws.cell(new + 1 + i, 2).value = f"=B{5 + i}"
    for cc, pc in lay.pairs:
        ws.cell(new, cc).value = "Anzahl Strafen "
        ws.cell(new, pc).value = "Strafen Preis €"
        for i in range(N_PEN):
            r = new + 1 + i
            ws.cell(r, pc).value = f"={L(cc)}{r}*$B{r}"
        ws.cell(new + N_PEN + 1, cc).value = "Summe Strafen:"
        ws.cell(new + N_PEN + 1, pc).value = f"=SUM({L(pc)}{new + 1}:{L(pc)}{new + N_PEN})"
    sum_row = lay.sum_row + shift
    for cc, pc in lay.pairs:
        cell = ws.cell(sum_row, pc)
        f = cell.value
        if not (isinstance(f, str) and f.startswith("=SUM(") and f.endswith(")")):
            raise RuntimeError(f"unexpected Summe Kegeln formula at {cell.coordinate}: {f!r}")
        cell.value = f[:-1] + f",{L(pc)}{new + N_PEN + 1})"
    lay.refresh()
    return new


def make_comment(text: str, author: str) -> Comment:
    cm = Comment(text, author)
    cm.width, cm.height = 420, 160
    return cm


def set_count(lay: Layout, col: int, player: str, label: str, n, comment=None, author="Übertrag"):
    r = lay.pen_row(player, label)
    cell = lay.ws.cell(r, col)
    if cell.value not in (None, "", 0):
        raise ValueError(f"{cell.coordinate} already holds {cell.value!r} ({player}/{label})")
    cell.value = n
    if comment:
        cell.comment = make_comment(comment, author)
    return cell


def write_note(lay: Layout, col: int, text: str):
    cell = lay.ws.cell(lay.notes_row, col)
    if isinstance(cell, MergedCell):
        raise RuntimeError(f"notes anchor {cell.coordinate} is a merged non-anchor cell")
    cell.value = (cell.value + "\n" + text) if cell.value else text
    cell.alignment = Alignment(wrap_text=True, vertical="top")


# ---- recalculation -------------------------------------------------------
def recalc_script() -> Path:
    for cand in (
        os.environ.get("XLSX_RECALC"),
        Path(__file__).resolve().parent / "recalc_xlsx.py",
        Path.home() / ".claude/skills/xlsx-recalc-nixos/scripts/recalc_xlsx.py",
    ):
        if cand and Path(cand).exists():
            return Path(cand)
    raise FileNotFoundError(
        "recalc_xlsx.py not found - install the xlsx-recalc-nixos skill or set XLSX_RECALC"
    )


def recalc(path: Path, timeout: int = 240) -> dict:
    import json

    r = subprocess.run([sys.executable, str(recalc_script()), str(path), "--timeout", str(timeout)],
                       capture_output=True, text=True)
    try:
        return json.loads(r.stdout.strip().splitlines()[-1] if r.stdout.strip() else "{}") or {
            "error": r.stderr[-500:]
        }
    except json.JSONDecodeError:
        return {"error": (r.stdout + r.stderr)[-800:]}


def load(path=None, sheet=DEFAULT_SHEET, price_sheet=DEFAULT_PRICE_SHEET, data_only=False):
    path = Path(path) if path else DEFAULT_WORKBOOK
    wb = openpyxl.load_workbook(path, data_only=data_only)
    return wb, Layout(wb, sheet, price_sheet)

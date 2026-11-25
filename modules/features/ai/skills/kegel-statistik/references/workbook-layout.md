# KC DKKN Kegel-Statistik — workbook layout and conventions

File: `~/Nextcloud/Documents/kcdkkn/kasse/KC DKKN Statistik 24&25&26.xlsx`
(LibreOffice-style number formats; a `.bak.xlsx` next to it holds the state
before the 2026-10-30 entries). Photos of book pages and Zettel arrive in
`~/Nextcloud/Documents/kcdkkn/pictures/`.

## Sheets

| Sheet | Purpose |
|---|---|
| `Tabelle1` | Seasons 2022-07 … JHV 18.07.2025 (old price list: Rinne 50 ct / 10 ct, Taxipauschale 3 €). Read-only history. |
| `Lukas - Strafen ab 15.08.2025` | Price list, A2:B18 — the 17 penalty labels in the order every block uses. |
| `Lukas - Statistik ab 15.08.2025` | **The active sheet.** One column pair per Kegelabend. |
| `Statistik seit JHV 2025` | Formula-driven season statistics, built by `build_stats.py` (replaceable). |

## Active sheet geometry (discovered by `kegel_lib.Layout`, never hardcode)

- Row 3: evening date, merged over the pair. `D3` is the TEXT `'15.08.2025'`,
  every later header is a real date — parse both.
- Row 4 and every block's name row: `Anzahl Strafen ` (trailing space!) /
  `Strafen Preis €`.
- Player blocks of 19 rows: name row, 17 penalty rows in price-list order
  (`=A5`… labels, `=B5`… prices), `Summe Strafen:` with `=SUM(price rows)`.
  Price cells are `=<count>*$B<row>` (older columns reference `$B$5`-style
  master rows; both resolve identically).
- After the last block: a blank row, `Summe Kegeln:` (`=SUM(<every block's
  Summe Strafen>)`), then `Notizen zum Kegeln ` with one merged cell per pair
  (8 rows tall). Merged header/notes ranges already exist up to column DS.
- Column pairs run D/E, F/G, … Each pair is cloned from the previous one when
  a new evening is added (formulas translated by two columns).
- `freeze_panes` is `N262` in the source file (odd, left as is).

Penalty order (index → label, 2025/26 prices): 0 Nicht abgestimmt 5 €,
1 Vergessen (Kutte, Pudel oder Buch) 20 €, 2 Vergessen  (Shirt) 10 € (two
spaces in the label), 3 Vergessen (Pin) 5 €, 4 Schimpfwörter 0,50 €,
5 Unachtsamkeit 0,50 €, 6 Leine berührt 0,50 €, 7 Handy Nutzung 0,50 €,
8 Kugel aus der Bahn 2 €, 9 Taxipauschale 5 €, 10 5 er Spiel 5 €,
11 Auf die Bahn kotzen 20 €, 12 Rinne 1EUR 1 €, 13 Rinne 50ct 0,50 €,
14 Strafen Pauschale 10 €, 15 König −5 €, 16 Pudel 5 €.

## Conventions (verified over every evening since 15.08.2025)

- **Every player is accounted for every evening.** Present players carry their
  penalties; absent players carry `Strafen Pauschale = 1` (10 €). A present
  player with nothing bookable (Lucky on 11.09.2026) is simply empty — the
  statistics treat "no Pauschale" as present, so do not invent a penalty.
- A new player gets a full block (`add_player_block`), appended before
  `Summe Kegeln:`; the Summe Kegeln formulas are extended automatically.
- Evenings happen every four weeks on Fridays; the season runs from the
  Jahreshauptversammlung (JHV, mid-July/early August) to the next one. Planned
  dates may already have empty column pairs (e.g. 19.06. and 17.07.2026).
- Nicknames in the book/Zettel: Fochi = Focki, Luchy = Lucky, Schenho =
  Schenko, Schlauti = Schloti, Lukas = Lukas Fr., Robin = Robin P.,
  Schmelli = Schmelzer. `Marius` joined 11.09.2026.
- Notes for an evening go into the merged Notizen cell of its pair; cell
  comments carry per-entry assumptions (author `Übertrag …`).

## The physical Kegelbuch template

Rows: Strafe|Kegler (names), Vergessen 20 €, Vergessen 10 €, Pin 5 €, **thick
line**, Schimpfwörter 50 ct (**two ruled rows tall**), Unachtsamkeit, Leine
berührt, Handy Nutzung, Kugel aus der Bahn 2 €, Taxipauschale **3 €** (the
sheet charges 5 €), 5er Spiel 5 €, blank, blank, Summe Rinnen, Summe Strafen,
thick line, Spiel 1…10, Summe Punkte, Platzierungen, 5er-Spiel|Auswahl,
Trinken, Bezahlen, Notizen. Three players per page, two pages per evening.
Tally marks hang from a row's top line and often overshoot into the next
row, so assign a stroke to the row its *top* starts in, and remember the
Schimpfwörter row is two lines tall when counting rows below the thick line.
Game scores and drinks are not tracked in the workbook (put them in Notizen).

## Decision log

- 2026-10-30: Zettel evening (no book, "Kutte + Buch fehlt") entered as
  11.09.2026 — later confirmed by the user. Its 5 € items were booked as
  Vergessen (Pin), 0,50 € items as Schimpfwort (categories were not written
  down; cell comments say so). Its 10-ct amounts (0,20–0,50 €, 2,90 € total,
  presumably Rinnen at the old 10 ct rate) cannot be expressed with the
  current price list and live only in the Notizen cell.
- 2026-10-30: book note "Marius 20 Euro" booked as Vergessen (Kutte, Pudel
  oder Buch) for Marius on 11.09.2026 — assumption, flagged.
- 2026-10-30: Marius absent on 09.10.2026 got the Pauschale per convention —
  whether new players pay it is unconfirmed (flagged).
- Taxipauschale: the printed book says 3 €, the 2025/26 price list 5 €; the
  sheet's price list wins.

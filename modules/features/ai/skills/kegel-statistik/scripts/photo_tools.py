#!/usr/bin/env python3
"""Helpers for reading Kegelbuch photos: rotate, zoom crops, column strips, ruled-line finder.

    photo_tools.py rotate  IMG --deg -90 --out upright.jpg          # -90 = clockwise
    photo_tools.py grid    IMG --rows 2 --cols 2 --scale 2 --outdir crops/
    photo_tools.py crop    IMG --box X0 Y0 X1 Y1 --scale 3 --out zoom.jpg
    photo_tools.py strips  IMG --y 350 560 --scale 3 --out strips.jpg \
                           --strip labels:150-330 --strip John:300-365 --strip Timo:465-535
    photo_tools.py lines   IMG --x 400 440 --y 300 560                # ruled lines + ink runs in a window

Why: tally marks on a curved page are easy to misread by one row. Side-by-side
narrow strips (one per player column, starting at the thick Schimpfwörter line)
let you count rows by eye, and `lines` prints where the ruled lines and the ink
strokes actually are so a stroke on a row boundary can be assigned by measurement.
Run with Pillow available: nix-shell -p "python3.withPackages (ps: [ps.pillow])".
"""

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw


def zoom(im, box, scale):
    c = im.crop(box)
    return c.resize((c.width * scale, c.height * scale), Image.LANCZOS)


def cmd_rotate(a):
    im = Image.open(a.img).rotate(a.deg, expand=True)
    im.save(a.out, quality=92)
    print(a.out, im.size)


def cmd_grid(a):
    im = Image.open(a.img)
    Path(a.outdir).mkdir(parents=True, exist_ok=True)
    W, H = im.size
    for r in range(a.rows):
        for c in range(a.cols):
            box = (c * W // a.cols, r * H // a.rows, (c + 1) * W // a.cols, (r + 1) * H // a.rows)
            out = Path(a.outdir) / f"{Path(a.img).stem}_r{r}c{c}.jpg"
            zoom(im, box, a.scale).save(out, quality=92)
            print(out, box)


def cmd_crop(a):
    im = Image.open(a.img)
    z = zoom(im, tuple(a.box), a.scale)
    z.save(a.out, quality=92)
    print(a.out, z.size)


def cmd_strips(a):
    im = Image.open(a.img)
    y0, y1 = a.y
    parts = []
    for spec in a.strip:
        name, rng = spec.split(":")
        x0, x1 = (int(v) for v in rng.split("-"))
        z = zoom(im, (x0, y0, x1, y1), a.scale)
        cv = Image.new("RGB", (z.width + 10, z.height + 30), "white")
        cv.paste(z, (5, 30))
        ImageDraw.Draw(cv).text((3, 8), name, fill="red")
        parts.append(cv)
    W = sum(p.width for p in parts) + 20 * len(parts)
    H = max(p.height for p in parts)
    out = Image.new("RGB", (W, H), "white")
    x = 0
    for p in parts:
        out.paste(p, (x, 0))
        x += p.width + 20
    out.save(a.out, quality=92)
    print(a.out, out.size)


def cmd_lines(a):
    g = Image.open(a.img).convert("L")
    px = g.load()
    x0, x1 = a.x
    y0, y1 = a.y
    means = [sum(px[x, y] for x in range(x0, x1)) / (x1 - x0) for y in range(y0, y1)]
    sm = [sum(means[max(0, i - 1): i + 2]) / len(means[max(0, i - 1): i + 2]) for i in range(len(means))]
    print(f"window x{x0}-{x1} y{y0}-{y1}")
    print("ruled lines / dark rows (y, darkness, width):")
    for i in range(2, len(sm) - 2):
        local = sm[max(0, i - 10): i + 10]
        if sm[i] <= min(sm[i - 2: i + 3]) and sm[i] < max(local) - a.drop:
            depth = max(local) - sm[i]
            w, j = 1, i - 1
            while j > 0 and sm[j] < sm[i] + depth / 2:
                w += 1
                j -= 1
            j = i + 1
            while j < len(sm) and sm[j] < sm[i] + depth / 2:
                w += 1
                j += 1
            print(f"  y={y0 + i:4d}  {int(sm[i]):3d}  w={w}")
    cols = [x for x in range(x0, x1) if sum(1 for y in range(y0, y1) if px[x, y] < a.ink) < 0.4 * (y1 - y0)]
    cnt = [sum(1 for x in cols if px[x, y] < a.ink) for y in range(y0, y1)]
    runs, i = [], 0
    while i < len(cnt):
        if cnt[i] >= 2:
            j = i
            while j < len(cnt) and cnt[j] >= 1:
                j += 1
            if j - i >= 4:
                runs.append((y0 + i, y0 + j - 1))
            i = j
        else:
            i += 1
    print("ink strokes (y_start, y_end):", runs)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("rotate"); p.add_argument("img"); p.add_argument("--deg", type=float, required=True); p.add_argument("--out", required=True); p.set_defaults(fn=cmd_rotate)
    p = sub.add_parser("grid"); p.add_argument("img"); p.add_argument("--rows", type=int, default=2); p.add_argument("--cols", type=int, default=2); p.add_argument("--scale", type=int, default=2); p.add_argument("--outdir", required=True); p.set_defaults(fn=cmd_grid)
    p = sub.add_parser("crop"); p.add_argument("img"); p.add_argument("--box", type=int, nargs=4, required=True); p.add_argument("--scale", type=int, default=3); p.add_argument("--out", required=True); p.set_defaults(fn=cmd_crop)
    p = sub.add_parser("strips"); p.add_argument("img"); p.add_argument("--y", type=int, nargs=2, required=True); p.add_argument("--strip", action="append", required=True, help="name:x0-x1"); p.add_argument("--scale", type=int, default=3); p.add_argument("--out", required=True); p.set_defaults(fn=cmd_strips)
    p = sub.add_parser("lines"); p.add_argument("img"); p.add_argument("--x", type=int, nargs=2, required=True); p.add_argument("--y", type=int, nargs=2, required=True); p.add_argument("--drop", type=float, default=6); p.add_argument("--ink", type=int, default=110); p.set_defaults(fn=cmd_lines)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    sys.exit(main())

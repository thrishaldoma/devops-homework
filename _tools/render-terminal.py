#!/usr/bin/env python3
"""Render a captured terminal transcript (.txt) into a terminal-styled PNG.

The text is taken verbatim from the log file - nothing is re-typed or invented.
Lines are only colourised:
    "$ ..."  command    -> green
    "# ..."  commentary -> muted grey
    everything else     -> normal output
"""
import sys, os
from PIL import Image, ImageDraw, ImageFont

BG, CHROME, TXT   = "#11131a", "#1c1f29", "#d4d7e0"
CMD, NOTE, ACCENT = "#7ee787", "#7d8590", "#58a6ff"
FS, PAD, LH       = 15, 22, 21
TITLE_H, MAXW     = 34, 150          # wrap width in characters
MAX_LINES         = 200              # split into parts beyond this

def load_font(size, bold=False):
    for path, idx in (("/System/Library/Fonts/Menlo.ttc", 1 if bold else 0),
                      ("/System/Library/Fonts/SFNSMono.ttf", 0)):
        try:
            return ImageFont.truetype(path, size, index=idx)
        except Exception:
            continue
    return ImageFont.load_default()

def wrap(line, width):
    if len(line) <= width:
        return [line]
    out, cur = [], line
    while len(cur) > width:
        out.append(cur[:width])
        cur = "    " + cur[width:]      # indent continuations
    out.append(cur)
    return out

def render(lines, out_path, title):
    font, bold = load_font(FS), load_font(FS, bold=True)
    flat = []
    for raw in lines:
        flat.extend(wrap(raw.rstrip("\n"), MAXW))
    if not flat:
        flat = ["(empty)"]

    cw = draw_probe.textlength("M", font=font)
    width  = int(PAD * 2 + cw * min(MAXW, max(len(l) for l in flat))) + 8
    width  = max(width, 720)
    height = TITLE_H + PAD * 2 + LH * len(flat)

    img = Image.new("RGB", (width, height), BG)
    d = ImageDraw.Draw(img)
    # window chrome
    d.rectangle([0, 0, width, TITLE_H], fill=CHROME)
    for i, c in enumerate(("#ff5f56", "#ffbd2e", "#27c93f")):
        d.ellipse([PAD + i * 18 - 4, 12, PAD + i * 18 + 6, 22], fill=c)
    d.text((PAD + 74, 9), title, font=bold, fill="#8b93a7")

    y = TITLE_H + PAD
    for l in flat:
        s = l.lstrip()
        if s.startswith("$ "):
            colour, f = CMD, bold
        elif s.startswith("#"):
            colour, f = NOTE, font
        elif s.startswith("==="):
            colour, f = ACCENT, bold
        else:
            colour, f = TXT, font
        d.text((PAD, y), l, font=f, fill=colour)
        y += LH
    img.save(out_path)
    return width, height

probe = Image.new("RGB", (10, 10))
draw_probe = ImageDraw.Draw(probe)

def main(src, dst_dir):
    base = os.path.splitext(os.path.basename(src))[0]
    lines = open(src, encoding="utf-8", errors="replace").read().split("\n")
    while lines and not lines[-1].strip():
        lines.pop()
    os.makedirs(dst_dir, exist_ok=True)

    if len(lines) <= MAX_LINES:
        p = os.path.join(dst_dir, base + ".png")
        w, h = render(lines, p, base + ".txt")
        print(f"{p}  ({w}x{h}, {len(lines)} lines)")
    else:
        chunks = [lines[i:i + MAX_LINES] for i in range(0, len(lines), MAX_LINES)]
        for n, ch in enumerate(chunks, 1):
            p = os.path.join(dst_dir, f"{base}-part{n}.png")
            w, h = render(ch, p, f"{base}.txt  (part {n}/{len(chunks)})")
            print(f"{p}  ({w}x{h}, {len(ch)} lines)")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

#!/usr/bin/env python3
"""Turns the pane icons (assets/icons/*.svg) gray to match the app logo.

Every hex color is replaced by its luminance, with a little extra contrast so
saturated colors (blue, green) become dark gray and light ones stay light.
The WhiteSur artwork is GPL-3.0; this is a modification of it (see README).

    python3 icon/grayscale_icons.py assets/icons/*.svg
"""
import re
import sys

CONTRAST = 1.18


def gray(hexcolor: str) -> str:
    h = hexcolor.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    y = 0.299 * r + 0.587 * g + 0.114 * b
    if y < 250:  # keep pure white highlights white
        y = (y - 128) * CONTRAST + 128
    v = max(0, min(255, round(y)))
    return f"#{v:02x}{v:02x}{v:02x}"


for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    text = re.sub(r"#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b", lambda m: gray(m.group(0)), text)
    open(path, "w", encoding="utf-8").write(text)
    print("gray:", path)

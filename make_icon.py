#!/usr/bin/env python3
"""Generate AppIcon.icns + menu-bar template from agentpad-logo.png (black mark on white).

Run: python3 make_icon.py
Outputs:
  AppIcon.icns          – squircle app icon (white tile, black mark)
  Resources/menubar.png – monochrome template (mark on transparent) for the menu bar + header
"""
import os, math, subprocess, shutil
from PIL import Image, ImageDraw

SRC = "agentpad-logo.png"
ROOT = os.path.dirname(os.path.abspath(__file__))


def load_mark():
    """Return (mark_rgba, bbox) — the black mark isolated on transparent, tightly cropped."""
    im = Image.open(os.path.join(ROOT, SRC)).convert("RGBA")
    px = im.load()
    w, h = im.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            dark = 255 - min(r, g, b)          # white bg -> 0, black mark -> 255
            if a and dark > 16:
                op[x, y] = (0, 0, 0, dark)
    return out.crop(out.getbbox())


def squircle_mask(size, n=5.0):
    """Apple-style superellipse mask at `size`px (supersampled for smooth edges)."""
    ss = size * 4
    m = Image.new("L", (ss, ss), 0)
    d = m.load()
    c = ss / 2.0
    r = c
    for y in range(ss):
        for x in range(ss):
            if (abs((x - c) / r) ** n + abs((y - c) / r) ** n) <= 1.0:
                d[x, y] = 255
    return m.resize((size, size), Image.LANCZOS)


def app_icon(size, mark):
    """White squircle tile + centered black mark, with Apple's ~10% safe-area inset."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    tile = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    img.paste(tile, (0, 0), squircle_mask(size))

    inset = int(size * 0.20)
    box = size - 2 * inset
    m = mark.copy()
    mw, mh = m.size
    scale = min(box / mw, box / mh)
    m = m.resize((max(1, int(mw * scale)), max(1, int(mh * scale))), Image.LANCZOS)
    img.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return img


def main():
    mark = load_mark()

    # ---- menu-bar / header template (transparent, padded square) ----
    pad = int(max(mark.size) * 0.12)
    side = max(mark.size) + 2 * pad
    tmpl = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    tmpl.alpha_composite(mark, ((side - mark.width) // 2, (side - mark.height) // 2))
    tmpl.resize((88, 88), Image.LANCZOS).save(os.path.join(ROOT, "Resources", "menubar.png"))
    print("wrote Resources/menubar.png (88x88 template)")

    # ---- iconset -> icns ----
    iconset = os.path.join(ROOT, "AppIcon.iconset")
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset)
    for base in (16, 32, 128, 256, 512):
        app_icon(base, mark).save(os.path.join(iconset, f"icon_{base}x{base}.png"))
        app_icon(base * 2, mark).save(os.path.join(iconset, f"icon_{base}x{base}@2x.png"))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o",
                    os.path.join(ROOT, "AppIcon.icns")], check=True)
    print("wrote AppIcon.icns")

    # preview for README
    app_icon(256, mark).save(os.path.join(ROOT, "icon-preview.png"))
    print("wrote icon-preview.png")


if __name__ == "__main__":
    main()

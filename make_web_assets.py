#!/usr/bin/env python3
"""Generate favicons, apple-touch-icon, and the OG/Twitter social image for the site.

Run: python3 make_web_assets.py   (after make_icon.py — reuses the squircle icon)
Outputs into docs/assets/.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(ROOT, "docs", "assets")
LOGO = os.path.join(ROOT, "terminalpad-logo.png")
ICON = os.path.join(ROOT, "icon-preview.png")   # white squircle + black mark, 256px


def load_mark():
    """Black mark isolated on transparent, tightly cropped."""
    im = Image.open(LOGO).convert("RGBA")
    px = im.load()
    w, h = im.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            d = 255 - min(r, g, b)
            if a and d > 16:
                op[x, y] = (0, 0, 0, d)
    return out.crop(out.getbbox())


def tint(mark, rgb):
    r, g, b = rgb
    src = mark.split()[3]
    out = Image.new("RGBA", mark.size, (r, g, b, 0))
    out.putalpha(src)
    return out


def font(size, bold=True):
    paths = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold
        else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except Exception:
            continue
    return ImageFont.load_default()


def favicons():
    icon = Image.open(ICON).convert("RGBA")
    for s in (16, 32, 180):
        name = "apple-touch-icon.png" if s == 180 else f"favicon-{s}.png"
        icon.resize((s, s), Image.LANCZOS).save(os.path.join(ASSETS, name))
    # multi-size .ico
    icon.resize((48, 48), Image.LANCZOS).save(
        os.path.join(ASSETS, "favicon.ico"), sizes=[(16, 16), (32, 32), (48, 48)])
    print("wrote favicon-16/32, apple-touch-icon, favicon.ico")


def og_image():
    W, H = 1200, 630
    img = Image.new("RGBA", (W, H), (6, 6, 8, 255))
    d = ImageDraw.Draw(img)
    # soft purple glow top-left, blue bottom-right
    for cx, cy, col, rad in [(180, 120, (91, 60, 255), 520),
                             (1050, 560, (43, 107, 255), 560),
                             (980, 90, (192, 68, 255), 420)]:
        glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse([cx - rad, cy - rad, cx + rad, cy + rad], fill=col + (70,))
        img.alpha_composite(glow)

    mark = load_mark()
    # white app-tile on the left
    tile = Image.new("RGBA", (260, 260), (0, 0, 0, 0))
    td = ImageDraw.Draw(tile)
    td.rounded_rectangle([0, 0, 259, 259], radius=64, fill=(255, 255, 255, 255))
    m = mark.resize((150, int(150 * mark.height / mark.width)), Image.LANCZOS)
    tile.alpha_composite(m, ((260 - m.width) // 2, (260 - m.height) // 2))
    img.alpha_composite(tile, (110, (H - 260) // 2))

    tx = 430
    d.text((tx, 210), "TerminalPad", font=font(94), fill=(255, 255, 255, 255))
    d.text((tx, 322), "The home screen for AI coding",
           font=font(38, bold=False), fill=(188, 188, 210, 255))
    d.text((tx, 372), "agents on Mac.",
           font=font(38, bold=False), fill=(188, 188, 210, 255))
    img.convert("RGB").save(os.path.join(ASSETS, "og.png"), quality=92)
    print("wrote og.png (1200x630)")


if __name__ == "__main__":
    favicons()
    og_image()

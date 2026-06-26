#!/usr/bin/env python3
"""Build AppIcon.icns: white AgentPad logo on a dark glass squircle."""
import os, subprocess, math
from PIL import Image, ImageDraw, ImageFilter

SRC = "/Users/abhisarsingh/Documents/agentpad .png"
ROOT = os.path.dirname(os.path.abspath(__file__))
S = 1024

# --- logo: black-on-white -> white-on-transparent ---
logo = Image.open(SRC).convert("L")
# alpha = how black the pixel is (black logo -> opaque)
alpha = logo.point(lambda p: 255 - p)
white = Image.new("RGBA", logo.size, (255, 255, 255, 255))
white.putalpha(alpha)

# --- dark glass squircle background ---
bg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
draw = ImageDraw.Draw(bg)
radius = int(0.2237 * S)
# vertical dark gradient
grad = Image.new("RGBA", (S, S))
gd = grad.load()
top = (34, 36, 40)      # #222428
bot = (10, 10, 12)      # near black
for y in range(S):
    t = y / (S - 1)
    r = int(top[0] + (bot[0] - top[0]) * t)
    g = int(top[1] + (bot[1] - top[1]) * t)
    b = int(top[2] + (bot[2] - top[2]) * t)
    for x in range(S):
        gd[x, y] = (r, g, b, 255)

# squircle mask
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, fill=255)
bg = Image.composite(grad, bg, mask)

# subtle top glass highlight
hi = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(hi).rounded_rectangle([0, 0, S - 1, int(S * 0.5)],
                                     radius=radius, fill=(255, 255, 255, 22))
hi = hi.filter(ImageFilter.GaussianBlur(40))
hi.putalpha(Image.composite(hi.getchannel("A"), Image.new("L", (S, S), 0), mask))
bg = Image.alpha_composite(bg, hi)

# inner stroke
ImageDraw.Draw(bg).rounded_rectangle([2, 2, S - 3, S - 3], radius=radius,
                                     outline=(255, 255, 255, 40), width=3)

# --- place logo centered ~54% ---
target = int(S * 0.54)
lw, lh = white.size
scale = target / max(lw, lh)
white = white.resize((int(lw * scale), int(lh * scale)), Image.LANCZOS)
ox = (S - white.size[0]) // 2
oy = (S - white.size[1]) // 2
bg.alpha_composite(white, (ox, oy))

master = bg

# --- iconset ---
iconset = os.path.join(ROOT, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
specs = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for size, scale in specs:
    px = size * scale
    img = master.resize((px, px), Image.LANCZOS)
    name = f"icon_{size}x{size}{'@2x' if scale==2 else ''}.png"
    img.save(os.path.join(iconset, name))

subprocess.run(["iconutil", "-c", "icns", iconset,
                "-o", os.path.join(ROOT, "AppIcon.icns")], check=True)
master.save(os.path.join(ROOT, "icon-preview.png"))
print("AppIcon.icns built")

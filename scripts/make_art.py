#!/usr/bin/env python3
"""Generate the CurseForge avatar and banner (original art, Pillow only).

Run from anywhere: python3 scripts/make_art.py  -> writes curseforge/*.png
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "curseforge")
SS = 4  # supersampling factor

GOLD = (255, 209, 0)       # Hub.lua ring (1.0, 0.82, 0)
FILL = (18, 18, 25)        # Hub.lua fill (0.07, 0.07, 0.10)
TOP = (11, 34, 78)         # deep blue
BOT = (14, 112, 120)       # teal
LINE = (150, 205, 225, 48) # subtle handheld line art

FONT_PATH = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def font(size):
    try:
        return ImageFont.truetype(FONT_PATH, size)
    except OSError:
        return ImageFont.load_default(size=size)


def gradient(w, h):
    """Diagonal blue -> teal gradient."""
    g = Image.new("RGB", (w, h))
    px = g.load()
    for y in range(h):
        for x in range(w):
            t = (x / w * 0.35 + y / h * 0.65)
            px[x, y] = tuple(round(TOP[i] + (BOT[i] - TOP[i]) * t) for i in range(3))
    return g


def handheld(d, cx, cy, w, h, s):
    """Low-contrast handheld outline: body, two sticks, d-pad, face buttons."""
    lw = max(2, round(s * 0.012))
    d.rounded_rectangle((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2),
                        radius=h * 0.32, outline=LINE, width=lw)
    r = h * 0.11
    for sx in (-1, 1):  # sticks
        x = cx + sx * w * 0.36
        y = cy - h * 0.12 if sx < 0 else cy + h * 0.16
        d.ellipse((x - r, y - r, x + r, y + r), outline=LINE, width=lw)
    # d-pad (right-hand side swaps: d-pad right, buttons left would clash; keep d-pad lower-left)
    px, py, a = cx - w * 0.36, cy + h * 0.16, h * 0.11
    t = a * 0.38
    d.rectangle((px - t, py - a, px + t, py + a), outline=LINE, width=lw)
    d.rectangle((px - a, py - t, px + a, py + t), outline=LINE, width=lw)
    # face buttons (diamond, upper right)
    bx, by, o, br = cx + w * 0.36, cy - h * 0.12, h * 0.12, h * 0.04
    for dx, dy in ((0, -o), (0, o), (-o, 0), (o, 0)):
        d.ellipse((bx + dx - br, by + dy - br, bx + dx + br, by + dy + br),
                  outline=LINE, width=lw)


def mark(img, cx, cy, radius, s):
    """Dark disc, gold ring, white PE (with soft shadow)."""
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = radius * 0.05
    sd.ellipse((cx - radius, cy - radius + off, cx + radius, cy + radius + off), fill=(0, 0, 0, 110))
    from PIL import ImageFilter
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius * 0.06))
    img.alpha_composite(shadow)
    d = ImageDraw.Draw(img)
    d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=FILL + (255,))
    ring = radius * 0.09
    d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline=GOLD + (255,), width=round(ring))
    f = font(round(radius * 0.95))
    d.text((cx, cy), "PE", font=f, fill=(255, 255, 255, 255), anchor="mm")


def avatar():
    n = 400 * SS
    img = gradient(n, n).convert("RGBA")
    d = ImageDraw.Draw(img, "RGBA")
    handheld(d, n / 2, n / 2, n * 0.94, n * 0.60, n)
    mark(img, n / 2, n / 2, n * 0.30, n)
    return img.resize((400, 400), Image.LANCZOS).convert("RGB")


def banner():
    w, h = 1280 * SS, 640 * SS
    img = gradient(w, h).convert("RGBA")
    d = ImageDraw.Draw(img, "RGBA")
    handheld(d, w * 0.27, h * 0.5, w * 0.42, h * 0.62, h)
    mark(img, w * 0.27, h * 0.5, h * 0.25, h)
    d = ImageDraw.Draw(img)
    x = w * 0.5
    d.text((x, h * 0.45), "Pocket Essentials", font=font(round(h * 0.10)),
           fill=(255, 255, 255), anchor="ls")
    d.rectangle((x, h * 0.50, x + w * 0.06, h * 0.50 + 5 * SS), fill=GOLD)
    d.text((x, h * 0.62), "Handheld helpers for WoW Forever", font=font(round(h * 0.056)),
           fill=(205, 232, 240), anchor="ls")
    return img.resize((1280, 640), Image.LANCZOS).convert("RGB")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    avatar().save(os.path.join(OUT, "avatar.png"), optimize=True)
    banner().save(os.path.join(OUT, "banner.png"), optimize=True)
    print("wrote", OUT)

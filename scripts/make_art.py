#!/usr/bin/env python3
"""Generate the CurseForge avatar and banner (original art, Pillow only).

Run from anywhere: python3 scripts/make_art.py  -> writes curseforge/*.png
"""
import os
import argparse
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "curseforge")
SS = 4  # supersampling factor

PALETTES = {
    # Current (owner has not picked yet): navy->teal, black disc, gold ring.
    "current": dict(
        bg_top=(11, 34, 78), bg_bottom=(14, 112, 120),
        line=(150, 205, 225, 48), disc=(18, 18, 25), ring=(255, 209, 0),
        letters=(255, 255, 255), title=(255, 255, 255),
        tagline=(205, 232, 240), accent=(255, 209, 0)),
    "A": dict(  # Deep teal mono
        bg_top=(10, 74, 80), bg_bottom=(26, 150, 130),
        line=(150, 240, 225, 60), disc=(6, 38, 44), ring=(170, 245, 222),
        letters=(255, 255, 255), title=(255, 255, 255),
        tagline=(200, 245, 235), accent=(170, 245, 222)),
    "B": dict(  # Midnight ice
        bg_top=(10, 20, 58), bg_bottom=(52, 50, 130),
        line=(170, 205, 255, 60), disc=(6, 11, 36), ring=(160, 215, 255),
        letters=(255, 255, 255), title=(255, 255, 255),
        tagline=(200, 220, 255), accent=(160, 215, 255)),
    "C": dict(  # Dusk ember
        bg_top=(52, 18, 70), bg_bottom=(46, 44, 120),
        line=(200, 180, 255, 62), disc=(28, 9, 38), ring=(255, 160, 90),
        letters=(255, 244, 222), title=(255, 244, 222),
        tagline=(214, 198, 245), accent=(255, 160, 90)),
}
DEFAULT = "current"

FONT_PATH = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def font(size):
    try:
        return ImageFont.truetype(FONT_PATH, size)
    except OSError:
        return ImageFont.load_default(size=size)


def gradient(w, h, top, bottom):
    """Vertical top -> bottom gradient (fast: resize a 256-step ramp)."""
    mask = Image.linear_gradient("L").resize((w, h), Image.BILINEAR)
    return Image.composite(Image.new("RGB", (w, h), bottom),
                           Image.new("RGB", (w, h), top), mask)


def handheld(d, cx, cy, w, h, s, disc_r, line):
    """Low-contrast handheld outline: body, two sticks, d-pad, face buttons.

    disc_r is the radius of the mark drawn over the centre; the face-button
    cluster is pushed right until it clears the disc entirely.
    """
    lw = max(2, round(s * 0.012))
    d.rounded_rectangle((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2),
                        radius=h * 0.32, outline=line, width=lw)
    r = h * 0.11
    for sx in (-1, 1):  # sticks: upper-left, lower-right
        x = cx + sx * w * 0.36
        y = cy - h * 0.12 if sx < 0 else cy + h * 0.16
        d.ellipse((x - r, y - r, x + r, y + r), outline=line, width=lw)
    # d-pad (plus shape), lower left
    px, py, a = cx - w * 0.36, cy + h * 0.16, h * 0.11
    t = a * 0.38
    d.rectangle((px - t, py - a, px + t, py + a), outline=line, width=lw)
    d.rectangle((px - a, py - t, px + a, py + t), outline=line, width=lw)
    # face buttons (diamond), upper right, fully clear of the disc
    o, br = h * 0.07, h * 0.026
    by = cy - h * 0.12
    bx = max(cx + w * 0.36, cx + disc_r + s * 0.012 + o + br)
    for dx, dy in ((0, -o), (0, o), (-o, 0), (o, 0)):
        d.ellipse((bx + dx - br, by + dy - br, bx + dx + br, by + dy + br),
                  outline=line, width=lw)


def mark(img, cx, cy, radius, pal):
    """Dark disc, coloured ring, letters (with soft shadow)."""
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    off = radius * 0.05
    sd.ellipse((cx - radius, cy - radius + off, cx + radius, cy + radius + off), fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius * 0.06))
    img.alpha_composite(shadow)
    d = ImageDraw.Draw(img)
    box = (cx - radius, cy - radius, cx + radius, cy + radius)
    d.ellipse(box, fill=pal["disc"] + (255,))
    d.ellipse(box, outline=pal["ring"] + (255,), width=round(radius * 0.09))
    d.text((cx, cy), "PE", font=font(round(radius * 0.95)), fill=pal["letters"] + (255,), anchor="mm")


def avatar(pal):
    n = 400 * SS
    img = gradient(n, n, pal["bg_top"], pal["bg_bottom"]).convert("RGBA")
    d = ImageDraw.Draw(img, "RGBA")
    handheld(d, n / 2, n / 2, n * 0.94, n * 0.60, n, n * 0.30, pal["line"])
    mark(img, n / 2, n / 2, n * 0.30, pal)
    return img.resize((400, 400), Image.LANCZOS).convert("RGB")


def banner(pal):
    w, h = 1280 * SS, 640 * SS
    img = gradient(w, h, pal["bg_top"], pal["bg_bottom"]).convert("RGBA")
    d = ImageDraw.Draw(img, "RGBA")
    handheld(d, w * 0.27, h * 0.5, w * 0.42, h * 0.62, h, h * 0.25, pal["line"])
    mark(img, w * 0.27, h * 0.5, h * 0.25, pal)
    d = ImageDraw.Draw(img)
    x = w * 0.5
    d.text((x, h * 0.45), "Pocket Essentials", font=font(round(h * 0.10)),
           fill=pal["title"], anchor="ls")
    d.rectangle((x, h * 0.50, x + w * 0.06, h * 0.50 + 5 * SS), fill=pal["accent"])
    d.text((x, h * 0.62), "Handheld helpers for WoW Forever", font=font(round(h * 0.056)),
           fill=pal["tagline"], anchor="ls")
    return img.resize((1280, 640), Image.LANCZOS).convert("RGB")


def contact_sheet(path):
    """Every palette's avatar (400) + banner (640x320), labelled, in one PNG."""
    names = list(PALETTES)
    rowh, pad = 400, 24
    sheet = Image.new("RGB", (130 + 400 + pad + 800 + pad, len(names) * (rowh + pad) + pad), (235, 235, 235))
    d = ImageDraw.Draw(sheet)
    for i, name in enumerate(names):
        y = pad + i * (rowh + pad)
        pal = PALETTES[name]
        d.text((pad, y + 40), name, font=font(30), fill=(30, 30, 30), anchor="lm")
        sheet.paste(avatar(pal), (130, y))
        sheet.paste(banner(pal).resize((800, 400), Image.LANCZOS), (130 + 400 + pad, y))
        sheet.paste(avatar(pal).resize((64, 64), Image.LANCZOS), (pad, y + 80))
    sheet.save(path)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--palette", default=DEFAULT, choices=list(PALETTES))
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--contact-sheet", metavar="PNG")
    args = ap.parse_args()
    if args.contact_sheet:
        contact_sheet(args.contact_sheet)
    else:
        os.makedirs(args.out, exist_ok=True)
        avatar(PALETTES[args.palette]).save(os.path.join(args.out, "avatar.png"), optimize=True)
        banner(PALETTES[args.palette]).save(os.path.join(args.out, "banner.png"), optimize=True)
        print("wrote", args.out)

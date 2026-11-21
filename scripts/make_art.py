#!/usr/bin/env python3
"""Generate the CurseForge art (original art).

Run from anywhere: python3 scripts/make_art.py
It runs curseforge/source/render.sh, which saves the pages in
curseforge/source/ as curseforge/avatar.png, banner.png and images/*.png.
(--pillow writes the old Pillow-drawn avatar and banner instead.)

With --icons it instead writes the addon's own textures (original art):
    addons/PocketEssentials/Icons/arrow.tga, circle.tga, tab_round.tga
"""
import os
import struct
import argparse
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "curseforge")
ICONS = os.path.join(ROOT, "addons", "PocketEssentials", "Icons")
SS = 4  # supersampling factor

PALETTES = {
    # Previous default: navy->teal, black disc, gold ring.
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
DEFAULT = "B"

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
    d.text((x, h * 0.62), "All-in-one quality of life", font=font(round(h * 0.056)),
           fill=pal["tagline"], anchor="ls")
    d.text((x, h * 0.71), "Touch and controller friendly", font=font(round(h * 0.056)),
           fill=pal["tagline"], anchor="ls")
    return img.resize((1280, 640), Image.LANCZOS).convert("RGB")


# --- Addon textures -----------------------------------------------------------

ICON_SS = 8  # supersampling for the textures (edges must stay smooth when scaled)


def write_tga(img, path):
    """32-bit uncompressed TGA (type 2, BGRA, no RLE), bottom-left origin.

    The game reads the header's origin flag; bottom-left (descriptor 0x08:
    8 alpha bits, origin bit clear) is the classic layout every reader accepts.
    """
    img = img.convert("RGBA")
    w, h = img.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    rows = img.transpose(Image.FLIP_TOP_BOTTOM).tobytes("raw", "BGRA")
    with open(path, "wb") as f:
        f.write(header)
        f.write(rows)


def downscale(img, size, clear_rgb):
    """Supersampled RGBA -> final size, filtered with premultiplied alpha.

    Fully transparent pixels get clear_rgb (the colour of the nearby edge), so
    the game's bilinear filtering does not bleed a dark or light fringe.
    """
    out = img.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")
    clear = Image.new("RGBA", out.size, tuple(clear_rgb) + (0,))
    return Image.composite(out, clear, out.split()[3].point(lambda a: 255 if a else 0))


def circle_icon(size=128):
    """White filled circle on transparent; tinted in game with SetVertexColor."""
    n = size * ICON_SS
    m = 1.5 * ICON_SS  # small margin so the anti-aliased edge is never clipped
    img = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    ImageDraw.Draw(img).ellipse((m, m, n - 1 - m, n - 1 - m), fill=(255, 255, 255, 255))
    return downscale(img, size, (255, 255, 255))


# The bag's Sort tab: corner radius as a share of the tab's width (spec 0.9.0,
# "Bag Sort tab": radius button*0.28 on a tab one button wide).
TAB_RADIUS = 0.28


def tab_round_icon(size=32):
    """White square with its two left corners rounded, square on the right.

    Bags.lua draws it in three slices (top half, a thin middle band stretched
    to any height, bottom half), so the corners keep their shape on a tall tab.
    Each half holds a whole corner: the radius is under half the height.
    """
    n = size * ICON_SS
    r = TAB_RADIUS * n
    img = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, n - 1, n - 1), radius=r, fill=(255, 255, 255, 255),
                        corners=(True, False, False, True))
    return downscale(img, size, (255, 255, 255))


ARROW_OUTLINE = (12, 12, 14)


def arrow_icon(size=128):
    """Navigation arrow pointing straight up, white fill, dark outline baked in.

    The game rotates it about the texture centre (Texture:SetRotation), so
    the whole shape, outline included, stays inside the inscribed circle.
    Transparent pixels carry the outline colour so filtering leaves no halo.
    """
    s = size * ICON_SS / 128.0  # design in 128-unit space
    pts = [(64, 13), (99, 105), (64, 85), (29, 105)]  # tip, right wing, notch, left wing
    pts = [(x * s, y * s) for x, y in pts]
    outline = 7 * s
    n = size * ICON_SS
    img = Image.new("RGBA", (n, n), ARROW_OUTLINE + (0,))
    d = ImageDraw.Draw(img)
    dark = ARROW_OUTLINE + (240,)
    d.polygon(pts, fill=dark)
    d.line(pts + [pts[0]], fill=dark, width=round(outline * 2), joint="curve")
    for x, y in pts:  # round the line ends at the closing vertex too
        d.ellipse((x - outline, y - outline, x + outline, y + outline), fill=dark)
    d.polygon(pts, fill=(255, 255, 255, 255))
    return downscale(img, size, ARROW_OUTLINE)


def make_icons(out):
    os.makedirs(out, exist_ok=True)
    write_tga(arrow_icon(), os.path.join(out, "arrow.tga"))
    write_tga(circle_icon(), os.path.join(out, "circle.tga"))
    write_tga(tab_round_icon(), os.path.join(out, "tab_round.tga"))
    print("wrote", out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--palette", default=DEFAULT, choices=list(PALETTES))
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--pillow", action="store_true",
                    help="write the old Pillow-drawn avatar and banner")
    ap.add_argument("--icons", action="store_true",
                    help="write the addon textures into addons/PocketEssentials/Icons")
    args = ap.parse_args()
    if args.icons:
        make_icons(ICONS)
    elif not args.pillow:
        import subprocess
        subprocess.run([os.path.join(OUT, "source", "render.sh")], check=True)
    else:
        os.makedirs(args.out, exist_ok=True)
        avatar(PALETTES[args.palette]).save(os.path.join(args.out, "avatar.png"), optimize=True)
        banner(PALETTES[args.palette]).save(os.path.join(args.out, "banner.png"), optimize=True)
        print("wrote", args.out)

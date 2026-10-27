#!/usr/bin/env python3
"""Draws the app icon: Resources/AppIcon.png (1024px) and Resources/AppIcon.icns.

Needs Pillow (pip3 install pillow). Run from anywhere:  python3 scripts/make-icon.py
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SS = 4                      # supersampling factor for smooth edges
SIZE = 1024 * SS
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources")


def s(v):
    return int(round(v * SS))


def hex_rgb(h, a=255):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255, a)


def squircle_mask(size, box, n=5.0):
    """Superellipse (macOS icon shape) filling `box`."""
    x0, y0, x1, y1 = box
    cx, cy, rx, ry = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, si = math.cos(t), math.sin(t)
        pts.append((cx + rx * math.copysign(abs(c) ** (2 / n), c),
                    cy + ry * math.copysign(abs(si) ** (2 / n), si)))
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


def vertical_gradient(size, top, bottom):
    g = Image.new("RGBA", (1, 256))
    for y in range(256):
        t = y / 255
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4)))
    return g.resize((size, size), Image.BILINEAR)


def shadow(mask, offset, blur, alpha):
    sh = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    a = mask.point(lambda v: v * alpha // 255)
    sh.putalpha(a)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    out.paste(sh, offset, sh)
    return out


def card(color, center, side, angle, person=False):
    """A rounded-square profile avatar, rotated around its center."""
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    cx, cy = s(center[0]), s(center[1])
    half = s(side) // 2
    box = (cx - half, cy - half, cx + half, cy + half)
    radius = s(side * 0.27)

    m = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius, fill=255)

    fill = vertical_gradient(SIZE, hex_rgb(color[0]), hex_rgb(color[1]))
    layer.paste(fill, (0, 0), m)

    if person:
        d = ImageDraw.Draw(layer)
        white = (255, 255, 255, 255)
        hr = s(side * 0.15)
        hy = cy - s(side * 0.10)
        d.ellipse((cx - hr, hy - hr, cx + hr, hy + hr), fill=white)
        bw, bh = s(side * 0.27), s(side * 0.36)
        by = cy + s(side * 0.11)
        body = Image.new("L", (SIZE, SIZE), 0)
        ImageDraw.Draw(body).ellipse((cx - bw, by, cx + bw, by + bh), fill=255)
        body = ImageChops.multiply(body, m)
        clip = Image.new("L", (SIZE, SIZE), 0)
        ImageDraw.Draw(clip).rectangle((0, 0, SIZE, cy + s(side * 0.31)), fill=255)
        body = ImageChops.multiply(body, clip)
        layer.paste(Image.new("RGBA", (SIZE, SIZE), white), (0, 0), body)

    layer = layer.rotate(angle, resample=Image.BICUBIC, center=(cx, cy))
    return layer


def main():
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

    # Icon body on the standard macOS grid: 824px squircle centered in 1024.
    body_box = (s(100), s(100), s(924), s(924))
    body_mask = squircle_mask(SIZE, body_box)
    canvas = Image.alpha_composite(canvas, shadow(body_mask, (0, s(12)), s(18), 90))
    bg = vertical_gradient(SIZE, hex_rgb(0xFFFDF8), hex_rgb(0xECE7DC))
    body = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    body.paste(bg, (0, 0), body_mask)

    # Three stacked profiles: blue and green behind, rust (accent) in front.
    cards = [
        ((0x3B68DE, 0x2A50BD), (404, 400), 330, 14, False),
        ((0x26896A, 0x1A6A4E), (488, 484), 330, 6, False),
        ((0xC4552A, 0xA23F19), (580, 584), 350, 0, True),
    ]
    for color, center, side, angle, person in cards:
        layer = card(color, center, side, angle, person)
        body = Image.alpha_composite(body, shadow(layer.getchannel("A"), (0, s(10)), s(16), 70))
        body = Image.alpha_composite(body, layer)

    # keep everything inside the squircle
    body.putalpha(ImageChops.multiply(body.getchannel("A"), body_mask))
    canvas = Image.alpha_composite(canvas, body)

    icon = canvas.resize((1024, 1024), Image.LANCZOS)
    png = os.path.join(ROOT, "AppIcon.png")
    icns = os.path.join(ROOT, "AppIcon.icns")
    icon.save(png)
    icon.save(icns, sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
    print("wrote", os.path.normpath(png))
    print("wrote", os.path.normpath(icns))


if __name__ == "__main__":
    main()

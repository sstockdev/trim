"""Trim app icon: a weight-trend line easing down to a goal dot. Usage: python trim_icon.py <out.png>"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 2048


def gradient(top, bottom):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img.convert("RGBA")


def curve():
    # Starts high on the left, drops, then levels off toward the goal: what a healthy trend looks like.
    pts = []
    for i in range(201):
        t = i / 200
        x = S * (0.21 + 0.56 * t)
        y = S * (0.3 + 0.38 * (1 - math.exp(-3.2 * t)) / (1 - math.exp(-3.2)))
        pts.append((x, y))
    return pts


def art(layer, color, goal):
    d = ImageDraw.Draw(layer)
    width = int(S * 0.075)
    pts = curve()
    # Stamped discs instead of a wide polyline, which leaves seams between segments.
    for i in range(len(pts) - 1):
        (x0, y0), (x1, y1) = pts[i], pts[i + 1]
        steps = max(1, int(math.hypot(x1 - x0, y1 - y0) / 3))
        for k in range(steps + 1):
            x, y = x0 + (x1 - x0) * k / steps, y0 + (y1 - y0) * k / steps
            d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=color)
    gx, gy = pts[-1]
    r = S * 0.085
    d.ellipse([gx - r, gy - r, gx + r, gy + r], fill=goal)
    # Dashed goal line under the dot.
    dash, gap = S * 0.05, S * 0.035
    x = S * 0.16
    y = gy + r + S * 0.075
    while x + dash <= S * 0.84 + 1:
        d.rounded_rectangle([x, y - S * 0.012, min(x + dash, S * 0.84), y + S * 0.012], radius=S * 0.012,
                            fill=color[:3] + (110,))
        x += dash + gap


def make(path):
    img = gradient((46, 196, 140), (10, 98, 86))
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse([S * 0.1, S * 0.0, S * 0.9, S * 0.7], fill=(255, 255, 255, 50))
    img.alpha_composite(halo.filter(ImageFilter.GaussianBlur(S * 0.14)))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    art(shadow, (0, 0, 0, 70), (0, 0, 0, 70))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(S * 0.012)), (0, int(S * 0.012)))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    art(layer, (255, 255, 255, 255), (255, 214, 102, 255))
    img.alpha_composite(layer)
    img.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(path)


make(sys.argv[1])

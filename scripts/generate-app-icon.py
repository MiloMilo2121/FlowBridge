#!/usr/bin/env python3
"""Generate the FlowBridge app icon set (default / dark / tinted).

Design: seven waveform capsules whose height envelope draws a bridge arch,
on a near-black glass background with a faint violet radial glow.
Output: 1024x1024 PNGs into Resources/Assets.xcassets/AppIcon.appiconset/.

Requires Pillow:  python3 -m venv .build/iconenv && .build/iconenv/bin/pip install pillow
Run:              .build/iconenv/bin/python scripts/generate-app-icon.py
"""

import math
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:  # pragma: no cover
    raise SystemExit("Pillow missing. Run: python3 -m venv .build/iconenv && .build/iconenv/bin/pip install pillow")

SIZE = 1024
ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"

BG_TOP = (16, 15, 26, 255)      # #100F1A
BG_BOTTOM = (11, 11, 18, 255)   # #0B0B12
GLOW = (91, 76, 245)            # #5B4CF5
BAR_TOP = (139, 124, 255, 255)  # #8B7CFF
BAR_BOTTOM = (74, 58, 232, 255) # #4A3AE8

BAR_COUNT = 7
BAR_WIDTH = 68
BAR_GAP = 44
MIN_H, MAX_H = 170, 560
# Subtle per-bar variation so the arch still reads as a living waveform.
WIGGLE = [1.00, 0.94, 1.04, 1.00, 0.95, 1.03, 1.00]


def bar_heights():
    heights = []
    for i in range(BAR_COUNT):
        arch = math.sin(math.pi * (i + 0.5) / BAR_COUNT)
        heights.append((MIN_H + (MAX_H - MIN_H) * arch) * WIGGLE[i])
    return heights


def vertical_gradient(size, top, bottom):
    img = Image.new("RGBA", size)
    w, h = size
    for y in range(h):
        t = y / max(h - 1, 1)
        row = tuple(round(top[c] + (bottom[c] - top[c]) * t) for c in range(4))
        img.paste(Image.new("RGBA", (w, 1), row), (0, y))
    return img


def capsule_mask(width, height):
    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius=width // 2, fill=255)
    return mask


def draw_bars(canvas, top_color, bottom_color, glow_alpha):
    heights = bar_heights()
    total_w = BAR_COUNT * BAR_WIDTH + (BAR_COUNT - 1) * BAR_GAP
    start_x = (SIZE - total_w) // 2
    center_y = SIZE // 2

    if glow_alpha:
        glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        gdraw = ImageDraw.Draw(glow)
        for i, h in enumerate(heights):
            x = start_x + i * (BAR_WIDTH + BAR_GAP)
            gdraw.rounded_rectangle(
                (x - 8, center_y - h / 2 - 8, x + BAR_WIDTH + 8, center_y + h / 2 + 8),
                radius=(BAR_WIDTH + 16) // 2,
                fill=GLOW + (glow_alpha,),
            )
        canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(36)))

    for i, h in enumerate(heights):
        h = round(h)
        x = start_x + i * (BAR_WIDTH + BAR_GAP)
        y = round(center_y - h / 2)
        bar = vertical_gradient((BAR_WIDTH, h), top_color, bottom_color)
        canvas.paste(bar, (x, y), capsule_mask(BAR_WIDTH, h))


def make_default():
    canvas = vertical_gradient((SIZE, SIZE), BG_TOP, BG_BOTTOM)
    # Faint radial glow anchored just below center, behind the glyph.
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((512 - 430, 590 - 380, 512 + 430, 590 + 380), fill=GLOW + (46,))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(160)))
    draw_bars(canvas, BAR_TOP, BAR_BOTTOM, glow_alpha=70)
    return canvas


def make_dark():
    # Transparent background: iOS composes the glyph on its own dark backdrop.
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_bars(canvas, BAR_TOP, BAR_BOTTOM, glow_alpha=60)
    return canvas


def make_tinted():
    # Grayscale-on-transparent: iOS derives the tint from luminance.
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_bars(canvas, (250, 250, 250, 255), (150, 150, 150, 255), glow_alpha=0)
    return canvas


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    make_default().convert("RGB").save(DEST / "AppIcon.png")  # default icon must be opaque
    make_dark().save(DEST / "AppIcon-Dark.png")
    make_tinted().save(DEST / "AppIcon-Tinted.png")
    print(f"Icons written to {DEST}")


if __name__ == "__main__":
    main()

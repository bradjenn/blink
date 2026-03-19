#!/usr/bin/env python3
"""Generate 'under construction' debug app icons from the production icon."""

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parent.parent
SRC_DIR = REPO / "Blink" / "Assets.xcassets" / "AppIcon.appiconset"
DST_DIR = REPO / "Blink" / "Assets.xcassets" / "AppIcon-Debug.appiconset"

# All icon variants needed for macOS
VARIANTS = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

# Construction colors
YELLOW = (255, 200, 0, 255)
BLACK_STRIPE = (30, 30, 30, 255)
BANNER_BG = (255, 160, 0, 255)
BANNER_TEXT = (30, 30, 30, 255)


def draw_hazard_stripes(draw, width, height, stripe_width, stripe_height):
    """Draw diagonal hazard stripes in a band at the bottom of the icon."""
    y_start = height - stripe_height
    # Yellow background for stripe area
    draw.rectangle([0, y_start, width, height], fill=YELLOW)

    # Black diagonal stripes
    sw = stripe_width
    for x in range(-height, width + height, sw * 2):
        points = [
            (x, height),
            (x + sw, height),
            (x + sw + stripe_height, y_start),
            (x + stripe_height, y_start),
        ]
        draw.polygon(points, fill=BLACK_STRIPE)


def draw_dev_banner(draw, width, height, banner_height):
    """Draw a 'DEV' banner rotated -20 degrees across the top-right corner."""
    # We'll draw a horizontal ribbon across the top-right
    ribbon_y = int(height * 0.12)
    draw.rectangle([0, ribbon_y, width, ribbon_y + banner_height], fill=BANNER_BG)

    # Draw text centered in the ribbon
    text = "DEV"
    try:
        font_size = max(int(banner_height * 0.7), 8)
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except (OSError, IOError):
        font = ImageFont.load_default()

    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (width - tw) // 2
    ty = ribbon_y + (banner_height - th) // 2 - bbox[1]
    draw.text((tx, ty), text, fill=BANNER_TEXT, font=font)


def generate_debug_icon(src_path, dst_path, size):
    """Overlay construction elements onto the source icon."""
    img = Image.open(src_path).convert("RGBA").resize((size, size), Image.LANCZOS)

    # Create overlay
    overlay = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    stripe_height = max(int(size * 0.14), 3)
    stripe_width = max(int(size * 0.08), 2)
    banner_height = max(int(size * 0.18), 4)

    # Hazard stripes at bottom
    draw_hazard_stripes(draw, size, size, stripe_width, stripe_height)

    # DEV banner at top
    draw_dev_banner(draw, size, size, banner_height)

    # Apply rounded mask matching the original icon shape
    # The original icon has ~22.37% corner radius (macOS standard)
    radius = int(size * 0.2237)
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, size, size], radius=radius, fill=255)

    # Mask the overlay to the icon shape
    overlay.putalpha(Image.composite(overlay.split()[3], Image.new("L", (size, size), 0), mask))

    # Composite
    result = Image.alpha_composite(img, overlay)
    result.save(dst_path, "PNG")


def main():
    DST_DIR.mkdir(parents=True, exist_ok=True)

    for filename, size in VARIANTS:
        src = SRC_DIR / filename
        dst = DST_DIR / filename
        if src.exists():
            generate_debug_icon(src, dst, size)
            print(f"  {filename} ({size}x{size})")
        else:
            print(f"  SKIP {filename} (source not found)")

    print(f"\nGenerated {len(VARIANTS)} debug icons in {DST_DIR.relative_to(REPO)}")


if __name__ == "__main__":
    main()

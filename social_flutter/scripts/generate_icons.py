"""
Generate NTripi app icons in all required sizes using Pillow.
Run from the social_flutter directory: python3 scripts/generate_icons.py
"""
import math
import os
from PIL import Image, ImageDraw

FOREST = (31, 94, 58)    # ~oklch(34% 0.11 150)
AMBER  = (200, 144, 48)  # ~oklch(66% 0.17 75)
WHITE  = (255, 255, 255)

def draw_logo(draw: ImageDraw.ImageDraw, size: int) -> None:
    """Draw the NTripi logo mark onto draw at the given square size."""
    s = size / 32.0  # scale factor from the 32x32 viewbox

    # Rounded square background — fill the whole canvas (bg is already set)
    # (Already filled by the Image background color)

    # N-route polyline: (8,24)→(8,10)→(16,20)→(24,10)
    stroke_w = max(1, round(2.5 * s))
    points = [
        (8 * s, 24 * s),
        (8 * s, 10 * s),
        (16 * s, 20 * s),
        (24 * s, 10 * s),
    ]
    draw.line(points, fill=WHITE, width=stroke_w, joint="curve")

    # Round caps — draw small circles at each joint for cap/join rounding
    r_cap = stroke_w / 2
    for (x, y) in points:
        draw.ellipse(
            [x - r_cap, y - r_cap, x + r_cap, y + r_cap],
            fill=WHITE,
        )

    # Amber destination dot (outer) at top-right endpoint (24, 10)
    r_amber = 3 * s
    cx, cy = 24 * s, 10 * s
    draw.ellipse(
        [cx - r_amber, cy - r_amber, cx + r_amber, cy + r_amber],
        fill=AMBER,
    )

    # White inner dot
    r_inner = 1.5 * s
    draw.ellipse(
        [cx - r_inner, cy - r_inner, cx + r_inner, cy + r_inner],
        fill=WHITE,
    )


def make_icon(size: int, supersampling: int = 4) -> Image.Image:
    """
    Render the logo at size*supersampling then downsample to size×size
    for smooth anti-aliasing.
    """
    ss = size * supersampling
    radius = round(8 / 32 * ss)  # proportional corner radius

    # Background image
    img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Rounded square
    draw.rounded_rectangle([0, 0, ss - 1, ss - 1], radius=radius, fill=FOREST)

    # Logo mark
    draw_logo(draw, ss)

    # Downsample
    img = img.resize((size, size), Image.LANCZOS)
    return img


def save_png(img: Image.Image, path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img_rgb = Image.new("RGB", img.size, FOREST)
    img_rgb.paste(img, mask=img.split()[3])
    img_rgb.save(path, "PNG", optimize=True)
    print(f"  wrote {path}  ({img.size[0]}×{img.size[1]})")


def main() -> None:
    base = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    sizes = {
        # Android mipmaps
        "android/app/src/main/res/mipmap-mdpi/ic_launcher.png":     48,
        "android/app/src/main/res/mipmap-hdpi/ic_launcher.png":     72,
        "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png":    96,
        "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png":   144,
        "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png":  192,
        # Web
        "web/favicon.png":          32,
        "web/icons/Icon-192.png":   192,
        "web/icons/Icon-512.png":   512,
        "web/icons/Icon-maskable-192.png": 192,
        "web/icons/Icon-maskable-512.png": 512,
    }

    print("Generating NTripi icons…")
    for rel_path, size in sizes.items():
        img = make_icon(size)
        save_png(img, os.path.join(base, rel_path))

    print("Done.")


if __name__ == "__main__":
    main()

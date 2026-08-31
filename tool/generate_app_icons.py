"""Generate platform icons from the Recodex Relay brand mark.

The renderer intentionally uses only the Python standard library so icon
generation works on a fresh checkout. Its geometry mirrors relay-web's
Recodex mark while adding the soft paper tile, gradient bubble and restrained
highlight used by the product icon.
"""

from pathlib import Path
from functools import lru_cache
import math
import struct
import zlib


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "images" / "recodex_icon_1024.png"

DESIGN_SIZE = 1024.0
ICON_SCALE = 1.32
PAPER_TOP = (255, 255, 255)
PAPER_BOTTOM = (238, 243, 255)
BUBBLE_TOP = (184, 181, 255)
BUBBLE_MIDDLE = (111, 167, 255)
BUBBLE_BOTTOM = (52, 72, 244)
PROMPT = (237, 246, 255)
SHADOW = (39, 70, 219)


def _transform(value):
    return 512.0 + (value - 512.0) * ICON_SCALE


def _untransform(value):
    return 512.0 + (value - 512.0) / ICON_SCALE


def _point(point):
    return (_transform(point[0]), _transform(point[1]))


RECT_LEFT = _transform(230)
RECT_TOP = _transform(222)
RECT_RIGHT = _transform(822)
RECT_BOTTOM = _transform(784)
RECT_RADIUS = 188.0 * ICON_SCALE
STROKE_WIDTH = 52.0 * ICON_SCALE
PAPER_RADIUS = 230.0

CHEVRON = [_point((366, 444)), _point((466, 546)), _point((366, 648))]
CURSOR = [_point((552, 660)), _point((718, 660))]


def _inside_rounded_rect(x, y, left, top, right, bottom, radius):
    if not (left <= x <= right and top <= y <= bottom):
        return False
    if left + radius <= x <= right - radius:
        return True
    if top + radius <= y <= bottom - radius:
        return True
    cx = left + radius if x < left + radius else right - radius
    cy = top + radius if y < top + radius else bottom - radius
    return math.hypot(x - cx, y - cy) <= radius


def _mix(first, second, amount):
    return tuple(round(a + (b - a) * amount) for a, b in zip(first, second))


def _blend(base, overlay, alpha):
    return _mix(base, overlay, max(0.0, min(1.0, alpha)))


def _paper_color(y):
    return _mix(PAPER_TOP, PAPER_BOTTOM, max(0.0, min(1.0, y / DESIGN_SIZE)))


def _bubble_color(x, y):
    dx = 700.0 - 312.0
    dy = 724.0 - 280.0
    amount = ((x - 312.0) * dx + (y - 280.0) * dy) / (dx * dx + dy * dy)
    amount = max(0.0, min(1.0, amount))
    if amount < 0.42:
        return _mix(BUBBLE_TOP, BUBBLE_MIDDLE, amount / 0.42)
    return _mix(BUBBLE_MIDDLE, BUBBLE_BOTTOM, (amount - 0.42) / 0.58)


def _shadow_alpha(x, y):
    """Return a continuous blue shadow around an offset rounded rectangle."""
    center_x = (RECT_LEFT + RECT_RIGHT) / 2.0
    center_y = (RECT_TOP + RECT_BOTTOM) / 2.0 + 18.0
    inner_half_width = (RECT_RIGHT - RECT_LEFT) / 2.0 - RECT_RADIUS
    inner_half_height = (RECT_BOTTOM - RECT_TOP) / 2.0 - RECT_RADIUS
    qx = abs(x - center_x) - inner_half_width
    qy = abs(y - center_y) - inner_half_height
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    signed_distance = outside + min(max(qx, qy), 0.0) - RECT_RADIUS
    distance = max(0.0, signed_distance)
    return 0.24 * math.exp(-0.5 * (distance / 20.0) ** 2)


def _shine_alpha(x, y):
    local_x = _untransform(x)
    local_y = _untransform(y)
    distance = ((local_x - 526.0) / 226.0) ** 2 + ((local_y - 292.0) / 98.0) ** 2
    if distance >= 1:
        return 0.0
    return 0.2 * (1.0 - distance) ** 0.7


def _distance_to_segment(x, y, start, end):
    dx = end[0] - start[0]
    dy = end[1] - start[1]
    length_squared = dx * dx + dy * dy
    if length_squared == 0:
        return math.hypot(x - start[0], y - start[1])
    t = ((x - start[0]) * dx + (y - start[1]) * dy) / length_squared
    t = max(0.0, min(1.0, t))
    return math.hypot(x - (start[0] + t * dx), y - (start[1] + t * dy))


def _inside_prompt(x, y):
    half_width = STROKE_WIDTH / 2.0
    for start, end in zip(CHEVRON, CHEVRON[1:]):
        if _distance_to_segment(x, y, start, end) <= half_width:
            return True
    return _distance_to_segment(x, y, CURSOR[0], CURSOR[1]) <= half_width


def render_logo(size, samples=4, rounded_paper=True):
    """Return an antialiased RGBA pixel buffer for a square icon."""
    pixels = bytearray(size * size * 4)
    sample_count = samples * samples
    design_per_pixel = DESIGN_SIZE / size
    for py in range(size):
        for px in range(size):
            red = green = blue = alpha = 0
            covered_samples = 0
            for sy in range(samples):
                y = (py + (sy + 0.5) / samples) * design_per_pixel
                for sx in range(samples):
                    x = (px + (sx + 0.5) / samples) * design_per_pixel
                    if rounded_paper and not _inside_rounded_rect(
                        x,
                        y,
                        0.0,
                        0.0,
                        DESIGN_SIZE,
                        DESIGN_SIZE,
                        PAPER_RADIUS,
                    ):
                        continue
                    covered_samples += 1
                    color = _paper_color(y)
                    color = _blend(color, SHADOW, _shadow_alpha(x, y))
                    if _inside_rounded_rect(
                        x,
                        y,
                        RECT_LEFT,
                        RECT_TOP,
                        RECT_RIGHT,
                        RECT_BOTTOM,
                        RECT_RADIUS,
                    ):
                        color = _bubble_color(_untransform(x), _untransform(y))
                        color = _blend(
                            color,
                            (255, 255, 255),
                            _shine_alpha(x, y),
                        )
                        if _inside_prompt(x, y):
                            color = PROMPT
                    red += color[0]
                    green += color[1]
                    blue += color[2]
                    alpha += 255
            offset = (py * size + px) * 4
            if alpha:
                pixels[offset : offset + 4] = bytes(
                    (
                        round(red / covered_samples),
                        round(green / covered_samples),
                        round(blue / covered_samples),
                        round(alpha / sample_count),
                    )
                )
    return pixels


def _png_chunk(kind, payload):
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def png_bytes(size, pixels):
    scanlines = bytearray()
    row_size = size * 4
    for row in range(size):
        scanlines.append(0)
        start = row * row_size
        scanlines.extend(pixels[start : start + row_size])
    return (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + _png_chunk(b"IDAT", zlib.compress(bytes(scanlines), 9))
        + _png_chunk(b"IEND", b"")
    )


@lru_cache(maxsize=None)
def rendered_png(size, rounded_paper=True):
    # One sample is already subpixel-sized at 512 px and above. Smaller
    # assets use extra coverage samples to preserve smooth edges.
    samples = 1 if size >= 512 else 2 if size >= 256 else 4
    return png_bytes(
        size,
        render_logo(size, samples=samples, rounded_paper=rounded_paper),
    )


def save_png(path, size, rounded_paper=True):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(rendered_png(size, rounded_paper))


def save_ico(path):
    sizes = (16, 24, 32, 48, 64, 128, 256)
    images = [rendered_png(size) for size in sizes]
    offset = 6 + 16 * len(images)
    entries = bytearray()
    for size, image in zip(sizes, images):
        dimension = 0 if size == 256 else size
        entries.extend(
            struct.pack(
                "<BBBBHHII",
                dimension,
                dimension,
                0,
                0,
                1,
                32,
                len(image),
                offset,
            )
        )
        offset += len(image)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        struct.pack("<HHH", 0, 1, len(images))
        + entries
        + b"".join(images)
    )


def main():
    save_png(SOURCE, 1024)

    android = {
        "mipmap-mdpi/ic_launcher.png": 48,
        "mipmap-hdpi/ic_launcher.png": 72,
        "mipmap-xhdpi/ic_launcher.png": 96,
        "mipmap-xxhdpi/ic_launcher.png": 144,
        "mipmap-xxxhdpi/ic_launcher.png": 192,
    }
    for rel, size in android.items():
        save_png(ROOT / "android/app/src/main/res" / rel, size)

    ios = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    ios_dir = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, size in ios.items():
        # App Store icons must not contain transparent pixels; iOS supplies
        # the final platform mask.
        save_png(ios_dir / name, size, rounded_paper=False)

    macos = {
        "app_icon_16.png": 16,
        "app_icon_32.png": 32,
        "app_icon_64.png": 64,
        "app_icon_128.png": 128,
        "app_icon_256.png": 256,
        "app_icon_512.png": 512,
        "app_icon_1024.png": 1024,
    }
    macos_dir = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, size in macos.items():
        save_png(macos_dir / name, size)

    web = {
        "favicon.png": 32,
        "icons/Icon-192.png": 192,
        "icons/Icon-512.png": 512,
    }
    for rel, size in web.items():
        save_png(ROOT / "web" / rel, size)

    maskable_web = {
        "icons/Icon-maskable-192.png": 192,
        "icons/Icon-maskable-512.png": 512,
    }
    for rel, size in maskable_web.items():
        save_png(ROOT / "web" / rel, size, rounded_paper=False)

    save_ico(ROOT / "windows/runner/resources/app_icon.ico")


if __name__ == "__main__":
    main()

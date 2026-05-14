from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "images" / "recodex_icon_1024.png"
ICON_SCALE = 1.32


def rounded_rectangle(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def alpha_composite_ellipse(image, box, fill):
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    ImageDraw.Draw(overlay).ellipse(box, fill=fill)
    image.alpha_composite(overlay)


def radial_glow(image, center, radius, color, max_alpha):
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    pixels = overlay.load()
    cx, cy = center
    r2 = radius * radius
    left = max(0, cx - radius)
    right = min(image.size[0], cx + radius)
    top = max(0, cy - radius)
    bottom = min(image.size[1], cy + radius)
    for y in range(top, bottom):
        dy = y - cy
        for x in range(left, right):
            dx = x - cx
            d2 = dx * dx + dy * dy
            if d2 > r2:
                continue
            t = 1 - (d2 / r2)
            alpha = int(max_alpha * t * t)
            if alpha > 0:
                pixels[x, y] = (*color, alpha)
    image.alpha_composite(overlay)


def draw_round_cap(draw, point, width, fill):
    radius = width // 2
    x, y = point
    draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=fill)


def create_source():
    size = 1024
    image = Image.new("RGBA", (size, size), "#ffffff")
    draw = ImageDraw.Draw(image)

    def scaled(value):
        return int(round(512 + (value - 512) * ICON_SCALE))

    def scaled_box(box):
        return tuple(scaled(value) for value in box)

    def scaled_point(point):
        return tuple(scaled(value) for value in point)

    for index in range(size):
        t = index / (size - 1)
        r = int(255 * (1 - t) + 238 * t)
        g = int(255 * (1 - t) + 243 * t)
        b = int(255 * (1 - t) + 255 * t)
        draw.line((0, index, size, index), fill=(r, g, b, 255))

    radial_glow(
        image,
        center=(500, 500),
        radius=430,
        color=(92, 116, 235),
        max_alpha=28,
    )
    draw = ImageDraw.Draw(image)

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        scaled_box((230, 248, 822, 810)),
        radius=scaled(512 + 188) - 512,
        fill=(39, 70, 219, 98),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(scaled(512 + 20) - 512))
    image.alpha_composite(shadow)

    # Rounded terminal bubble.
    bubble = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bubble_draw = ImageDraw.Draw(bubble)
    bubble_box = scaled_box((230, 222, 822, 784))
    bubble_radius = scaled(512 + 188) - 512
    for y in range(bubble_box[1], bubble_box[3]):
        t = (y - bubble_box[1]) / (bubble_box[3] - bubble_box[1])
        r = int(184 * (1 - t) + 52 * t)
        g = int(181 * (1 - t) + 72 * t)
        b = int(255 * (1 - t) + 244 * t)
        bubble_draw.line((bubble_box[0], y, bubble_box[2], y), fill=(r, g, b, 255))
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(bubble_box, radius=bubble_radius, fill=255)
    image.alpha_composite(Image.composite(bubble, Image.new("RGBA", (size, size)), mask))

    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    highlight_draw = ImageDraw.Draw(highlight)
    highlight_draw.ellipse(scaled_box((300, 194, 752, 390)), fill=(255, 255, 255, 52))
    image.alpha_composite(highlight)
    draw = ImageDraw.Draw(image)

    stroke_width = scaled(512 + 52) - 512
    prompt_points = [scaled_point((366, 444)), scaled_point((466, 546)), scaled_point((366, 648))]
    draw.line(
        (*prompt_points[0], *prompt_points[1], *prompt_points[2]),
        fill="#edf6ff",
        width=stroke_width,
        joint="curve",
    )
    draw_round_cap(draw, prompt_points[0], stroke_width, "#edf6ff")
    draw_round_cap(draw, prompt_points[2], stroke_width, "#edf6ff")

    cursor_points = [scaled_point((552, 660)), scaled_point((718, 660))]
    draw.line((*cursor_points[0], *cursor_points[1]), fill="#edf6ff", width=stroke_width)
    draw_round_cap(draw, cursor_points[0], stroke_width, "#edf6ff")
    draw_round_cap(draw, cursor_points[1], stroke_width, "#edf6ff")

    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    image.save(SOURCE)
    return image


def save_png(image, path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    resized = image.resize((size, size), Image.Resampling.LANCZOS)
    if path.suffix.lower() == ".ico":
        resized.save(
            path,
            sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
        )
    else:
        resized.save(path)


def main():
    image = create_source()

    android = {
        "mipmap-mdpi/ic_launcher.png": 48,
        "mipmap-hdpi/ic_launcher.png": 72,
        "mipmap-xhdpi/ic_launcher.png": 96,
        "mipmap-xxhdpi/ic_launcher.png": 144,
        "mipmap-xxxhdpi/ic_launcher.png": 192,
    }
    for rel, size in android.items():
        save_png(image, ROOT / "android/app/src/main/res" / rel, size)

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
        save_png(image, ios_dir / name, size)

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
        save_png(image, macos_dir / name, size)

    web = {
        "favicon.png": 32,
        "icons/Icon-192.png": 192,
        "icons/Icon-512.png": 512,
        "icons/Icon-maskable-192.png": 192,
        "icons/Icon-maskable-512.png": 512,
    }
    for rel, size in web.items():
        save_png(image, ROOT / "web" / rel, size)

    save_png(image, ROOT / "windows/runner/resources/app_icon.ico", 256)


if __name__ == "__main__":
    main()

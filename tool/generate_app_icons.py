from pathlib import Path
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "brand" / "recodex_icon_1024.png"


def rounded_rectangle(draw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def create_source():
    size = 1024
    image = Image.new("RGBA", (size, size), "#f4f1ea")
    draw = ImageDraw.Draw(image)

    rounded_rectangle(draw, (72, 72, 952, 952), 196, "#f0ebdf")
    rounded_rectangle(draw, (198, 182, 826, 842), 112, "#24312b")
    rounded_rectangle(draw, (198, 182, 826, 366), 112, "#3f6f5a")
    draw.rectangle((198, 294, 826, 396), fill="#3f6f5a")

    for x, color in ((300, "#e9b872"), (374, "#d56f52"), (448, "#9fbea1")):
        draw.ellipse((x - 22, 274 - 22, x + 22, 274 + 22), fill=color)

    stroke = 56
    draw.line((378, 411, 306, 483, 378, 555), fill="#edf1e8", width=stroke, joint="curve")
    draw.line((646, 411, 718, 483, 646, 555), fill="#edf1e8", width=stroke, joint="curve")
    draw.line((556, 400, 468, 624), fill="#9fbea1", width=54)

    draw.line((330, 704, 694, 704), fill="#e9b872", width=42)
    draw.line((330, 704, 508, 704), fill="#edf1e8", width=42)

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

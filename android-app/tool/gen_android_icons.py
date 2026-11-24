"""生成 Android 各密度的启动图标资源。"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(HERE)
RES = os.path.join("..", "android", "app", "src", "main", "res")
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
SPLASH = {"mdpi": 96, "hdpi": 144, "xhdpi": 192, "xxhdpi": 288, "xxxhdpi": 384}


def ensure_dir(path):
    if not os.path.isdir(path):
        os.makedirs(path, exist_ok=True)


def save_square(src, out_path, size):
    img = Image.open(src).convert("RGBA").resize((size, size), Image.LANCZOS)
    img.save(out_path, "PNG")


def save_monochrome(src, out_path, size):
    img = Image.open(src).convert("RGBA").resize((size, size), Image.LANCZOS)
    mono = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mono.putalpha(img.getchannel("A"))
    mono.save(out_path, "PNG")


def main():
    assets = os.path.join("..", "assets")
    square = os.path.join(assets, "app_icon.png")
    foreground = os.path.join(assets, "app_icon_foreground.png")
    circle = os.path.join(assets, "app_icon_circle.png")
    for path in (square, foreground, circle):
        if not os.path.exists(path):
            print("missing asset: " + os.path.basename(path))
            return 1

    for density, size in LEGACY.items():
        folder = os.path.join(RES, "mipmap-" + density)
        ensure_dir(folder)
        save_square(square, os.path.join(folder, "ic_launcher.png"), size)

    for density, size in ADAPTIVE.items():
        folder = os.path.join(RES, "mipmap-" + density)
        ensure_dir(folder)
        save_square(foreground, os.path.join(folder, "ic_launcher_foreground.png"), size)
        save_monochrome(foreground, os.path.join(folder, "ic_launcher_monochrome.png"), size)

    for density, size in SPLASH.items():
        folder = os.path.join(RES, "drawable-" + density)
        ensure_dir(folder)
        save_square(circle, os.path.join(folder, "splash_logo.png"), size)

    ensure_dir(os.path.join(RES, "mipmap-anydpi-v26"))
    with open(os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml"), "w", encoding="utf-8") as f:
        f.write(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
            '    <background android:drawable="@color/ic_launcher_background"/>\n'
            '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
            '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
            "</adaptive-icon>\n"
        )

    # 背景色：Kelivo 的 values/colors.xml 里已经定义了 ic_launcher_background（纯白），
    # 这里只在缺失时才补，避免资源重复。
    colors_path = os.path.join(RES, "values", "colors.xml")
    has_background = False
    if os.path.exists(colors_path):
        with open(colors_path, encoding="utf-8") as f:
            has_background = "ic_launcher_background" in f.read()
    if not has_background:
        ensure_dir(os.path.join(RES, "values"))
        with open(os.path.join(RES, "values", "ic_launcher_background.xml"), "w", encoding="utf-8") as f:
            f.write(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                "<resources>\n"
                '    <color name="ic_launcher_background">#FFFFFF</color>\n'
                "</resources>\n"
            )

    print("android icons generated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

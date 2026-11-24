"""用 Chrome headless 把项目 SVG logo 渲染成 Android 图标母版。

输出（相对本脚本目录 tool/）：
  ../assets/app_icon.png            1024 纯白底方形图标
  ../assets/app_icon_foreground.png 1024 透明底自适应图标前景层
  ../assets/app_icon_circle.png     1024 圆形图标
"""
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.parse

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
os.chdir(HERE)
APP = os.path.join("..")
ASSETS = os.path.join(APP, "assets")
SRC_SVG = os.path.join(APP, "..", "素材", "logo.svg")
SIZE = 1024


def read_svg():
    with open(SRC_SVG, encoding="utf-8") as f:
        return f.read()


def page(svg, bg, logo_frac, radius=0):
    clip = ""
    if radius:
        clip = (
            "<div style='position:absolute;inset:0;background:#fff;"
            f"border-radius:{radius}px;overflow:hidden'></div>"
        )
    return (
        "<!doctype html><html><head><meta charset='utf-8'><style>"
        f"html,body{{margin:0;padding:0;width:{SIZE}px;height:{SIZE}px;overflow:hidden}}"
        f".stage{{position:relative;width:{SIZE}px;height:{SIZE}px;background:{bg};"
        "display:flex;align-items:center;justify-content:center}"
        f"svg{{width:{int(SIZE*logo_frac)}px;height:{int(SIZE*logo_frac)}px;display:block}}"
        "</style></head><body>"
        f"<div class='stage'>{clip}<div>{svg}</div></div>"
        "</body></html>"
    )


def shoot(html_text, out_png, transparent=False):
    out_png = os.path.abspath(out_png)
    if os.path.exists(out_png):
        os.remove(out_png)
    tmp = tempfile.mkdtemp(prefix="icon_")
    html_path = os.path.join(tmp, "icon.html")
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html_text)
    url = "file:///" + urllib.parse.quote(html_path.replace("\\", "/"), safe="/:")
    cmd = [
        CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--no-sandbox", "--force-device-scale-factor=1",
        f"--window-size={SIZE},{SIZE}",
        f"--screenshot={out_png}",
        "--default-background-color=" + ("00000000" if transparent else "FFFFFFFF"),
        url,
    ]
    log = os.path.join(tmp, "chrome.log")
    with open(log, "wb") as lf:
        subprocess.run(cmd, stdout=lf, stderr=lf, check=False, timeout=180)
    ok = os.path.exists(out_png) and os.path.getsize(out_png) > 1000
    if not ok:
        with open(log, encoding="utf-8", errors="ignore") as lf:
            sys.stdout.write(lf.read()[-1500:].encode("ascii", "replace").decode("ascii"))
        sys.stdout.write("FAILED: " + os.path.basename(out_png) + "\n")
    shutil.rmtree(tmp, ignore_errors=True)
    return ok


def main():
    if not os.path.exists(SRC_SVG):
        sys.stdout.write("logo.svg not found\n")
        return 1
    svg = read_svg()
    ok1 = shoot(page(svg, "transparent", 0.62),
                os.path.join(ASSETS, "app_icon_foreground.png"), True)
    ok2 = shoot(page(svg, "#FFFFFF", 0.78), os.path.join(ASSETS, "app_icon.png"))
    ok3 = shoot(page(svg, "#FFFFFF", 0.68, radius=SIZE // 2),
                os.path.join(ASSETS, "app_icon_circle.png"))
    sys.stdout.write("foreground=%s square=%s circle=%s\n" % (ok1, ok2, ok3))
    return 0 if (ok1 and ok2 and ok3) else 1


if __name__ == "__main__":
    sys.exit(main())

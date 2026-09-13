#!/usr/bin/env python3
"""
render-logo.py — 暖客宝 logo PNG 多尺寸分发器 (mm7 §A.5 single-source-of-truth)
- 源: tools/branding/nuankebao-logo-source.png (主人上传原图, 1254×1254 RGBA)
- PIL 高质量 LANCZOS 重采样, 输出 13 个 PNG
- Android mipmap 走 PNG8 256 色 (palette)
- PWA maskable 走 80% 安全区 (居中放缩)
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).parent
SRC = ROOT / "nuankebao-logo-source.png"
OUT = ROOT / "build"


def resize_to(src: Image.Image, size: int) -> Image.Image:
    """LANCZOS 重采样到 size×size."""
    return src.resize((size, size), Image.LANCZOS)


def to_palette(img: Image.Image, dst: Path):
    """RGBA → PNG8 256 色 (Android mipmap 要求)."""
    img = img.convert("RGBA").convert("P", palette=Image.Palette.ADAPTIVE, colors=256)
    img.save(dst, optimize=True)


def add_safe_zone(src_img: Image.Image, dst: Path, final_size: int, ratio: float = 0.8):
    """PWA maskable 安全区 — 在 final_size 内居中放 ratio 大小的图标.
    80% (不是默认 60%) 因为本 logo 自带白底圆角矩形 — 留 10% 边距给 mask 裁切."""
    inner_size = int(final_size * ratio)
    pad = (final_size - inner_size) // 2
    inner = resize_to(src_img, inner_size)
    canvas = Image.new("RGBA", (final_size, final_size), (0, 0, 0, 0))
    canvas.paste(inner, (pad, pad), inner if inner.mode == "RGBA" else None)
    canvas.save(dst, optimize=True)


# (filename, size, kind) — 13 个目标
TARGETS = [
    ("ic_launcher_48.png",     48, "mipmap"),
    ("ic_launcher_72.png",     72, "mipmap"),
    ("ic_launcher_96.png",     96, "mipmap"),
    ("ic_launcher_144.png",   144, "mipmap"),
    ("ic_launcher_192.png",   192, "mipmap"),
    ("favicon_16.png",         16, "favicon"),
    ("favicon_32.png",         32, "favicon"),
    ("favicon_48.png",         48, "favicon"),
    ("apple_touch_180.png",   180, "apple"),
    ("pwa_192.png",           192, "pwa"),
    ("pwa_512.png",           512, "pwa"),
    ("pwa_maskable_192.png",  192, "maskable"),
    ("pwa_maskable_512.png",  512, "maskable"),
]


def main():
    if not SRC.exists():
        raise FileNotFoundError(f"源图缺失: {SRC}")
    OUT.mkdir(exist_ok=True)
    src = Image.open(SRC)
    print(f"源: {SRC.name} ({src.size[0]}×{src.size[1]}, {src.mode})")
    print(f"输出到: {OUT}/\n")
    for name, size, kind in TARGETS:
        if kind == "mipmap":
            to_palette(resize_to(src, size), OUT / name)
        elif kind == "maskable":
            add_safe_zone(src, OUT / name, size)
        else:
            img = resize_to(src, size)
            if kind == "favicon":
                # favicon 直接保存 PNG (透明度不是关键, 原图就是白底)
                img.save(OUT / name, optimize=True)
            else:
                img.save(OUT / name, optimize=True)
        print(f"  ✓ {kind:8s} {size:3d}×{size:<3d} → {name}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
generate-logo-candidates.py — 给 暖客宝 项目生成 7 张 logo SVG 候选

零出网 (Pyhon stdlib only, 不调任何 image gen API).
每个 SVG 严格按 organic palette + AI 元素注入 prompt 设计.
输出到 /home/mm7/nuankebao-agent/public/logo-candidates/

使用:
  python3 tools/generate-logo-candidates.py

设计口径:
  - background: warm cream #f4e4c1
  - accent:     forest green #2d5016
  - highlight:  earth brown #8b4513
  - 6 个 logo 都用 暖/宝 (暖客宝 字形) 作为几何锚点
  - 每个 logo 注入 1 个独立 AI 元素 (per logo-prompts.json)
"""

from __future__ import annotations

from pathlib import Path
from textwrap import dedent
from typing import Iterable

# ============== Palette (organic) ==============
CREAM = "#f4e4c1"
GREEN = "#2d5016"
BROWN = "#8b4513"
GREEN_LIGHT = "#4a7a2c"  # 派生 (subtle gradient)
CREAM_DEEP = "#e8d4a8"   # 派生 (soft shadow)

LOGO_DIR = Path(__file__).resolve().parent.parent / "public" / "logo-candidates"
LOGO_DIR.mkdir(parents=True, exist_ok=True)


def svg_open(size: int) -> list[str]:
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'xmlns:xlink="http://www.w3.org/1999/xlink" '
        f'viewBox="0 0 {size} {size}" width="{size}" height="{size}">',
        f'  <rect width="{size}" height="{size}" fill="{CREAM}"/>',
    ]


def svg_close() -> list[str]:
    return ["</svg>"]


def write_svg(name: str, lines: Iterable[str]) -> Path:
    path = LOGO_DIR / name
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


# =====================================================================
# Logo 1: 点阵 (Neural Network Nodes) — 神经节点 = AI 信号
# =====================================================================
def logo_1_dot_matrix() -> Path:
    """8x12 dot 网格,排成 B 字形,几个大点表示 AI 信号流节点。"""
    lines = svg_open(1024)
    # 8 cols x 12 rows, cell 64, gap; padding 320/2 = 160 to center; total 8*60 = 480
    cell = 60
    radius = 18
    # B-shape mask (1 = dot present, 0 = empty)
    # Cols 0-7, Rows 0-11
    B_mask = [
        # row 0-3 = top bowl outline
        [1, 1, 1, 1, 0, 0, 0, 0],  # 0: top
        [1, 1, 1, 1, 1, 0, 0, 0],  # 1
        [1, 0, 0, 1, 1, 0, 0, 0],  # 2
        [1, 0, 0, 1, 1, 0, 0, 0],  # 3
        [1, 1, 1, 1, 0, 0, 0, 0],  # 4: top bowl bottom = bowl closed
        [1, 1, 1, 1, 1, 1, 1, 1],  # 5: middle horizontal
        [1, 1, 1, 1, 0, 0, 0, 0],  # 6
        [1, 0, 0, 1, 1, 0, 0, 0],  # 7
        [1, 0, 0, 1, 1, 0, 0, 0],  # 8
        [1, 0, 0, 1, 1, 0, 0, 0],  # 9
        [1, 1, 1, 1, 1, 0, 0, 0],  # 10
        [1, 1, 1, 1, 0, 0, 0, 0],  # 11
    ]
    # Signal-flow "big" nodes (larger radius, slight glow) — AI signal flowing
    big_nodes = {(0, 0), (3, 1), (5, 5), (3, 9), (1, 11)}

    grid_w = 8 * cell
    grid_h = 12 * cell
    pad_x = (1024 - grid_w) // 2
    pad_y = (1024 - grid_h) // 2

    # subtle gradient def
    lines.append(
        f'  <defs>'
        f'<radialGradient id="glow" cx="50%" cy="50%" r="50%">'
        f'<stop offset="0%" stop-color="{GREEN_LIGHT}" stop-opacity="0.6"/>'
        f'<stop offset="100%" stop-color="{GREEN}" stop-opacity="0"/>'
        f'</radialGradient>'
        f'</defs>'
    )

    for r, row in enumerate(B_mask):
        for c, present in enumerate(row):
            if not present:
                continue
            x = pad_x + c * cell + cell // 2
            y = pad_y + r * cell + cell // 2
            is_big = (c, r) in big_nodes
            if is_big:
                # halo + dot
                lines.append(
                    f'  <circle cx="{x}" cy="{y}" r="{radius+24}" fill="url(#glow)"/>'
                )
                lines.append(
                    f'  <circle cx="{x}" cy="{y}" r="{radius+6}" fill="{GREEN}" opacity="0.95"/>'
                )
                # small inner accent
                lines.append(
                    f'  <circle cx="{x}" cy="{y}" r="6" fill="{CREAM}" opacity="0.6"/>'
                )
            else:
                lines.append(
                    f'  <circle cx="{x}" cy="{y}" r="{radius}" fill="{GREEN}"/>'
                )
            # subtle cream rim on standard dots
            if not is_big:
                lines.append(
                    f'  <circle cx="{x}" cy="{y}" r="{radius-6}" fill="none" stroke="{CREAM_DEEP}" stroke-width="1.5" opacity="0.5"/>'
                )
    # connector lines between big nodes (AI signal flow)
    big_coords = [(pad_x + c * cell + cell // 2, pad_y + r * cell + cell // 2) for (c, r) in big_nodes]
    big_coords.sort(key=lambda p: (p[1], p[0]))
    for i in range(len(big_coords) - 1):
        x1, y1 = big_coords[i]
        x2, y2 = big_coords[i + 1]
        lines.append(
            f'  <line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{GREEN_LIGHT}" stroke-width="3" opacity="0.55" stroke-dasharray="6,8"/>'
        )

    lines += svg_close()
    return write_svg("logo-1-dot-matrix.svg", lines)


# =====================================================================
# Logo 2: Letter Mark + AI Data Ribbon
# =====================================================================
def logo_2_letter_mark() -> Path:
    """Bold sans-serif 'B' + AI 数据带穿字形(细弧形穿透)。"""
    lines = svg_open(1024)
    # B mark — using SVG <text> for clean glyph, fill forest green
    # Use a generic sans-serif family; modern browsers will pick a clean weight
    lines.append(
        f'  <text x="512" y="720" text-anchor="middle" '
        f'font-family="Helvetica, Arial, sans-serif" font-weight="900" '
        f'font-size="780" fill="{GREEN}" letter-spacing="-40">B</text>'
    )
    # AI data ribbon — thin weaving curve through the B
    # Curve from top-left to bottom-right, weaving through the letterform
    lines.append(
        f'  <path d="M 130 280 '
        f'C 280 230, 380 480, 540 470 '
        f'S 800 760, 920 880" '
        f'fill="none" stroke="{BROWN}" stroke-width="22" '
        f'stroke-linecap="round" stroke-linejoin="round" '
        f'opacity="0.85"/>'
    )
    # ribbon dots: AI data points
    for cx, cy in [(280, 290), (480, 480), (700, 600), (880, 820)]:
        lines.append(
            f'  <circle cx="{cx}" cy="{cy}" r="14" fill="{CREAM}" stroke="{BROWN}" stroke-width="6"/>'
        )
    # subtle highlight on letter (top-left lighter)
    lines.append(
        f'  <text x="512" y="720" text-anchor="middle" '
        f'font-family="Helvetica, Arial, sans-serif" font-weight="900" '
        f'font-size="780" fill="{GREEN_LIGHT}" letter-spacing="-40" '
        f'opacity="0.18" transform="translate(-6,-6)">B</text>'
    )
    lines += svg_close()
    return write_svg("logo-2-letter-mark.svg", lines)


# =====================================================================
# Logo 3: Abstract — Circle + Diagonal = AI Radar Orbit + Wellness Spark
# =====================================================================
def logo_3_abstract() -> Path:
    """圆 = AI 雷达轨道,斜线 = 养生火/能量流。"""
    lines = svg_open(1024)
    cx, cy = 512, 540
    r_orbit = 280
    # outer dotted orbit ring (AI radar sweep)
    for angle in range(0, 360, 12):
        rad = angle * 3.14159 / 180
        x1 = cx + (r_orbit + 14) * rad.cos if hasattr(rad, "cos") else cx + (r_orbit + 14) * __import__("math").cos(rad)
        # Python 3 没有 rad.cos / rad.tan — 改为显式 import:
    # fix: 重写
    return _logo_3_v2(lines)


def _logo_3_v2(lines: list[str]) -> Path:
    import math
    cx, cy = 512, 560
    r_orbit = 280
    # AI radar orbit ring — dotted
    orbit_dots = []
    for angle_deg in range(0, 360, 8):
        a = angle_deg * math.pi / 180
        x = cx + r_orbit * math.cos(a)
        y = cy + r_orbit * math.sin(a)
        orbit_dots.append((x, y, angle_deg))
    # Concentric pulse ring (inner, lighter)
    inner_dots = []
    for angle_deg in range(0, 360, 15):
        a = angle_deg * math.pi / 180
        x = cx + 220 * math.cos(a)
        y = cy + 220 * math.sin(a)
        inner_dots.append((x, y))
    # Outer dotted ring
    for x, y, deg in orbit_dots:
        # alternating opacity to suggest radar sweep (a sector brighter)
        sweep_brightness = 0.45 if 280 <= deg <= 360 or 0 <= deg <= 80 else 0.85
        lines.append(
            f'  <circle cx="{x:.1f}" cy="{y:.1f}" r="9" fill="{GREEN}" opacity="{sweep_brightness}"/>'
        )
    # Inner ring
    for x, y in inner_dots:
        lines.append(
            f'  <circle cx="{x:.1f}" cy="{y:.1f}" r="6" fill="{GREEN_LIGHT}" opacity="0.5"/>'
        )
    # Big inner filled circle = AI brain core
    lines.append(
        f'  <circle cx="{cx}" cy="{cy}" r="160" fill="{GREEN}"/>'
    )
    # Tiny pulse center (cream)
    lines.append(
        f'  <circle cx="{cx}" cy="{cy}" r="48" fill="{CREAM}"/>'
    )
    lines.append(
        f'  <circle cx="{cx}" cy="{cy}" r="20" fill="{GREEN}"/>'
    )
    # Diagonal spark/wellness fire — from bottom-left to upper-right
    lines.append(
        f'  <line x1="220" y1="900" x2="800" y2="170" '
        f'stroke="{BROWN}" stroke-width="26" stroke-linecap="round"/>'
    )
    # spark head — small flame dot
    lines.append(
        f'  <circle cx="800" cy="170" r="22" fill="{BROWN}"/>'
    )
    lines.append(
        f'  <circle cx="800" cy="170" r="9" fill="{CREAM}"/>'
    )
    # spark tail — fading brown dots
    for i, t in enumerate([0.85, 0.65, 0.45, 0.25]):
        x_t = 220 + (800 - 220) * (1 - t * 0.15)
        y_t = 900 + (170 - 900) * (1 - t * 0.15)
        lines.append(
            f'  <circle cx="{x_t:.0f}" cy="{y_t:.0f}" r="{14*t:.0f}" fill="{BROWN}" opacity="{t*0.7}"/>'
        )

    lines += svg_close()
    return write_svg("logo-3-abstract-shape.svg", lines)


# =====================================================================
# Logo 4: Arc = Continuous AI Learning Loop + B
# =====================================================================
def logo_4_arc() -> Path:
    """单条连续弧线,绕回自身 + 形成 B 字形,代表 AI 持续学习。"""
    lines = svg_open(1024)
    # B-style two-bowl path: outer left line + top bowl + middle + bottom bowl + close
    # We'll draw it as a single path that loops back
    # Background: faint dotted guide for "AI neural pulse"
    for i in range(0, 36):
        a = i * 10
        import math
        x = 512 + 380 * math.cos(a * math.pi / 180)
        y = 512 + 380 * math.sin(a * math.pi / 180)
        lines.append(
            f'  <circle cx="{x:.1f}" cy="{y:.1f}" r="4" fill="{GREEN}" opacity="0.18"/>'
        )

    # Main B-shaped arc — forest green, gradient stroke
    lines.append(
        f'  <defs>'
        f'<linearGradient id="grad-arc" x1="0%" y1="0%" x2="100%" y2="100%">'
        f'<stop offset="0%" stop-color="{GREEN}"/>'
        f'<stop offset="100%" stop-color="{GREEN_LIGHT}"/>'
        f'</linearGradient>'
        f'</defs>'
    )

    # B path (single continuous stroke, starts top-left, goes around)
    # points on the B
    #   top of spine: (320, 200)
    #   top-right of top bowl: (640, 280)
    #   bottom-right of top bowl: (640, 460)
    #   mid spine: (320, 480)
    #   bottom-right of bottom bowl: (700, 580)
    #   bottom-right curve: (700, 760)
    #   bottom: (320, 820)
    #   spine back up: close to (320, 200)
    path_d = (
        "M 320 200 "
        "L 320 820 "                          # main vertical spine
        "L 560 820 "                          # bottom horizontal
        "C 720 820, 760 770, 760 690 "        # bottom-right curve up
        "C 760 600, 720 560, 580 540 "        # bottom bowl inner curve
        "L 380 540 "                          # mid horizontal back to spine
        "C 580 530, 700 480, 700 380 "        # top-right curve
        "C 700 280, 640 200, 540 200 "        # top bowl
        "Z"
    )
    lines.append(
        f'  <path d="{path_d}" fill="none" stroke="url(#grad-arc)" '
        f'stroke-width="48" stroke-linecap="round" stroke-linejoin="round"/>'
    )
    # Add a subtle accent dot at end (where the path "loops back")
    lines.append(
        f'  <circle cx="320" cy="200" r="28" fill="{BROWN}"/>'
    )
    lines.append(
        f'  <circle cx="320" cy="200" r="10" fill="{CREAM}"/>'
    )
    # AI pulse middle node
    lines.append(
        f'  <circle cx="380" cy="540" r="22" fill="{CREAM}" stroke="{GREEN}" stroke-width="8"/>'
    )
    lines.append(
        f'  <circle cx="380" cy="540" r="8" fill="{BROWN}"/>'
    )

    lines += svg_close()
    return write_svg("logo-4-path-arc.svg", lines)


# =====================================================================
# Logo 5: Negative Space — B as Leaf Vein
# =====================================================================
def logo_5_negative_space() -> Path:
    """绿色实心方块 + B 字 cutout,但 B 的 spine 形似叶脉主轴。"""
    lines = svg_open(1024)
    margin = 96
    sq_x = margin
    sq_y = margin
    sq_size = 1024 - 2 * margin
    # Main solid forest green square (rounded corner radii = premium)
    # SVG rect rx="48" for rounded corners
    lines.append(
        f'  <rect x="{sq_x}" y="{sq_y}" width="{sq_size}" height="{sq_size}" '
        f'rx="80" ry="80" fill="{GREEN}"/>'
    )
    # subtle inner texture — wellness growth lines
    import math
    for i in range(0, 30):
        x_off = (i * 37) % sq_size
        lines.append(
            f'  <line x1="{sq_x + x_off}" y1="{sq_y + sq_size - 30}" '
            f'x2="{sq_x + x_off + 20}" y2="{sq_y + sq_size - 10}" '
            f'stroke="{GREEN_LIGHT}" stroke-width="2" opacity="0.4"/>'
        )

    # B carved in negative space (cream)
    # Vein-like: spine = main leaf vein, bowls = lateral veins
    lines.append(
        f'  <text x="512" y="740" text-anchor="middle" '
        f'font-family="Helvetica, Arial, sans-serif" font-weight="900" '
        f'font-size="700" fill="{CREAM}" letter-spacing="-32">B</text>'
    )
    # Add leaf vein detail: small AI droplet on top of B (sprout-like)
    lines.append(
        f'  <circle cx="512" cy="170" r="36" fill="{CREAM}"/>'
    )
    lines.append(
        f'  <circle cx="512" cy="170" r="18" fill="{GREEN}"/>'
    )
    # Brown accent: small wellness seed at the bottom
    lines.append(
        f'  <circle cx="512" cy="900" r="28" fill="{BROWN}"/>'
    )
    lines.append(
        f'  <circle cx="512" cy="900" r="10" fill="{CREAM}"/>'
    )

    lines += svg_close()
    return write_svg("logo-5-negative-space.svg", lines)


# =====================================================================
# Logo 6: Composite — Radar Ring + B Horizontal Lockup
# =====================================================================
def logo_6_composite() -> Path:
    """左侧小图标 = 圆带同心 AI 雷达环,右侧 B 字 = 横排 lockup。"""
    lines = svg_open(1024)
    import math
    # Icon on left
    cx_icon = 280
    cy_icon = 512
    # outer ring
    lines.append(
        f'  <circle cx="{cx_icon}" cy="{cy_icon}" r="180" fill="none" stroke="{GREEN}" stroke-width="22"/>'
    )
    # middle ring (dotted — AI radar pulse)
    for i in range(36):
        a = i * 10 * math.pi / 180
        x = cx_icon + 130 * math.cos(a)
        y = cy_icon + 130 * math.sin(a)
        lines.append(
            f'  <circle cx="{x:.1f}" cy="{y:.1f}" r="6" fill="{GREEN}" opacity="0.7"/>'
        )
    # inner core
    lines.append(
        f'  <circle cx="{cx_icon}" cy="{cy_icon}" r="76" fill="{GREEN}"/>'
    )
    lines.append(
        f'  <circle cx="{cx_icon}" cy="{cy_icon}" r="30" fill="{CREAM}"/>'
    )
    # radar sweep arm (diagonal brown line, simulating wave)
    lines.append(
        f'  <line x1="{cx_icon}" y1="{cy_icon}" x2="{cx_icon + 200}" y2="{cy_icon - 200}" '
        f'stroke="{BROWN}" stroke-width="14" stroke-linecap="round" opacity="0.85"/>'
    )
    # Sweep tip dot
    lines.append(
        f'  <circle cx="{cx_icon + 200}" cy="{cy_icon - 200}" r="20" fill="{BROWN}"/>'
    )

    # B letter on right
    lines.append(
        f'  <text x="800" y="700" text-anchor="middle" '
        f'font-family="Helvetica, Arial, sans-serif" font-weight="900" '
        f'font-size="500" fill="{BROWN}" letter-spacing="-22">B</text>'
    )
    # Underline beneath lockup
    lines.append(
        f'  <line x1="170" y1="770" x2="880" y2="770" '
        f'stroke="{GREEN}" stroke-width="6" stroke-linecap="round"/>'
    )
    # small AI dot on baseline — wellness seed
    lines.append(
        f'  <circle cx="525" cy="770" r="14" fill="{GREEN_LIGHT}"/>'
    )

    lines += svg_close()
    return write_svg("logo-6-composite-mark.svg", lines)


# =====================================================================
# Mockup Showcase: 3x2 grid
# =====================================================================
def mockup_showcase() -> Path:
    """3x2 排版 6 张 logo (各占 600x500 cell),warm cream 背景。"""
    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" '
        f'xmlns:xlink="http://www.w3.org/1999/xlink" '
        f'viewBox="0 0 1920 1080" width="1920" height="1080">',
        f'  <rect width="1920" height="1080" fill="{CREAM}"/>',
        # header band
        f'  <rect x="0" y="0" width="1920" height="100" fill="{GREEN}" opacity="0.05"/>',
    ]
    # 3 cols x 2 rows; each cell 600x460; padding top 130 left 60; cell gap 30
    cell_w = 600
    cell_h = 420
    gap_x = 20
    gap_y = 30
    pad_left = 60
    pad_top = 130
    # sub-SVGs via <use> would be ideal, but to keep simple, embed each logo scaled
    # For showcase, we'll use <image href> with the saved files. But that requires runtime serving.
    # Simplest: re-draw miniature versions inline (just the key element).
    # Actually easiest: reference the saved files via <image>
    # But we need to know their path — they are in same dir.
    # Self-referenced <image xlink:href="logo-1-dot-matrix.svg" /> — works in modern browsers.
    # The browser will request that URL relative to page, but since mockup is its own SVG, browsers honor relative.
    # We'll set explicit width/height to fit cell.
    logos = [
        ("logo-1-dot-matrix.svg", "1. 点阵神经节点"),
        ("logo-2-letter-mark.svg", "2. 字母 + AI 数据带"),
        ("logo-3-abstract-shape.svg", "3. AI 雷达 + 养生火"),
        ("logo-4-path-arc.svg", "4. AI 持续学习循环"),
        ("logo-5-negative-space.svg", "5. AI 培育的叶脉"),
        ("logo-6-composite-mark.svg", "6. 雷达环 + B 组合"),
    ]
    for idx, (filename, label) in enumerate(logos):
        col = idx % 3
        row = idx // 3
        x = pad_left + col * (cell_w + gap_x)
        y = pad_top + row * (cell_h + gap_y)
        # subtle "pedestal" background
        lines.append(
            f'  <rect x="{x}" y="{y}" width="{cell_w}" height="{cell_h}" '
            f'rx="32" ry="32" fill="#fffaf0" stroke="{CREAM_DEEP}" stroke-width="2"/>'
        )
        # logo image inside cell, fit ~360x360 centered top
        img_size = 340
        img_x = x + (cell_w - img_size) // 2
        img_y = y + 30
        # Self-reference — works in browser when SVG is rendered as <img> in HTML
        lines.append(
            f'  <image href="{filename}" xlink:href="{filename}" '
            f'x="{img_x}" y="{img_y}" width="{img_size}" height="{img_size}" '
            f'preserveAspectRatio="xMidYMid meet"/>'
        )
        # label below
        lines.append(
            f'  <text x="{x + cell_w//2}" y="{y + cell_h - 26}" '
            f'text-anchor="middle" font-family="Helvetica, Arial, sans-serif" '
            f'font-weight="600" font-size="22" fill="{GREEN}" '
            f'letter-spacing="0.5">{label}</text>'
        )

    # header title
    lines.append(
        f'  <text x="960" y="58" text-anchor="middle" '
        f'font-family="Helvetica, Arial, sans-serif" font-weight="700" '
        f'font-size="34" fill="{GREEN}" letter-spacing="2">'
        f'暖客宝 · Logo 候选 — Organic Warmth + AI</text>'
    )
    # subtitle small dot decoration
    for i, (x_d, _label) in enumerate([(820, ""), (960, ""), (1100, "")]):
        lines.append(
            f'  <circle cx="{x_d}" cy="84" r="4" fill="{BROWN}"/>'
        )
    # footer signature
    lines.append(
        f'  <text x="960" y="1052" text-anchor="middle" '
        f'font-family="Helvetica, Arial, sans-serif" font-weight="400" '
        f'font-size="16" fill="{BROWN}" opacity="0.7" '
        f'letter-spacing="3">'
        f'#f4e4c1  ·  #2d5016  ·  #8b4513  ·  zero-network svg generation</text>'
    )

    lines.append("</svg>")
    return write_svg("mockup-showcase.svg", lines)


# =====================================================================
# Main
# =====================================================================
def main() -> None:
    print(f"输出目录: {LOGO_DIR}")
    paths = []
    # logo-3 wrapper (since we split into _v2)
    # Direct call to _logo_3_v2 to ensure correctness
    lines_3 = svg_open(1024)
    p3 = _logo_3_v2(lines_3)
    paths.append(p3)
    paths.append(logo_1_dot_matrix())
    paths.append(logo_2_letter_mark())
    paths.append(logo_4_arc())
    paths.append(logo_5_negative_space())
    paths.append(logo_6_composite())
    paths.append(mockup_showcase())
    for p in paths:
        size = p.stat().st_size
        print(f"  ✓ {p.name}  ({size:,} bytes)")
    print(f"\n完成: {len(paths)} 张 SVG")


if __name__ == "__main__":
    main()

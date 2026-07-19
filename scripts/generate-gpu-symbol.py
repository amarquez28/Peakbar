#!/usr/bin/env python3
"""Generate GPUIcon.symbolset (custom SF Symbol) for the compact-mode GPU glyph.

The glyph is the two-fan graphics card from design/GPUIcon.svg. It is emitted
as a custom SF Symbol rather than a template imageset because only real symbol
images get the menu bar's automatic tinting and inactive-screen dimming when
embedded in an NSStatusItem attributed title.

The GEOMETRY constants below mirror design/GPUIcon.svg (30x18 canvas). If that
design changes shape, update them here and re-run (scripts/generate-icons.sh
calls this automatically). Strokes are converted to filled rings (outer subpath
clockwise, hole counter-clockwise -> nonzero fill), which is what the SF Symbol
pipeline expects. Ultralight/Black variants just use thinner/thicker strokes.
"""

import os

K = 0.5522847498307936  # circle-from-cubics kappa

# ---- SF Symbol template geometry (from an SF Symbols app export) ------------
# Artwork lives on the M row: actool requires the Regular-M glyph at minimum.
CAPLINE_M, BASELINE_M = 1055.54, 1126.0
CAP = BASELINE_M - CAPLINE_M
CENTER_Y = (CAPLINE_M + BASELINE_M) / 2
CENTERS = {"Ultralight-M": 559.711, "Regular-M": 1449.84, "Black-M": 2933.4}
MARGIN_Y = (1030.785, 1150.121)

# ---- Source geometry: design/GPUIcon.svg (30 x 18, y-down) -------------------
CARD_X0, CARD_X1 = 2.5, 27.5
CARD_Y0, CARD_Y1 = 3.5, 14.5
CARD_R = 2.2
FANS = [(10.0, 9.0), (20.0, 9.0)]
FAN_R = 3.4
SRC_CX, SRC_CY = 15.0, 9.0

REGULAR_W = 1.7
SCALE = CAP / (CARD_Y1 - CARD_Y0 + REGULAR_W)  # regular stroked height == cap height

# (stroke width, hub dot radius, fan circle centerline radius) per weight.
# Black shrinks the fans slightly so the thicker ring stays inside the card.
WEIGHTS = {
    "Ultralight-M": (0.93, 0.73, FAN_R),
    "Regular-M":    (REGULAR_W, 1.0, FAN_R),
    "Black-M":      (2.40, 1.27, 3.07),
}


def fmt(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


def rounded_rect(pts, x0, y0, x1, y1, r, cw=True):
    c = K * r
    if cw:
        p = (f"M{fmt(x0+r)} {fmt(y0)}"
             f"L{fmt(x1-r)} {fmt(y0)}"
             f"C{fmt(x1-r+c)} {fmt(y0)} {fmt(x1)} {fmt(y0+r-c)} {fmt(x1)} {fmt(y0+r)}"
             f"L{fmt(x1)} {fmt(y1-r)}"
             f"C{fmt(x1)} {fmt(y1-r+c)} {fmt(x1-r+c)} {fmt(y1)} {fmt(x1-r)} {fmt(y1)}"
             f"L{fmt(x0+r)} {fmt(y1)}"
             f"C{fmt(x0+r-c)} {fmt(y1)} {fmt(x0)} {fmt(y1-r+c)} {fmt(x0)} {fmt(y1-r)}"
             f"L{fmt(x0)} {fmt(y0+r)}"
             f"C{fmt(x0)} {fmt(y0+r-c)} {fmt(x0+r-c)} {fmt(y0)} {fmt(x0+r)} {fmt(y0)}Z")
    else:
        p = (f"M{fmt(x0+r)} {fmt(y0)}"
             f"C{fmt(x0+r-c)} {fmt(y0)} {fmt(x0)} {fmt(y0+r-c)} {fmt(x0)} {fmt(y0+r)}"
             f"L{fmt(x0)} {fmt(y1-r)}"
             f"C{fmt(x0)} {fmt(y1-r+c)} {fmt(x0+r-c)} {fmt(y1)} {fmt(x0+r)} {fmt(y1)}"
             f"L{fmt(x1-r)} {fmt(y1)}"
             f"C{fmt(x1-r+c)} {fmt(y1)} {fmt(x1)} {fmt(y1-r+c)} {fmt(x1)} {fmt(y1-r)}"
             f"L{fmt(x1)} {fmt(y0+r)}"
             f"C{fmt(x1)} {fmt(y0+r-c)} {fmt(x1-r+c)} {fmt(y0)} {fmt(x1-r)} {fmt(y0)}Z")
    pts.append(p)


def circle(pts, cx, cy, r, cw=True):
    c = K * r
    if cw:
        p = (f"M{fmt(cx)} {fmt(cy-r)}"
             f"C{fmt(cx+c)} {fmt(cy-r)} {fmt(cx+r)} {fmt(cy-c)} {fmt(cx+r)} {fmt(cy)}"
             f"C{fmt(cx+r)} {fmt(cy+c)} {fmt(cx+c)} {fmt(cy+r)} {fmt(cx)} {fmt(cy+r)}"
             f"C{fmt(cx-c)} {fmt(cy+r)} {fmt(cx-r)} {fmt(cy+c)} {fmt(cx-r)} {fmt(cy)}"
             f"C{fmt(cx-r)} {fmt(cy-c)} {fmt(cx-c)} {fmt(cy-r)} {fmt(cx)} {fmt(cy-r)}Z")
    else:
        p = (f"M{fmt(cx)} {fmt(cy-r)}"
             f"C{fmt(cx-c)} {fmt(cy-r)} {fmt(cx-r)} {fmt(cy-c)} {fmt(cx-r)} {fmt(cy)}"
             f"C{fmt(cx-r)} {fmt(cy+c)} {fmt(cx-c)} {fmt(cy+r)} {fmt(cx)} {fmt(cy+r)}"
             f"C{fmt(cx+c)} {fmt(cy+r)} {fmt(cx+r)} {fmt(cy+c)} {fmt(cx+r)} {fmt(cy)}"
             f"C{fmt(cx+r)} {fmt(cy-c)} {fmt(cx+c)} {fmt(cy-r)} {fmt(cx)} {fmt(cy-r)}Z")
    pts.append(p)


def variant_path(cx_dest, stroke_w, dot_r, fan_r):
    h = stroke_w / 2

    def X(x): return cx_dest + (x - SRC_CX) * SCALE
    def Y(y): return CENTER_Y + (y - SRC_CY) * SCALE

    pts = []
    rounded_rect(pts, X(CARD_X0 - h), Y(CARD_Y0 - h), X(CARD_X1 + h), Y(CARD_Y1 + h),
                 (CARD_R + h) * SCALE, True)
    rounded_rect(pts, X(CARD_X0 + h), Y(CARD_Y0 + h), X(CARD_X1 - h), Y(CARD_Y1 - h),
                 max(CARD_R - h, 0.2) * SCALE, False)
    for fx, fy in FANS:
        circle(pts, X(fx), Y(fy), (fan_r + h) * SCALE, True)
        circle(pts, X(fx), Y(fy), (fan_r - h) * SCALE, False)
        circle(pts, X(fx), Y(fy), dot_r * SCALE, True)
    return "".join(pts), X(CARD_X0 - h), X(CARD_X1 + h)


H_REF_D = ("M0.993654 0L3.63775 0L29.3281-67.1323L30.0303-67.1323L30.0303-70.459"
           "L28.1226-70.459ZM11.6885-24.4799L46.9815-24.4799L46.2315-26.7285"
           "L12.4385-26.7285ZM55.1196 0L57.7637 0L30.6382-70.459L29.4326-70.459"
           "L29.4326-67.1323Z")

TXT = 'style="stroke:none;fill:black;font-family:sans-serif;font-size:13px;'
GUIDE = 'style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;"'

lines = []
lines.append('<?xml version="1.0" encoding="UTF-8"?>')
lines.append('<svg width="3300" height="2200" version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">')
lines.append(' <g id="Notes">')
lines.append('  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>')
lines.append('  <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" y1="292" x2="3036" y2="292"/>')
lines.append(f'  <text {TXT}font-weight:bold;" x="263" y="322">Weight/Scale Variations</text>')
for name, cx in [("Ultralight", 559.711), ("Regular", 1449.84), ("Black", 2933.4)]:
    lines.append(f'  <text {TXT}text-anchor:middle;" x="{cx}" y="322">{name}</text>')
lines.append('  <line style="fill:none;stroke:black;opacity:1;stroke-width:0.5;" x1="263" y1="1903" x2="3036" y2="1903"/>')
lines.append(f'  <text {TXT}font-weight:bold;" x="263" y="1953">Design Variations</text>')
lines.append(f'  <text {TXT}" x="263" y="1971">Symbols are supported in up to nine weights and three scales.</text>')
lines.append(f'  <text {TXT}" x="263" y="1989">For optimal layout with text and other symbols, vertically align</text>')
lines.append(f'  <text {TXT}" x="263" y="2007">symbols with the adjacent text.</text>')
lines.append(f'  <text {TXT}text-anchor:end;" x="3036" y="1933">Template v.6.0</text>')
lines.append(f'  <text {TXT}text-anchor:end;" x="3036" y="1951">Requires Xcode 16 or greater</text>')
lines.append(f'  <text {TXT}text-anchor:end;" x="3036" y="1969">Generated from design/GPUIcon.svg</text>')
lines.append(f'  <text {TXT}" x="263" y="726">Small</text>')
lines.append(f'  <text {TXT}" x="263" y="1156">Medium</text>')
lines.append(f'  <text {TXT}" x="263" y="1586">Large</text>')
lines.append(' </g>')
lines.append(' <g id="Guides">')
for gy in (696, 1126, 1556):
    lines.append(f'  <g id="H-reference" style="fill:#27AAE1;stroke:none;" transform="matrix(1 0 0 1 339 {gy})">')
    lines.append(f'   <path d="{H_REF_D}"/>')
    lines.append('  </g>')
for scale_name, base, cap in [("S", 696, 625.541), ("M", 1126, 1055.54), ("L", 1556, 1485.54)]:
    lines.append(f'  <line id="Capline-{scale_name}" {GUIDE} x1="263" y1="{cap}" x2="3036" y2="{cap}"/>')
    lines.append(f'  <line id="Baseline-{scale_name}" {GUIDE} x1="263" y1="{base}" x2="3036" y2="{base}"/>')

symbol_groups = []
for variant, (w, dot_r, fan_r) in WEIGHTS.items():
    d, left, right = variant_path(CENTERS[variant], w, dot_r, fan_r)
    y0, y1 = MARGIN_Y
    lines.append(f'  <line id="left-margin-{variant}" {GUIDE} x1="{fmt(left)}" y1="{y0}" x2="{fmt(left)}" y2="{y1}"/>')
    lines.append(f'  <line id="right-margin-{variant}" {GUIDE} x1="{fmt(right)}" y1="{y0}" x2="{fmt(right)}" y2="{y1}"/>')
    symbol_groups.append((variant, d))
lines.append(' </g>')
lines.append(' <g id="Symbols">')
for variant, d in symbol_groups:
    lines.append(f'  <g id="{variant}">')
    lines.append(f'   <path d="{d}"/>')
    lines.append('  </g>')
lines.append(' </g>')
lines.append('</svg>')

repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out_dir = os.path.join(repo_root, "PeakBar", "PeakBar", "Assets.xcassets", "GPUIcon.symbolset")
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, "GPUIcon.svg"), "w") as f:
    f.write("\n".join(lines) + "\n")
with open(os.path.join(out_dir, "Contents.json"), "w") as f:
    f.write('{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  },\n'
            '  "symbols" : [\n    {\n      "filename" : "GPUIcon.svg",\n'
            '      "idiom" : "universal"\n    }\n  ]\n}\n')
print(f"Generated {out_dir}/GPUIcon.svg")

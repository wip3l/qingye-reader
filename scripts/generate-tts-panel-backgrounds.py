"""Generates the per-theme TTS / audiobook panel artwork (tts_panel_<id>_<mode>.svg).

Each theme has one drawing shared by its light and dark variant; only the palette differs.
The artwork is a 720 x 520 top-anchored scene on a transparent canvas. The sky gradient
and the fade into the panel colour are drawn by TtsPanelThemeBackground, because theme
SVGs must not use gradients, filters or external references.

Usage: python scripts/generate-tts-panel-backgrounds.py
"""
import math
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'entry', 'src', 'main', 'resources', 'base',
                   'media')


def fill(shape, color, opacity):
    return f'<{shape} fill="{color}" fill-opacity="{opacity}"/>'


def stroke(shape, color, opacity, width, extra=''):
    return (f'<{shape} fill="none" stroke="{color}" stroke-opacity="{opacity}" stroke-width="{width}" '
            f'stroke-linecap="round" stroke-linejoin="round"{extra}/>')


def both(shape, fill_color, fill_opacity, stroke_color, stroke_opacity, width):
    return (f'<{shape} fill="{fill_color}" fill-opacity="{fill_opacity}" stroke="{stroke_color}" '
            f'stroke-opacity="{stroke_opacity}" stroke-width="{width}" stroke-linejoin="round"/>')


def circle(cx, cy, r):
    return f'circle cx="{cx}" cy="{cy}" r="{r}"'


def ellipse(cx, cy, rx, ry, transform=''):
    t = f' transform="{transform}"' if transform else ''
    return f'ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}"{t}'


def rect(x, y, w, h, rx=0, transform=''):
    t = f' transform="{transform}"' if transform else ''
    r = f' rx="{rx}"' if rx else ''
    return f'rect x="{x}" y="{y}" width="{w}" height="{h}"{r}{t}'


def path(d, transform=''):
    t = f' transform="{transform}"' if transform else ''
    return f'path d="{d}"{t}'


def plain_default(p):
    out = [stroke(circle(610, 60, r), p['a'], round(0.24 - i * 0.045, 3), 2)
           for i, r in enumerate((80, 140, 200, 260, 320))]
    heights = (26, 54, 38, 82, 46, 110, 64, 92, 40, 70, 30, 56, 24)
    for i, h in enumerate(heights):
        out.append(fill(rect(64 + i * 26, 330 - h, 10, h, 5), p['a'], 0.13))
    out.append(fill(circle(610, 60, 14), p['a'], 0.22))
    return out


def classic_blue(p):
    out = [
        fill(circle(560, 110, 180), p['a'], 0.10),
        fill(circle(620, 70, 110), p['b'], 0.16),
        fill(circle(110, 310, 96), p['a'], 0.06),
        fill(circle(250, 90, 22), p['b'], 0.18),
        fill(circle(318, 150, 10), p['a'], 0.20),
    ]
    for i, r in enumerate((220, 262, 304)):
        out.append(stroke(circle(560, 110, r), p['a'], round(0.18 - i * 0.05, 3), 2))
    out.append(stroke(path('M0 372c60-44 120-44 180 0s120 44 180 0 120-44 180 0 120 44 180 0'), p['a'], 0.24, 3))
    out.append(stroke(path('M0 404c60-30 120-30 180 0s120 30 180 0 120-30 180 0 120 30 180 0'), p['b'], 0.22, 3))
    return out


def warm_paper(p):
    out = [
        fill(circle(520, 200, 112), p['a'], 0.30),
        stroke(circle(520, 200, 144), p['a'], 0.18, 2),
        stroke(circle(520, 200, 176), p['a'], 0.09, 2),
    ]
    for y in (64, 92, 120):
        out.append(stroke(path(f'M44 {y}H{250 - (y - 64)}'), p['c'], 0.16, 2))
    out.append(fill(path('M0 366C120 300 226 302 344 352S566 402 720 330V520H0Z'), p['b'], 0.30))
    out.append(fill(path('M0 430C160 376 300 402 432 424S640 384 720 412V520H0Z'), p['c'], 0.22))
    for x, y, s in ((300, 120, 1.0), (352, 92, 0.75), (246, 160, 0.6)):
        out.append(stroke(path(f'M{x} {y}q{12 * s:.0f}-{14 * s:.0f} {24 * s:.0f} 0q{12 * s:.0f}-{14 * s:.0f} {24 * s:.0f} 0'),
                          p['c'], 0.5, 3))
    return out


def pine(x, base, h, w):
    d = ''
    for i in range(3):
        top = base - h + i * h * 0.24
        bottom = base - h + (i + 1.25) * h * 0.4
        half = w * (0.34 + i * 0.33)
        d += f'M{x} {top:.0f}L{x + half:.0f} {min(bottom, base):.0f}H{x - half:.0f}Z'
    d += f'M{x - 4} {base - 8}h8v{26}h-8Z'
    return d


def forest_mist(p):
    out = [fill(circle(548, 118, 62), p['c'], 0.55), fill(circle(548, 118, 96), p['c'], 0.18)]
    back = ((40, 300, 150, 44), (130, 316, 190, 52), (236, 300, 130, 40), (330, 322, 210, 58), (452, 304, 150, 44),
            (560, 320, 200, 56), (668, 302, 160, 46))
    out.append(fill(path(''.join(pine(*item) for item in back)), p['b'], 0.34))
    out.append(fill(rect(-40, 262, 800, 58, 29), p['c'], 0.34))
    front = ((-6, 420, 230, 64), (92, 440, 170, 50), (198, 428, 250, 70), (410, 446, 190, 54), (520, 426, 260, 72),
             (640, 444, 200, 58), (724, 424, 240, 66))
    out.append(fill(path(''.join(pine(*item) for item in front)), p['a'], 0.40))
    out.append(fill(rect(-40, 392, 800, 46, 23), p['c'], 0.26))
    return out


def ink_wash(p):
    return [
        fill(circle(566, 112, 34), p['c'], 0.78),
        fill(path('M0 318C70 300 110 232 168 214S250 262 300 250 372 150 430 138 500 232 560 244 660 200 720 226V520H0Z'),
             p['b'], 0.16),
        fill(path('M0 392C80 372 120 318 190 306S300 356 360 344 440 268 500 262 610 344 720 330V520H0Z'), p['a'], 0.22),
        fill(path('M0 452C110 430 170 398 250 394S380 438 470 432 610 396 720 414V520H0Z'), p['a'], 0.34),
        stroke(path('M150 150q12-12 24 0q12-12 24 0M214 116q9-9 18 0q9-9 18 0'), p['a'], 0.5, 3),
        fill(path('M232 382h78l-14 14h-50Z'), p['a'], 0.6),
        stroke(path('M270 382V352'), p['a'], 0.6, 3),
        stroke(path('M196 410h52M300 414h74M228 426h40'), p['b'], 0.32, 2),
    ]


def neon_night(p):
    out = []
    cx, cy, radius = 360, 196, 132
    for i in range(10):
        y = 74 + i * 25
        half = math.sqrt(max(0, radius * radius - (y + 8 - cy) ** 2))
        if half < 12:
            continue
        height = max(5, 20 - i * 1.6)
        color = p['c'] if i < 5 else p['b']
        out.append(fill(rect(round(cx - half), y, round(half * 2), round(height), round(height / 2)), color, 0.5))
    out.append(fill(path('M0 318V250h34v-36h46v58h30v-84h52v106h38v-52h40v76ZM480 318v-70h36v-46h44v72h34v-98h50v112h30v-44h46v74Z'),
                    p['b'], 0.24))
    out.append(stroke(path('M0 318H720'), p['a'], 0.7, 3))
    grid = ''.join(f'M360 318L{x} 520' for x in range(-590, 1311, 190))
    grid += ''.join(f'M0 {y}H720' for y in (334, 358, 394, 442, 502))
    out.append(stroke(path(grid), p['a'], 0.30, 2))
    for x, y, r in ((70, 70, 3), (150, 130, 2), (232, 54, 2), (540, 60, 3), (628, 132, 2), (676, 48, 2)):
        out.append(fill(circle(x, y, r), p['a'], 0.8))
    return out


def berry(x, y, s, p, angle):
    t = f'translate({x} {y}) rotate({angle}) scale({s})'
    seeds = ''.join(f'M{sx} {sy}a2 3 0 1 0 .1 0Z' for sx, sy in ((-14, -4), (12, -6), (0, 6), (-8, 16), (10, 14)))
    return [
        fill(path('M0-22C28-38 48-6 0 36C-48-6-28-38 0-22Z', t), p['a'], 0.62),
        fill(path('M0-20L-16-34L-4-30L0-42L4-30L16-34Z', t), p['d'], 0.7),
        fill(path(seeds, t), p['b'], 0.85),
    ]


def strawberry_cream(p):
    drip = 'M0 0H720V38'
    x = 720
    for width, depth in ((70, 46), (58, 22), (84, 62), (62, 26), (76, 50), (56, 20), (90, 70), (64, 28), (80, 44),
                         (80, 24)):
        drip += f'c0 {depth}-{width} {depth}-{width} 0'
        x -= width
    drip += 'Z'
    out = [fill(path(drip), p['b'], 0.8)]
    out += berry(566, 190, 2.1, p, 14)
    out += berry(132, 250, 1.3, p, -18)
    out += berry(330, 330, 0.9, p, 8)
    for cx, cy, r in ((420, 150, 30), (474, 104, 14), (240, 150, 18), (640, 330, 22), (60, 380, 12), (212, 360, 9)):
        out.append(fill(circle(cx, cy, r), p['c'], 0.18))
        out.append(stroke(circle(cx, cy, r), p['c'], 0.5, 2))
    return out


def crimson_archive(p):
    out = [
        fill(rect(452, 0, 268, 214), p['a'], 0.10),
        fill(rect(56, 250, 190, 124, 0, 'rotate(-6 151 312)'), p['a'], 0.07),
        stroke(rect(56, 250, 190, 124, 0, 'rotate(-6 151 312)'), p['a'], 0.24, 2),
    ]
    for i, w in enumerate((210, 150, 184, 96)):
        out.append(fill(rect(60, 70 + i * 26, w, 10), p['a'], 0.18))
    dots = ''
    for row in range(8):
        for col in range(11):
            r = max(1.5, 7 - row * 0.7 - abs(col - 5) * 0.3)
            dots += f'M{478 + col * 22 + r:.1f} {250 + row * 22}a{r:.1f} {r:.1f} 0 1 0 .1 0Z'
    out.append(fill(path(dots), p['a'], 0.18))
    out.append(stroke(path('M-10 150L730 318'), p['b'], 0.75, 3, ' stroke-dasharray="16 11"'))
    out.append(stroke(circle(590, 108, 58), p['b'], 0.75, 5))
    out.append(stroke(circle(590, 108, 44), p['b'], 0.6, 2))
    out.append(fill(rect(552, 100, 76, 16, 0, 'rotate(-14 590 108)'), p['b'], 0.7))
    out.append(fill(rect(210, 232, 96, 26, 0, 'rotate(-20 258 245)'), p['b'], 0.28))
    out.append(fill(rect(20, 356, 86, 24, 0, 'rotate(12 63 368)'), p['b'], 0.22))
    return out


def blossom(x, y, r, p, opacity=0.72):
    d = ''
    for i in range(5):
        angle = math.radians(i * 72 - 90)
        px, py = x + math.cos(angle) * r, y + math.sin(angle) * r
        d += f'M{px + r * 0.72:.1f} {py:.1f}a{r * 0.72:.1f} {r * 0.72:.1f} 0 1 0 .1 0Z'
    return [fill(path(d), p['b'], opacity), fill(circle(x, y, round(r * 0.34, 1)), p['d'], 0.9)]


def plum_tea(p):
    out = [
        fill(circle(500, 196, 152), p['a'], 0.08),
        stroke(circle(500, 196, 152), p['a'], 0.36, 6),
        stroke(circle(500, 196, 138), p['a'], 0.16, 2),
        stroke(path('M362 196H638M500 58V334M402 98L598 294M598 98L402 294'), p['a'], 0.10, 2),
        stroke(path('M730 34C650 62 612 124 536 146S430 150 372 214'), p['c'], 0.6, 8),
        stroke(path('M612 106C590 70 552 60 520 34M536 146C540 190 520 226 488 250M452 164C420 150 396 124 386 94'),
               p['c'], 0.55, 4),
    ]
    for x, y, r in ((520, 34, 13), (612, 106, 15), (488, 250, 14), (386, 94, 11), (430, 172, 12), (372, 214, 10),
                    (664, 70, 10)):
        out += blossom(x, y, r, p)
    for x, y, angle in ((300, 300, 30), (250, 244, -20), (580, 360, 60), (204, 330, 10)):
        out.append(fill(ellipse(x, y, 9, 5, f'rotate({angle} {x} {y})'), p['b'], 0.42))
    out.append(stroke(path('M110 400c-22-30 22-52 0-84s22-52 0-84M156 404c-18-24 18-44 0-70s18-44 0-70'), p['a'], 0.26, 5))
    return out


def rose(x, y, s, p):
    t = f'translate({x} {y}) scale({s})'
    return [
        fill(circle(0, 0, 44) + f' transform="{t}"', p['a'], 0.26),
        fill(path('M-30 6C-34-22-6-40 16-28S40 14 18 30-26 34-30 6Z', t), p['a'], 0.36),
        stroke(path('M-14 4C-16-12 0-20 10-12S20 10 6 16-12 16-14 4M-2 2c0-6 8-6 8 0', t), p['a'], 0.75, 3),
        fill(path('M30 30C52 26 66 40 70 58C50 60 36 50 30 30ZM-34 30C-54 30-66 44-66 60C-48 58-38 48-34 30Z', t),
             p['d'], 0.42),
    ]


def rose_letter(p):
    out = [
        fill(path('M0 0L360 236L720 0Z'), p['a'], 0.07),
        stroke(path('M0 0L360 236L720 0'), p['b'], 0.6, 3),
        stroke(path('M0 28L360 264L720 28'), p['b'], 0.24, 2),
        fill(circle(360, 236, 46), p['a'], 0.72),
        stroke(circle(360, 236, 34), p['b'], 0.85, 2),
        stroke(path('M346 240c-4-14 10-22 18-14s8 20-4 22-12-2-14-8'), p['b'], 0.85, 3),
    ]
    out += rose(596, 330, 1.25, p)
    out += rose(110, 320, 0.9, p)
    for i in range(4):
        out.append(stroke(path(f'M470 {66 + i * 16}c18-10 36 10 54 0s36 10 54 0 36 10 54 0'), p['c'], 0.22, 2))
    for x, y, r in ((70, 120, 4), (150, 196, 3), (250, 300, 3), (470, 318, 4), (664, 200, 3), (300, 60, 3)):
        out.append(fill(circle(x, y, r), p['b'], 0.7))
    return out


def moon_crane(p):
    out = [
        fill(circle(548, 150, 136), p['a'], 0.12),
        fill(circle(548, 150, 96), p['a'], 0.86),
        stroke(ellipse(330, 330, 330, 54, 'rotate(-14 330 330)'), p['b'], 0.30, 3),
        stroke(ellipse(330, 330, 240, 34, 'rotate(-14 330 330)'), p['b'], 0.22, 2),
        fill(path('M180 196c-87-45-147-24-188 36 73-25 128-17 170 26-53-2-91 16-119 54 80-21 140-7 181 44-15-50-34-91-44-160Z',
                  'translate(120 66) scale(0.9)'), p['c'], 0.66),
        stroke(path('M282 242c26-18 52-22 82-10l26-18M364 232l30 6'), p['c'], 0.66, 5),
    ]
    stars = ((60, 70, 4), (150, 40, 3), (236, 112, 3), (330, 52, 4), (420, 96, 2), (680, 60, 3), (690, 250, 3),
             (604, 318, 2), (96, 180, 2), (470, 400, 3), (200, 420, 2))
    for x, y, r in stars:
        out.append(fill(circle(x, y, r), p['b'], 0.8))
    return out


def sword_frost(p):
    out = [
        stroke(path('M-20 150c80-30 150 26 230-4s150-40 240-10 170 20 290-16'), p['a'], 0.16, 12),
        fill(path('M0 346L118 226L204 292L332 152L452 302L544 240L720 364V520H0Z'), p['a'], 0.17),
        fill(path('M332 152L296 192L320 184L338 202L366 190ZM118 226L96 248L114 244L126 256L142 248ZM544 240L522 256L540 254L552 266L570 260Z'),
             p['d'], 0.6),
        fill(path('M0 428L160 322L262 384L420 284L560 404L720 334V520H0Z'), p['a'], 0.27),
    ]
    sword = 'rotate(20 604 210)'
    out.append(fill(path('M604 20L614 58V306H594V58Z', sword), p['c'], 0.34))
    out.append(stroke(path('M604 40V300', sword), p['d'], 0.5, 2))
    out.append(fill(path('M570 306h68v10h-68ZM598 316h12v54h-12Z', sword), p['c'], 0.5))
    out.append(fill(circle(604, 378, 9) + f' transform="{sword}"', p['b'], 0.8))
    out.append(fill(rect(70, 66, 50, 50, 5), p['b'], 0.72))
    out.append(stroke(path('M84 80h22v22h-22ZM95 80v22'), p['d'], 0.85, 3))
    snow = ((180, 70, 4), (250, 130, 3), (40, 210, 3), (410, 60, 4), (470, 180, 3), (680, 96, 3), (300, 250, 2),
            (656, 290, 3), (150, 300, 2), (520, 110, 2))
    for x, y, r in snow:
        out.append(fill(circle(x, y, r), p['d'], 0.7))
    return out


def qingluan_water(p):
    out = [
        fill(path('M566 44a74 74 0 1 0 66 108a58 58 0 1 1-66-108Z'), p['c'], 0.85),
        fill(circle(560, 122, 120), p['c'], 0.10),
    ]
    for rx, ry, opacity in ((300, 44, 0.20), (214, 30, 0.28), (128, 17, 0.36)):
        out.append(stroke(ellipse(300, 440, rx, ry), p['a'], opacity, 3))
    out.append(stroke(path('M276 250C200 300 150 360 60 372M270 258C220 330 190 380 120 420M284 252C250 330 250 380 214 440'),
                      p['a'], 0.5, 5))
    out.append(stroke(path('M60 372c-10-4-18 2-20 12M120 420c-10-2-16 6-16 16M214 440c-8 0-12 8-10 16'), p['b'], 0.7, 5))
    out.append(fill(path('M270 262C300 214 356 196 410 208C392 232 366 258 318 270C300 274 284 272 270 262Z'), p['a'], 0.5))
    out.append(fill(path('M316 238C330 176 376 136 440 122C436 172 404 220 350 250Z'), p['a'], 0.34))
    out.append(fill(circle(424, 196, 17), p['a'], 0.62))
    out.append(fill(path('M438 188l28 4l-26 10Z'), p['b'], 0.8))
    out.append(stroke(path('M420 180c-4-16 4-28 16-34M428 180c4-12 14-18 26-18'), p['b'], 0.7, 3))
    for x, y, angle in ((150, 120, 30), (230, 70, -24), (96, 230, 60), (520, 300, 18), (640, 360, -30), (360, 60, 12)):
        out.append(fill(ellipse(x, y, 10, 5, f'rotate({angle} {x} {y})'), p['b'], 0.5))
    return out


def paw(x, y, s, angle, color, opacity):
    t = f'translate({x} {y}) rotate({angle}) scale({s})'
    d = 'M0 4C14 4 22 16 16 26S-10 36-16 26-14 4 0 4Z'
    for tx, ty in ((-19, -6), (-7, -18), (7, -18), (19, -6)):
        d += f'M{tx + 6} {ty}a6 7.5 0 1 0 .1 0Z'
    return fill(path(d, t), color, opacity)


def cat_pipi(p):
    out = [fill(circle(124, 112, 104), p['b'], 0.22), fill(circle(124, 112, 68), p['b'], 0.7)]
    rays = ''
    for i in range(12):
        angle = math.radians(i * 30)
        rays += (f'M{124 + math.cos(angle) * 86:.0f} {112 + math.sin(angle) * 86:.0f}'
                 f'L{124 + math.cos(angle) * 104:.0f} {112 + math.sin(angle) * 104:.0f}')
    out.append(stroke(path(rays), p['b'], 0.6, 5))
    out.append(fill(path('M452 300L462 188L540 250ZM668 300L660 188L582 250Z'), p['a'], 0.42))
    out.append(fill(path('M474 270L476 214L516 246ZM646 270L646 214L606 246Z'), p['d'], 0.5))
    out.append(fill(ellipse(560, 350, 124, 104), p['a'], 0.42))
    out.append(stroke(path('M500 340q16-18 32 0M588 340q16-18 32 0'), p['e'], 0.8, 5))
    out.append(fill(path('M552 366h16l-8 10Z'), p['d'], 0.9))
    out.append(stroke(path('M560 376v8q-12 12-24 2M560 384q12 12 24 2M470 362l-46-8M472 378l-44 10M650 362l46-8M648 378l44 10'),
                      p['e'], 0.6, 3))
    for x, y, s, angle in ((250, 330, 0.9, -20), (316, 250, 0.8, 14), (360, 150, 0.7, -16), (430, 70, 0.6, 18)):
        out.append(paw(x, y, s, angle, p['a'], 0.30))
    out.append(stroke(circle(96, 380, 34), p['c'], 0.55, 5))
    out.append(stroke(path('M70 366c20-14 44-8 54 10M66 388c22 12 46 10 60-8M96 414c40 30 90 10 130 30'), p['c'], 0.5, 4))
    return out


def star4(cx, cy, r):
    """Four-point sparkle."""
    inner = round(r * 0.3, 1)
    outer = round(r - inner, 1)
    return (f'M{cx} {cy - r}l{inner} {outer} {outer} {inner}-{outer} {inner}-{inner} {outer}'
            f'-{inner}-{outer}-{outer}-{inner} {outer}-{inner}Z')


def azure_mecha(p):
    hexes = ''
    for row in range(4):
        for col in range(5):
            cx, cy = 430 + col * 66 + (33 if row % 2 else 0), 40 + row * 57
            hexes += f'M{cx - 33} {cy}l16.5-28.5h33l16.5 28.5-16.5 28.5h-33Z'
    out = [
        stroke(path(hexes), p['a'], 0.14, 2),
        fill(path('M529 97l16.5-28.5h33l16.5 28.5-16.5 28.5h-33ZM628 154l16.5-28.5h33l16.5 28.5-16.5 28.5h-33Z'),
             p['a'], 0.10),
        stroke(circle(560, 190, 96), p['b'], 0.5, 6, ' stroke-dasharray="230 60 90 60"'),
        stroke(circle(560, 190, 74), p['b'], 0.3, 2),
        stroke(circle(560, 190, 120), p['a'], 0.2, 2, ' stroke-dasharray="6 12"'),
        fill(path('M560 190V116A74 74 0 0 1 624 153Z'), p['b'], 0.18),
        fill(circle(560, 190, 7), p['c'], 0.9),
        stroke(path('M24 150V44l22-22h170'), p['a'], 0.4, 3),
        stroke(path('M24 96V44l22-22h60'), p['a'], 0.6, 7),
        stroke(path('M130 22h44'), p['c'], 0.8, 7),
        stroke(path('M48 58h96M48 76h62M48 94h78'), p['a'], 0.22, 6),
    ]
    wave = 'M0 372'
    for i, height in enumerate((8, 20, 46, 14, 70, 30, 96, 22, 56, 110, 40, 74, 18, 50, 28, 12, 36, 8)):
        x = 20 + i * 40
        wave += f'L{x} {372 - height}L{x + 20} {372 + height}'
    out.append(stroke(path(wave + 'L720 372'), p['b'], 0.5, 3))
    out.append(stroke(path('M0 372H720'), p['a'], 0.2, 2))
    ticks = ''.join(f'M{20 + i * 20} 440v{14 if i % 5 == 0 else 7}' for i in range(35))
    out.append(stroke(path(ticks), p['a'], 0.3, 2))
    return out


def starwish_magic(p):
    out = [
        fill(circle(548, 150, 150), p['b'], 0.10),
        fill(path('M560 30a122 122 0 1 0 82 204a98 98 0 1 1-82-204Z'), p['b'], 0.85),
    ]
    for i in range(5):
        y = 300 + i * 16
        out.append(stroke(path(f'M-10 {y}C120 {y - 70} 240 {y + 40} 370 {y - 20}S600 {y - 80} 730 {y - 30}'), p['a'],
                          0.26, 2))
    notes = ((70, 282, 16), (170, 300, 12), (262, 332, 18), (360, 300, 13), (450, 286, 16), (560, 268, 12),
             (660, 290, 15))
    out.append(fill(path(''.join(star4(x, y, r) for x, y, r in notes)), p['b'], 0.9))
    out.append(stroke(path('M0 60C80 20 150 80 230 50S380 10 430 60'), p['c'], 0.6, 8))
    out.append(stroke(path('M40 120C110 90 170 130 240 110'), p['c'], 0.4, 5))
    sparks = ((60, 180, 9), (150, 150, 7), (250, 196, 8), (330, 130, 6), (410, 200, 7), (690, 60, 8), (680, 380, 7),
              (120, 420, 6), (300, 440, 7), (520, 420, 6), (440, 100, 5))
    out.append(fill(path(''.join(star4(x, y, r) for x, y, r in sparks)), p['a'], 0.6))
    return out


def letterpress_page(p):
    out = [
        fill(circle(548, 176, 150), p['c'], 0.14),
        fill(circle(548, 176, 96), p['c'], 0.20),
        # desk lamp
        stroke(path('M640 420V250C640 190 600 150 556 140'), p['a'], 0.5, 7),
        fill(path('M492 176c8-40 46-62 96-52l-22 74Z'), p['a'], 0.5),
        fill(path('M506 184l56 14-8 12-52-14Z'), p['c'], 0.9),
        fill(path('M596 420h88v14h-88Z'), p['a'], 0.5),
        # open book
        both(path('M150 392c60-30 120-30 170 0v60c-50-26-110-26-170 0Z'), p['b'], 0.8, p['a'], 0.5, 3),
        both(path('M320 392c50-30 110-30 170 0v60c-60-26-120-26-170 0Z'), p['b'], 0.8, p['a'], 0.5, 3),
        stroke(path('M174 404c42-16 84-16 124 0M174 420c42-16 84-16 124 0M344 404c40-16 82-16 124 0M344 420c40-16 82-16 124 0'),
               p['a'], 0.3, 2),
        fill(path('M420 380h22v96l-11-10-11 10Z'), p['a'], 0.5),
        # running head
        stroke(path('M40 70h34M118 70h250'), p['a'], 0.34, 2),
        stroke(path('M40 80h328'), p['a'], 0.16, 1.5),
        fill(path('M96 54l11 16-11 16-11-16Z'), p['c'], 0.9),
    ]
    for i, (rise, spread) in enumerate(((60, 50), (104, 86), (150, 124))):
        out.append(stroke(path(f'M{320 - spread} {372 - rise * 0.5:.0f}Q320 {372 - rise} {320 + spread} {372 - rise * 0.5:.0f}'),
                          p['a'], round(0.34 - i * 0.09, 2), 3))
    out.append(stroke(path('M0 456H720'), p['a'], 0.24, 3))
    return out


# Palette keys: a = main ink, b = second ink, c = third ink, d / e = small accents.
THEMES = {
    'plain_default': (plain_default, {'a': '#4A5F7E'}, {'a': '#9DB1CF'}),
    'classic_blue': (classic_blue, {'a': '#007DFF', 'b': '#70B6F2'}, {'a': '#4E9BFF', 'b': '#2A6FD0'}),
    'warm_paper': (warm_paper, {'a': '#B66A3C', 'b': '#D9A679', 'c': '#8C5A3A'},
                   {'a': '#E49A69', 'b': '#8A5A3C', 'c': '#C77D50'}),
    'forest_mist': (forest_mist, {'a': '#3F7D5B', 'b': '#7FB095', 'c': '#FFFFFF'},
                    {'a': '#70B58B', 'b': '#2F5C45', 'c': '#B9D8C6'}),
    'ink_wash': (ink_wash, {'a': '#292A2C', 'b': '#4E5D6C', 'c': '#B74747'},
                 {'a': '#C9CED2', 'b': '#9AA8B5', 'c': '#ED7171'}),
    'neon_night': (neon_night, {'a': '#6750FF', 'b': '#8A5CFF', 'c': '#E5487D'},
                   {'a': '#00D5FF', 'b': '#8A5CFF', 'c': '#FF4D8D'}),
    'strawberry_cream': (strawberry_cream, {'a': '#E76E77', 'b': '#FFFFFF', 'c': '#8FB8D6', 'd': '#6FA86B'},
                         {'a': '#FF929B', 'b': '#F8E9E5', 'c': '#8DB3CC', 'd': '#7DB37A'}),
    'crimson_archive': (crimson_archive, {'a': '#211F1D', 'b': '#8D211C'}, {'a': '#EEEAE4', 'b': '#D55A50'}),
    'plum_tea': (plum_tea, {'a': '#557A68', 'b': '#A34D48', 'c': '#3C3028', 'd': '#E7C36A'},
                 {'a': '#84A795', 'b': '#D4746B', 'c': '#C9BFAE', 'd': '#F0D48A'}),
    'rose_letter': (rose_letter, {'a': '#A84550', 'b': '#C9A063', 'c': '#583B3D', 'd': '#6E8B6A'},
                    {'a': '#D87983', 'b': '#D4B37A', 'c': '#F4E4E1', 'd': '#8FAE8A'}),
    'moon_crane': (moon_crane, {'a': '#FFFFFF', 'b': '#5879A7', 'c': '#7E9CC6'},
                   {'a': '#D9E5F5', 'b': '#8BBEFF', 'c': '#AFCDF4'}),
    'sword_frost': (sword_frost, {'a': '#476963', 'b': '#83372F', 'c': '#272B27', 'd': '#FFFFFF'},
                    {'a': '#8AB1A7', 'b': '#B85C4F', 'c': '#E8EBE4', 'd': '#F4F7F2'}),
    'qingluan_water': (qingluan_water, {'a': '#607F79', 'b': '#9C4F62', 'c': '#FFFFFF'},
                       {'a': '#8AB5AC', 'b': '#C16A7D', 'c': '#DCEBE7'}),
    'cat_pipi': (cat_pipi, {'a': '#C46F45', 'b': '#F6C98F', 'c': '#587E73', 'd': '#E79A8E', 'e': '#5A3A2A'},
                 {'a': '#E8A06F', 'b': '#8A5C36', 'c': '#79A99B', 'd': '#E39A8F', 'e': '#2A1C14'}),
    'letterpress_page': (letterpress_page, {'a': '#2F5D48', 'b': '#FBF8F1', 'c': '#C9A24A'},
                         {'a': '#9DB8A7', 'b': '#26302B', 'c': '#D3B36A'}),
    'azure_mecha': (azure_mecha, {'a': '#2F6FB3', 'b': '#2A9DB0', 'c': '#E8731F'},
                    {'a': '#8FB6DE', 'b': '#3FD3E6', 'c': '#F08A3C'}),
    'starwish_magic': (starwish_magic, {'a': '#9A74D6', 'b': '#D9B24C', 'c': '#C9B1EE'},
                       {'a': '#C3A2F2', 'b': '#E8C76A', 'c': '#6D52A8'}),
}


def main():
    for name, (draw, light, dark) in THEMES.items():
        for mode, palette in (('light', light), ('dark', dark)):
            body = '\n  '.join(draw(palette))
            svg = (f'<svg width="720" height="520" viewBox="0 0 720 520" xmlns="http://www.w3.org/2000/svg">\n'
                   f'  {body}\n</svg>\n')
            with open(os.path.join(OUT, f'tts_panel_{name}_{mode}.svg'), 'w', encoding='utf-8', newline='\n') as f:
                f.write(svg)
    print(f'Generated {len(THEMES) * 2} panel backgrounds.')


if __name__ == '__main__':
    main()

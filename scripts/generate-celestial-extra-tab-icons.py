"""星穹御藏第四个页签（听 / 足迹）的底栏位图图标。

和另外三个页签一样是 144 px 位图：普通态是古金粗线（#A07C3A，浅底深底通用），选中态是午夜蓝圆章配金色图形。
底栏不给位图着色，所以颜色都画死在图里。

依赖：pip install resvg-py pillow
运行：python scripts/generate-celestial-extra-tab-icons.py
"""
import io
import os

import resvg_py
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'entry', 'src', 'main', 'resources', 'base',
                   'media')
GOLD = '#A07C3A'
SIZE = 144


def sparkle(x, y, s):
    t = s * 0.28
    return (f'M{x} {y - s}L{x + t} {y - t}L{x + s} {y}L{x + t} {y + t}L{x} {y + s}L{x - t} {y + t}'
            f'L{x - s} {y}L{x - t} {y - t}Z')


def star5(cx, cy, outer, inner):
    import math
    points = []
    for i in range(10):
        r = outer if i % 2 == 0 else inner
        a = -math.pi / 2 + i * math.pi / 5
        points.append(f'{cx + r * math.cos(a):.2f} {cy + r * math.sin(a):.2f}')
    return 'M' + 'L'.join(points) + 'Z'


# 48 网格上的图形，普通态和选中态共用。
LISTEN_BAND = 'M11 29v-4a13 13 0 0 1 26 0v4'
LISTEN_CUPS = ['M9.5 27h4a2.5 2.5 0 0 1 2.5 2.5v9a2.5 2.5 0 0 1-2.5 2.5h-4A2.5 2.5 0 0 1 7 38.5v-9A2.5 2.5 0 0 1 9.5 27Z',
               'M34.5 27h4a2.5 2.5 0 0 1 2.5 2.5v9a2.5 2.5 0 0 1-2.5 2.5h-4a2.5 2.5 0 0 1-2.5-2.5v-9a2.5 2.5 0 0 1 2.5-2.5Z']
TRAIL = 'M9 38L18 27L28 31L37 15'


def normal_listen():
    cups = ''.join(f'<path d="{d}" fill="{GOLD}" fill-opacity=".1" stroke="{GOLD}" stroke-width="3" '
                   f'stroke-linejoin="round"/>' for d in LISTEN_CUPS)
    return (f'<path d="{LISTEN_BAND}" fill="none" stroke="{GOLD}" stroke-width="3" stroke-linecap="round"/>{cups}'
            f'<path d="{sparkle(24, 24.5, 3.6)}" fill="{GOLD}"/>'
            f'<path d="{sparkle(42, 7, 4)}" fill="{GOLD}"/>')


def normal_footprint():
    return (f'<path d="{TRAIL}" fill="none" stroke="{GOLD}" stroke-width="2.2" stroke-linecap="round" '
            f'stroke-linejoin="round" stroke-dasharray="0.1 4.2"/>'
            f'<circle cx="9" cy="38" r="3.4" fill="{GOLD}" fill-opacity=".1" stroke="{GOLD}" stroke-width="2.4"/>'
            f'<path d="{sparkle(18, 27, 4.4)}" fill="{GOLD}"/>'
            f'<circle cx="28" cy="31" r="2.6" fill="{GOLD}"/>'
            f'<circle cx="37" cy="15" r="9" fill="{GOLD}" fill-opacity=".1" stroke="{GOLD}" stroke-width="2.6"/>'
            f'<path d="{star5(37, 15.4, 5.6, 2.4)}" fill="{GOLD}" stroke="{GOLD}" stroke-width=".8" '
            f'stroke-linejoin="round"/>'
            f'<path d="{sparkle(9, 10, 3.2)}" fill="{GOLD}"/>')


DEFS = '''<defs>
<linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FBEBC0"/><stop offset=".45" stop-color="#E2B866"/><stop offset="1" stop-color="#A9772E"/></linearGradient>
<linearGradient id="rim" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#F7DFA0"/><stop offset=".5" stop-color="#C6923E"/><stop offset="1" stop-color="#8E6224"/></linearGradient>
<radialGradient id="navy" cx=".45" cy=".35" r=".75"><stop offset="0" stop-color="#2B4A86"/><stop offset=".7" stop-color="#18295A"/><stop offset="1" stop-color="#0F1B40"/></radialGradient>
<filter id="s" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy=".6" stdDeviation=".6" flood-color="#06102A" flood-opacity=".55"/></filter>
</defs>'''


def medallion(inner):
    ring = ''.join(f'<path d="{sparkle(x, y, 3.4)}" fill="url(#g)" stroke="#8E6224" stroke-width=".35"/>'
                   for x, y in [(24, 2.6), (45.4, 24), (24, 45.4), (2.6, 24)])
    return (DEFS +
            '<circle cx="24" cy="24" r="21.2" fill="url(#rim)"/>'
            '<circle cx="24" cy="24" r="19" fill="url(#navy)"/>'
            '<circle cx="24" cy="24" r="16.6" fill="none" stroke="#D9B160" stroke-width=".7" stroke-opacity=".9"/>'
            f'<g filter="url(#s)">{inner}</g>{ring}')


def selected_listen():
    band = 'M14.2 28.5v-3.2a9.8 9.8 0 0 1 19.6 0v3.2'
    cups = ['M13 26.5h2.6a2 2 0 0 1 2 2v6.6a2 2 0 0 1-2 2H13a2 2 0 0 1-2-2v-6.6a2 2 0 0 1 2-2Z',
            'M32.4 26.5H35a2 2 0 0 1 2 2v6.6a2 2 0 0 1-2 2h-2.6a2 2 0 0 1-2-2v-6.6a2 2 0 0 1 2-2Z']
    inner = (f'<path d="{band}" fill="none" stroke="#8E6224" stroke-width="3.6" stroke-linecap="round"/>'
             f'<path d="{band}" fill="none" stroke="url(#g)" stroke-width="2.6" stroke-linecap="round"/>' +
             ''.join(f'<path d="{d}" fill="url(#g)" stroke="#8E6224" stroke-width=".5"/>' for d in cups) +
             f'<path d="{sparkle(24, 25.5, 3.4)}" fill="url(#g)"/>')
    return medallion(inner)


def selected_footprint():
    trail = 'M14 33L20 26L27 29L33 17'
    inner = (f'<path d="{trail}" fill="none" stroke="#E8C474" stroke-width="1.6" stroke-linecap="round" '
             f'stroke-dasharray="0.1 2.9"/>'
             f'<circle cx="14" cy="33" r="1.9" fill="url(#g)"/>'
             f'<path d="{sparkle(20, 26, 3.2)}" fill="url(#g)"/>'
             f'<circle cx="27" cy="29" r="1.6" fill="url(#g)"/>'
             f'<path d="{star5(32.4, 17.6, 7, 3)}" fill="url(#g)" stroke="#8E6224" stroke-width=".5" '
             f'stroke-linejoin="round"/>')
    return medallion(inner)


def render(name, body):
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">{body}</svg>'
    png = bytes(resvg_py.svg_to_bytes(svg_string=svg, width=SIZE, height=SIZE))
    image = Image.open(io.BytesIO(png)).convert('RGBA')
    image.save(os.path.join(OUT, f'ic_theme_celestial_vault_{name}.png'), optimize=True)


def main():
    render('listen', normal_listen())
    render('footprint', normal_footprint())
    render('listen_selected', selected_listen())
    render('footprint_selected', selected_footprint())
    print('Generated 4 celestial vault tab icons.')


if __name__ == '__main__':
    main()

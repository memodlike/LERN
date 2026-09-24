#!/usr/bin/env python3
"""Generates LERN's Icon Composer (.icon) app icons, in-app previews and the Watch icon.

Each icon is a flat background fill plus one or more vector layers that iOS renders
as Liquid Glass, so Default, Dark, Tinted and Clear appearances come from one source.
Run from the repository root: python3 scripts/generate_app_icons.py
"""
import json, math, shutil, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ICONS_DIR = ROOT / 'Resources/AppIcons'
ASSETS = ROOT / 'Resources/Assets.xcassets'
WATCH_ICON = ROOT / 'Watch/Assets.xcassets/AppIcon.appiconset'
ICTOOL = '/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool'


def svg(body):
    return f"<svg xmlns='http://www.w3.org/2000/svg' width='1024' height='1024' viewBox='0 0 1024 1024'>{body}</svg>"


def stroke(d, color, width):
    return f"<path d='{d}' fill='none' stroke='{color}' stroke-width='{width}' stroke-linecap='round' stroke-linejoin='round'/>"


def fill(d, color):
    return f"<path d='{d}' fill='{color}'/>"


def circle(cx, cy, r, color):
    return f"<circle cx='{cx}' cy='{cy}' r='{r}' fill='{color}'/>"


# --- Marks (1024 canvas, optically centred) ---------------------------------

def mark_l(ink, dot):
    """"L." — the letter as a finished sentence: your own words, full stop."""
    return [('dot', svg(circle(706, 702, 86, dot))),
            ('letter', svg(stroke('M322 288 V702 H532', ink, 156)))]


def mark_quote(color):
    def comma(cx, cy):
        return (f'M{cx + 96} {cy} A96 96 0 1 0 {cx - 10} {cy + 95} '
                f'C{cx - 26} {cy + 160} {cx - 78} {cy + 214} {cx - 140} {cy + 246} '
                f'C{cx - 60} {cy + 236} {cx + 96} {cy + 170} {cx + 96} {cy} Z')
    grow = "<g transform='translate(512 500) scale(1.14) translate(-500 -500)'>{}</g>"
    return [('left', svg(grow.format(fill(comma(392, 420), color)))),
            ('right', svg(grow.format(fill(comma(652, 420), color))))]


def mark_dawn(sun, water):
    ripples = stroke('M236 640 H788', water, 44) + stroke('M322 716 H702', water, 44) + stroke('M408 792 H616', water, 44)
    return [('sun', svg(fill('M298 570 A214 214 0 0 1 726 570 Z', sun))),
            ('water', svg(ripples))]


def mark_bookmark(color):
    return [('ribbon', svg(fill('M372 232 H652 A40 40 0 0 1 692 272 V792 L512 668 L332 792 V272 A40 40 0 0 1 372 232 Z', color)))]


def mark_moon(moon, star):
    # Crescent = outer disc minus an offset disc, built from the two intersection points.
    (ox, oy, R), (ix, iy, r) = (500, 530, 250), (610, 440, 210)
    d = math.hypot(ix - ox, iy - oy)
    a = (R * R - r * r + d * d) / (2 * d)
    h = math.sqrt(R * R - a * a)
    mx, my = ox + a * (ix - ox) / d, oy + a * (iy - oy) / d
    p1 = (mx + h * (iy - oy) / d, my - h * (ix - ox) / d)
    p2 = (mx - h * (iy - oy) / d, my + h * (ix - ox) / d)
    path = (f'M{p1[0]:.1f} {p1[1]:.1f} A{R} {R} 0 1 0 {p2[0]:.1f} {p2[1]:.1f} '
            f'A{r} {r} 0 0 1 {p1[0]:.1f} {p1[1]:.1f} Z')
    sparkle = 'M752 268 Q760 316 808 324 Q760 332 752 380 Q744 332 696 324 Q744 316 752 268 Z'
    return [('star', svg(fill(sparkle, star))), ('moon', svg(fill(path, moon)))]


def mark_sprout(leaf, stem):
    left = 'M500 560 C400 574 290 520 262 392 C386 372 486 432 500 560 Z'
    right = 'M524 470 C540 330 650 250 790 262 C782 404 666 484 524 470 Z'
    return [('leaves', svg(fill(left, leaf) + fill(right, leaf))),
            ('stem', svg(stroke('M512 792 V560 C512 520 516 494 524 470', stem, 44)))]


def mark_spark(big, small):
    star = 'M470 196 Q506 470 780 506 Q506 542 470 816 Q434 542 160 506 Q434 470 470 196 Z'
    mini = 'M766 206 Q778 280 852 292 Q778 304 766 378 Q754 304 680 292 Q754 280 766 206 Z'
    return [('mini', svg(fill(mini, small))), ('star', svg(fill(star, big)))]


def mark_page(page, spine):
    left = 'M492 356 C420 312 318 300 226 318 V716 C318 700 420 712 492 756 Z'
    right = 'M532 356 C604 312 706 300 798 318 V716 C706 700 604 712 532 756 Z'
    return [('right', svg(fill(right, spine))), ('left', svg(fill(left, page)))]


# Dark artwork would vanish on the dark and tinted backgrounds iOS substitutes, so
# these layers are filled white in those appearances.
LIGHT_IN_DARK = {('Paper', 'letter')}
WHITE = {'solid': 'extended-srgb:1.00000,1.00000,1.00000,1.00000'}

# name -> (display name, background, [(layer name, svg)])
ICONS = {
    'AppIcon':  ('Ink',      (0.075, 0.137, 0.247), mark_l('#FFFFFF', '#7CC4FF')),
    'Paper':    ('Paper',    (0.953, 0.933, 0.894), mark_l('#1B1B1F', '#E0482A')),
    'Noir':     ('Noir',     (0.040, 0.040, 0.047), mark_l('#FFFFFF', '#E8C46A')),
    'Quote':    ('Quote',    (1.000, 0.420, 0.290), mark_quote('#FFFFFF')),
    'Dawn':     ('Dawn',     (0.965, 0.545, 0.357), mark_dawn('#FFF3DC', '#FFFFFF')),
    'Bookmark': ('Bookmark', (0.059, 0.357, 0.271), mark_bookmark('#F6E6B4')),
    'Moon':     ('Moon',     (0.118, 0.106, 0.294), mark_moon('#F4F1FF', '#FFD66B')),
    'Sprout':   ('Sprout',   (0.353, 0.522, 0.227), mark_sprout('#E9F7C8', '#FFFFFF')),
    'Spark':    ('Spark',    (0.357, 0.247, 0.851), mark_spark('#FFFFFF', '#C9BCFF')),
    'Page':     ('Page',     (0.784, 0.333, 0.239), mark_page('#FFF7EC', '#FFE1C2')),
}


def layer_json(icon, name):
    layer = {'glass': True, 'image-name': f'{name}.svg', 'name': name}
    if (icon, name) in LIGHT_IN_DARK:
        layer['fill-specializations'] = [{'value': 'automatic'}] + [{'appearance': a, 'value': WHITE} for a in ('dark', 'tinted')]
    return layer


def icon_json(icon, background, layers):
    r, g, b = background
    return {
        'fill': {'automatic-gradient': f'extended-srgb:{r:.5f},{g:.5f},{b:.5f},1.00000'},
        'groups': [{
            'layers': [layer_json(icon, name) for name, _ in layers],
            'shadow': {'kind': 'neutral', 'opacity': 0.5},
            'translucency': {'enabled': True, 'value': 0.4},
        }],
        'supported-platforms': {'circles': ['watchOS'], 'squares': 'shared'},
    }


def render(icon, out, platform='iOS', rendition='Default', size=1024):
    subprocess.run([ICTOOL, str(icon), '--export-image', '--output-file', str(out), '--platform', platform,
                    '--rendition', rendition, '--width', str(size), '--height', str(size), '--scale', '1'],
                   check=True, capture_output=True)


def write_imageset(folder, image, filename):
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(image, folder / filename)
    (folder / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': filename, 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')


def main():
    shutil.rmtree(ICONS_DIR, ignore_errors=True)
    tmp = Path(tempfile.mkdtemp())
    for name, (_, background, layers) in ICONS.items():
        bundle = ICONS_DIR / f'{name}.icon'
        (bundle / 'Assets').mkdir(parents=True)
        for layer, content in layers:
            (bundle / 'Assets' / f'{layer}.svg').write_text(content + '\n')
        (bundle / 'icon.json').write_text(json.dumps(icon_json(name, background, layers), indent=2) + '\n')
        preview = tmp / f'{name}.png'
        render(bundle, preview, size=216)
        write_imageset(ASSETS / f'{name}Preview.imageset', preview, 'preview.png')
        print(f'{name}.icon')
    watch = tmp / 'watch.png'
    render(ICONS_DIR / 'AppIcon.icon', watch, platform='watchOS')
    WATCH_ICON.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(watch, WATCH_ICON / 'icon.png')
    shutil.rmtree(tmp)


if __name__ == '__main__':
    main()

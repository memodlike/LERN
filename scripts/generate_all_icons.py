#!/usr/bin/env python3
import json, subprocess, shutil
from pathlib import Path

root = Path(__file__).resolve().parents[1]
assets = root / 'Resources/Assets.xcassets'
assets.mkdir(parents=True, exist_ok=True)
(assets / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))

tmp_dir = Path('/tmp/lern_icon_gen')
tmp_dir.mkdir(parents=True, exist_ok=True)

ICONS = {
    'AppIcon': ('#1E3C66', '#0B182B', '#A9D8F4', '#FFFFFF', 'monogram'),
    'MinimalBlack': ('#1C1D21', '#090A0C', '#FFFFFF', '#E2E8F0', 'monogram'),
    'MinimalWhite': ('#FFFFFF', '#E2E8F0', '#142C46', '#3B82F6', 'monogram'),
    'ObsidianGold': ('#262833', '#0E1014', '#F5D061', '#FDE68A', 'monogram'),
    'Titanium': ('#42444A', '#1D1E22', '#E5E7EB', '#9CA3AF', 'monogram'),
    'GraphiteSlate': ('#333A48', '#141820', '#CBD5E1', '#94A3B8', 'monogram'),
    'MidnightAurora': ('#0D3D38', '#021213', '#34D399', '#6EE7B7', 'orbit'),
    'DeepSpace': ('#2C1B4D', '#0A0614', '#C084FC', '#E9D5FF', 'portal'),
    'Starlight': ('#1D2B5E', '#070D22', '#93C5FD', '#DBEAFE', 'star'),
    'SolarFlare': ('#4A1D0B', '#160502', '#FB923C', '#FDBA74', 'sun'),
    'Eclipse': ('#25252D', '#0A0A0E', '#FBBF24', '#FDE68A', 'eclipse'),
    'CosmicOrbit': ('#133659', '#051322', '#38BDF8', '#7DD3FC', 'orbit'),
    'ForestSanctuary': ('#18422A', '#06180E', '#86EFAC', '#BBF7D0', 'leaf'),
    'Warm': ('#783227', '#2E0F0A', '#FDE1C7', '#FFFFFF', 'monogram'),
    'Cool': ('#1D527F', '#082239', '#BAE6FD', '#E0F2FE', 'monogram'),
    'DesertDusk': ('#54283A', '#1E0B14', '#FDBA74', '#FED7AA', 'monogram'),
    'LavenderMist': ('#382A54', '#120B21', '#DDD6FE', '#EDE9FE', 'portal'),
    'MatchaZen': ('#2C4A2A', '#0E1C0D', '#BEF264', '#D9F99D', 'leaf'),
    'QuoteMark': ('#2D3D54', '#101827', '#FFFFFF', '#93C5FD', 'quote'),
    'Gradient': ('#3B82F6', '#1D4ED8', '#FFFFFF', '#BFDBFE', 'monogram'),
    'ParchmentInk': ('#FAF4E8', '#E6D7BA', '#3B2516', '#784A2A', 'monogram'),
    'CrimsonVelvet': ('#540E18', '#1A0306', '#FCD34D', '#FDE68A', 'monogram'),
    'EmeraldLibrary': ('#114532', '#041C13', '#FDE68A', '#FEF08A', 'quote'),
    'IndigoDye': ('#1D3373', '#08102B', '#E0E7FF', '#C7D2FE', 'monogram'),
}

def get_mark_svg(mark_type, fg1, fg2):
    if mark_type == 'monogram':
        return f"""
        <path d='M300 278 H386 V652 H724 V738 H300Z' fill='{fg1}'/>
        <path d='M494 316 H602 V424 L548 494 H494 L548 424 H494Z' fill='{fg2}' opacity='0.95'/>
        <path d='M638 316 H746 V424 L692 494 H638 L692 424 H638Z' fill='{fg2}' opacity='0.95'/>
        """
    elif mark_type == 'quote':
        return f"""
        <path d='M350 360 C300 360 260 400 260 450 C260 520 310 570 370 590 C360 630 330 660 280 670 L280 720 C360 710 430 650 430 540 C430 440 395 360 350 360 Z' fill='{fg1}'/>
        <path d='M590 360 C540 360 500 400 500 450 C500 520 550 570 610 590 C600 630 570 660 520 670 L520 720 C600 710 670 650 670 540 C670 440 635 360 590 360 Z' fill='{fg2}'/>
        """
    elif mark_type == 'orbit':
        return f"""
        <circle cx='512' cy='512' r='230' fill='none' stroke='{fg1}' stroke-width='36' opacity='0.9'/>
        <circle cx='512' cy='512' r='130' fill='none' stroke='{fg2}' stroke-width='28'/>
        <circle cx='512' cy='282' r='32' fill='{fg2}'/>
        <circle cx='512' cy='512' r='48' fill='{fg1}'/>
        """
    elif mark_type == 'portal':
        return f"""
        <rect x='330' y='270' width='364' height='484' rx='72' fill='none' stroke='{fg1}' stroke-width='40'/>
        <circle cx='512' cy='460' r='100' fill='none' stroke='{fg2}' stroke-width='30'/>
        <circle cx='512' cy='460' r='32' fill='{fg2}'/>
        """
    elif mark_type == 'star':
        return f"""
        <path d='M512 240 L545 440 L745 512 L545 584 L512 784 L479 584 L279 512 L479 440 Z' fill='{fg1}'/>
        <circle cx='512' cy='512' r='40' fill='{fg2}'/>
        """
    elif mark_type == 'sun':
        return f"""
        <circle cx='512' cy='512' r='160' fill='{fg1}'/>
        <circle cx='512' cy='512' r='240' fill='none' stroke='{fg2}' stroke-width='26' stroke-dasharray='24 16'/>
        """
    elif mark_type == 'eclipse':
        return f"""
        <circle cx='512' cy='512' r='180' fill='{fg1}'/>
        <circle cx='475' cy='485' r='160' fill='#0A0A0E'/>
        <circle cx='512' cy='512' r='230' fill='none' stroke='{fg2}' stroke-width='16' opacity='0.8'/>
        """
    elif mark_type == 'leaf':
        return f"""
        <path d='M330 694 C330 450 490 330 694 330 C694 574 534 694 330 694 Z' fill='{fg1}'/>
        <path d='M330 694 L694 330' stroke='{fg2}' stroke-width='32' stroke-linecap='round'/>
        """
    return ''

for name, (c_bg, e_bg, fg1, fg2, mark_type) in ICONS.items():
    folder = assets / f'{name}.appiconset'
    folder.mkdir(exist_ok=True)
    bg_png = tmp_dir / f'{name}_bg.png'
    fg_svg = tmp_dir / f'{name}_fg.svg'
    fg_png = tmp_dir / f'{name}_fg.png'
    final_png = folder / 'icon.png'

    subprocess.run(['magick', '-size', '1024x1024', f'radial-gradient:{c_bg}-{e_bg}', str(bg_png)], check=True)
    mark_content = get_mark_svg(mark_type, fg1, fg2)
    svg_data = f"""<svg xmlns='http://www.w3.org/2000/svg' width='1024' height='1024' viewBox='0 0 1024 1024'>
    <rect x='24' y='24' width='976' height='976' rx='218' fill='none' stroke='#FFFFFF' stroke-width='6' opacity='0.18'/>
    {mark_content}
    </svg>"""
    fg_svg.write_text(svg_data)
    subprocess.run(['magick', '-background', 'none', str(fg_svg), str(fg_png)], check=True)
    subprocess.run(['magick', str(bg_png), str(fg_png), '-composite', str(final_png)], check=True)

    (folder / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': 'icon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
        'info': {'author': 'xcode', 'version': 1}
    }, indent=2))

    preview_folder_name = 'IconPreview' if name == 'AppIcon' else f'{name}Preview'
    preview_folder = assets / f'{preview_folder_name}.imageset'
    preview_folder.mkdir(exist_ok=True)
    preview_png = preview_folder / 'preview.png'

    subprocess.run(['magick', str(final_png), '-resize', '144x144', str(preview_png)], check=True)
    (preview_folder / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': 'preview.png', 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1}
    }, indent=2))

    print(f'Generated {name}: {final_png.stat().st_size} bytes (preview: {preview_png.stat().st_size} bytes)')

watch_folder = root / 'Watch/Assets.xcassets/AppIcon.appiconset'
watch_folder.mkdir(parents=True, exist_ok=True)
shutil.copyfile(assets / 'AppIcon.appiconset/icon.png', watch_folder / 'icon.png')
(watch_folder / 'Contents.json').write_text(json.dumps({
    'images': [{'filename': 'icon.png', 'idiom': 'universal', 'platform': 'watchos', 'size': '1024x1024'}],
    'info': {'author': 'xcode', 'version': 1}
}, indent=2))
print('ALL 24 ICONS GENERATED SUCCESSFULLY!')

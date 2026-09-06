#!/usr/bin/env python3
"""Reproduce original geometric app icons and three short notification chimes."""
from pathlib import Path
import json, subprocess, math, wave, struct
root = Path(__file__).resolve().parents[1]
assets = root / 'Resources/Assets.xcassets'
assets.mkdir(parents=True, exist_ok=True)
(assets / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
colors = {'AppIcon':('#142C46','#A9D8F4'), 'MinimalBlack':('#101010','#FFFFFF'), 'MinimalWhite':('#FFFFFF','#142C46'), 'Gradient':('#284564','#C3E2EE'), 'QuoteMark':('#233755','#FFFFFF'), 'Warm':('#6E3D42','#FDE1C7'), 'Cool':('#244C68','#D6F3F7')}
for name,(bg,fg) in colors.items():
    folder = assets / f'{name}.appiconset'; folder.mkdir(exist_ok=True)
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="{bg}"/><path d="M300 278 H386 V652 H724 V738 H300Z" fill="{fg}"/><path d="M494 316 H602 V424 L548 494 H494 L548 424 H494Z M638 316 H746 V424 L692 494 H638 L692 424 H638Z" fill="{fg}" opacity=".9"/></svg>'''
    svg_path = folder / 'icon.svg'; svg_path.write_text(svg)
    subprocess.run(['magick', '-background', 'none', str(svg_path), str(folder / 'icon.png')], check=True)
    svg_path.unlink()
    (folder / 'Contents.json').write_text(json.dumps({'images':[{'filename':'icon.png','idiom':'universal','platform':'ios','size':'1024x1024'}], 'info':{'author':'xcode','version':1}}))
    preview = assets / (('IconPreview' if name == 'AppIcon' else name + 'Preview') + '.imageset'); preview.mkdir(exist_ok=True)
    subprocess.run(['magick', str(folder/'icon.png'), '-resize', '144x144', str(preview/'preview.png')], check=True)
    (preview/'Contents.json').write_text(json.dumps({'images':[{'filename':'preview.png','idiom':'universal'}], 'info':{'author':'xcode','version':1}}))
watch = root/'Watch/Assets.xcassets/AppIcon.appiconset'; watch.mkdir(parents=True,exist_ok=True)
import shutil
shutil.copyfile(assets/'AppIcon.appiconset/icon.png',watch/'icon.png')
(watch/'Contents.json').write_text(json.dumps({'images':[{'filename':'icon.png','idiom':'universal','platform':'watchos','size':'1024x1024'}], 'info':{'author':'xcode','version':1}}))
for index, hz in enumerate([523.25,659.25,783.99],1):
    path=root/f'Resources/chime{index}.wav'; rate=44100
    with wave.open(str(path),'w') as out:
        out.setnchannels(1); out.setsampwidth(2); out.setframerate(rate)
        out.writeframes(b''.join(struct.pack('<h',int(32767 * .17 * min(1,t/.02) * math.exp(-4*t) * (math.sin(2*math.pi*hz*t)+.25*math.sin(2*math.pi*hz*2*t)))) for t in (i/rate for i in range(int(rate*1.4)))))
    subprocess.run(['afconvert','-f','caff','-d','LEI16',str(path),str(root/f'Resources/chime{index}.caf')],check=True)
    path.unlink()

"""Render CUE's bundled typographic icon. Development-only Pillow dependency."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
image = Image.new('RGB', (1024, 1024), '#754238')
draw = ImageDraw.Draw(image)
cream = '#f7f3ec'
font = ImageFont.truetype(str(root / 'assets/fonts/Manrope.ttf'), 244)
bounds = draw.textbbox((0, 0), 'CUE', font=font)
draw.text(((1024 - (bounds[2] - bounds[0])) / 2 - bounds[0], (1024 - (bounds[3] - bounds[1])) / 2 - bounds[1]), 'CUE', font=font, fill=cream)
draw.line([(194, 330), (194, 228), (332, 228)], fill=cream, width=16)
draw.line([(692, 796), (830, 796), (830, 694)], fill=cream, width=16)
for folder in ['ios/Runner/Assets.xcassets/AppIcon.appiconset', 'macos/Runner/Assets.xcassets/AppIcon.appiconset']:
    directory = root / folder
    contents = json.loads((directory / 'Contents.json').read_text())
    for item in contents['images']:
        if 'filename' not in item:
            continue
        size = round(float(item['size'].split('x')[0]) * float(item['scale'].removesuffix('x')))
        image.resize((size, size), Image.Resampling.LANCZOS).save(directory / item['filename'])
for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    image.resize((size, size), Image.Resampling.LANCZOS).save(root / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png')
image.save(root / 'windows/runner/resources/app_icon.ico', sizes=[(16,16), (32,32), (48,48), (64,64), (128,128), (256,256)])
image.save(root / 'assets/cue-icon.png')
for filename in ['windows/runner/main.cpp', 'windows/runner/Runner.rc', 'linux/runner/my_application.cc']:
    path = root / filename
    text = path.read_text()
    text = text.replace('L"cue"', 'L"CUE"').replace('"cue" "\\0"', '"CUE" "\\0"').replace('"cue"', '"CUE"')
    path.write_text(text, newline='\n')
print('Created CUE icons for iPhone, macOS, Windows and Android.')

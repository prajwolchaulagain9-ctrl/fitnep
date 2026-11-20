"""Render the Figma logo's rounded display shape for native launch screens.

Run from the repository root with Python and Pillow installed.
The original image in assets/images is kept unchanged.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
LOGO = Image.open(ROOT / 'assets/images/fitnep_logo.png').convert('RGBA')
SIZE = (180, round(180 * LOGO.height / LOGO.width))


def rounded_logo(scale):
    size = tuple(round(value * scale) for value in SIZE)
    result = LOGO.resize(size, Image.Resampling.LANCZOS)
    mask = Image.new('L', size)
    ImageDraw.Draw(mask).ellipse((0, 0, size[0] - 1, size[1] - 1), fill=255)
    result.putalpha(mask)
    return result


for density, scale in [('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)]:
    directory = ROOT / f'android/app/src/main/res/drawable-{density}'
    directory.mkdir(parents=True, exist_ok=True)
    logo = rounded_logo(scale)
    logo.save(directory / 'fitnep_splash.png')
    # Android 12 masks splash icons; keep the complete logo in the safe center.
    canvas_size = round(288 * scale)
    canvas = Image.new('RGBA', (canvas_size, canvas_size))
    canvas.alpha_composite(logo, ((canvas_size - logo.width) // 2, (canvas_size - logo.height) // 2))
    canvas.save(directory / 'fitnep_splash_android12.png')

for suffix, scale in [('', 1), ('@2x', 2), ('@3x', 3)]:
    rounded_logo(scale).save(ROOT / f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png')

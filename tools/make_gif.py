"""Turn the frames tools/record_gif.gd saved into docs/demo.gif.

    python tools/make_gif.py

Needs Pillow. Frames are every fourth of 60 a second, so 15 a second.
"""
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
FRAMES = sorted((ROOT / "export" / "frames").glob("*.png"))
WIDTH = 640

if not FRAMES:
    raise SystemExit("no frames: run tools/record_gif.gd first")

images = []
for path in FRAMES:
    im = Image.open(path).convert("RGB")
    im = im.resize((WIDTH, round(im.height * WIDTH / im.width)), Image.LANCZOS)
    images.append(im)

# One palette for every frame, taken from a spread of them, so colours do not
# flicker from frame to frame.
sample = Image.new("RGB", (WIDTH, images[0].height * 4))
for i, im in enumerate(images[:: max(1, len(images) // 4)][:4]):
    sample.paste(im, (0, i * im.height))
palette = sample.quantize(colors=128, method=Image.MEDIANCUT)
frames = [im.quantize(palette=palette, dither=Image.NONE) for im in images]

out = ROOT / "docs" / "demo.gif"
durations = [66] * len(frames)
durations[-1] = 1500  # hold the last frame before the loop
frames[0].save(out, save_all=True, append_images=frames[1:], duration=durations,
               loop=0, optimize=True)
print(f"{out.relative_to(ROOT)}: {len(frames)} frames, {out.stat().st_size / 1e6:.1f} MB")

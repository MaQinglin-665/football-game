"""Original seamless 512px grass data texture; no external imagery or samples.

R: fine blade albedo variation   G: tileable clump/macro variation
B: blade normal X (world +x)     A: blade normal Z (world +z)
All channels are linear data; the shader reads them without source_color.
"""
from pathlib import Path
import json
import math
import random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "textures"
SIZE = 512
SEED = 51042026
rng = random.Random(SEED)
nrng = np.random.default_rng(SEED)


def periodic_fbm(beta: float, low_cut: float, high_cut: float) -> np.ndarray:
    # Filtering white noise in the frequency domain is exactly tileable.
    noise = nrng.standard_normal((SIZE, SIZE))
    fx = np.fft.fftfreq(SIZE)[None, :]
    fy = np.fft.fftfreq(SIZE)[:, None]
    f = np.sqrt(fx * fx + fy * fy) * SIZE
    amp = np.where(f > 0, 1.0 / np.maximum(f, 1e-6) ** beta, 0.0)
    amp *= 1.0 / (1.0 + np.exp((low_cut - f) * 1.5))
    amp *= np.exp(-(f / high_cut) ** 2)
    field = np.real(np.fft.ifft2(np.fft.fft2(noise) * amp))
    field -= field.mean()
    return field / (field.std() + 1e-9)


def blades(count: int, length: tuple, value_range: tuple, width: int) -> tuple:
    # Draw on a 3x3 tiled canvas, crop the middle tile after filtering.
    height = Image.new("L", (SIZE * 3, SIZE * 3), 0)
    tone = Image.new("L", (SIZE * 3, SIZE * 3), 128)
    dh, dt = ImageDraw.Draw(height), ImageDraw.Draw(tone)
    for _ in range(count):
        x, y = rng.uniform(0, SIZE), rng.uniform(0, SIZE)
        # Top-down blades point everywhere, with a mild mowing lean along v.
        angle = rng.gauss(math.pi * 0.5, 0.75) + (math.pi if rng.random() < 0.5 else 0.0)
        ln = rng.uniform(*length)
        dx, dy = math.cos(angle) * ln, math.sin(angle) * ln
        h = rng.randrange(150, 256)
        t = rng.randrange(*value_range)
        for ox in (-SIZE, 0, SIZE):
            for oy in (-SIZE, 0, SIZE):
                seg = (x + SIZE + ox, y + SIZE + oy, x + SIZE + ox + dx, y + SIZE + oy + dy)
                dh.line(seg, fill=h, width=width)
                dt.line(seg, fill=t, width=width)
    crop = (SIZE, SIZE, SIZE * 2, SIZE * 2)
    return (np.asarray(height.filter(ImageFilter.GaussianBlur(.6)).crop(crop), np.float32) / 255.0,
            np.asarray(tone.filter(ImageFilter.GaussianBlur(.5)).crop(crop), np.float32) / 255.0)


clumps = periodic_fbm(1.1, 3.0, 40.0)      # ~5-15 cm tufts at a 1.6 m tile
macro = periodic_fbm(1.6, 1.0, 10.0)       # broad patches, read at a large rotated tile
grain = periodic_fbm(0.2, 60.0, 220.0)     # soil/thatch grain between blades
h_far, t_far = blades(9000, (5, 11), (70, 150), 2)
h_near, t_near = blades(26000, (3, 8), (95, 200), 1)

height = 0.45 * h_far + 0.75 * h_near + 0.10 * clumps + 0.04 * grain
albedo = 0.5 * t_far + 0.5 * t_near
albedo = albedo + 0.10 * (h_near - h_near.mean()) + 0.035 * clumps + 0.02 * grain
albedo = 0.5 + (albedo - albedo.mean()) * (0.23 / (albedo.std() + 1e-9))
macro_g = 0.5 + macro * 0.17

# Heightfield y = h(x, z): normal = (-dh/dx, 1, -dh/dz).
k = 2.4
gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * k
gz = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * k
inv = 1.0 / np.sqrt(gx * gx + gz * gz + 1.0)
nx, nz = -gx * inv, -gz * inv


def to8(a: np.ndarray) -> np.ndarray:
    return np.clip(np.rint(a * 255.0), 0, 255).astype(np.uint8)


packed = np.stack([to8(albedo), to8(macro_g), to8(nx * 0.5 + 0.5), to8(nz * 0.5 + 0.5)], axis=-1)
Image.fromarray(packed, "RGBA").save(OUT / "grass_detail_hd_512.png", optimize=True)
(OUT / "provenance_hd_512.json").write_text(json.dumps({
    "license": "CC0-1.0", "generator": "tools/generate_grass_texture_hd.py", "seed": SEED,
    "size": [SIZE, SIZE], "channels": {"R": "fine blade albedo variation", "G": "tileable clump/macro variation",
    "B": "blade normal x (0.5 = flat)", "A": "blade normal z (0.5 = flat)"},
    "color_space": "linear data (not source_color)", "external_sources": []}, indent=2), encoding="utf-8")
print("GRASS_HD_TEXTURE bytes=%d size=%dx%d" % ((OUT / "grass_detail_hd_512.png").stat().st_size, SIZE, SIZE))

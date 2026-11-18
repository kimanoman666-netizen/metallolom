"""Генерирует текстуры эффектов: дым, огонь, вспышка выстрела, следы пуль, копоть.
Запуск: python tools/gen_fx_textures.py  → assets/fx/*.png
"""
import math
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "fx")
rng = np.random.default_rng(7)


def fbm(n, octaves=5, seed=0):
    r = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        f = 4 * 2 ** o
        g = r.random((f + 1, f + 1))
        g[-1, :] = g[0, :]
        g[:, -1] = g[:, 0]
        x = np.linspace(0, f, n, endpoint=False)
        xi = x.astype(int)
        xf = x - xi
        xf = xf * xf * (3 - 2 * xf)
        a = g[np.ix_(xi, xi)]
        b = g[np.ix_(xi + 1, xi)]
        c = g[np.ix_(xi, xi + 1)]
        d = g[np.ix_(xi + 1, xi + 1)]
        u = xf[:, None]
        v = xf[None, :]
        out += amp * (a * (1 - u) * (1 - v) + b * u * (1 - v) + c * (1 - u) * v + d * u * v)
        total += amp
        amp *= 0.5
    return out / total


def radial(n):
    y, x = np.mgrid[0:n, 0:n]
    c = (n - 1) / 2
    return np.sqrt((x - c) ** 2 + (y - c) ** 2) / c, np.arctan2(y - c, x - c)


def save(name, rgba):
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(np.clip(rgba * 255, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))
    print("saved", name)


def smoke():
    n = 256
    r, _ = radial(n)
    noise = fbm(n, 6, 1)
    shape = np.clip(1.0 - r * (0.85 + noise * 0.5), 0, 1)
    alpha = np.clip(shape * 1.6, 0, 1) ** 1.4 * (0.55 + noise * 0.6)
    lum = 0.75 + noise * 0.25
    rgba = np.dstack([lum, lum, lum, np.clip(alpha, 0, 1)])
    save("smoke.png", rgba)


def fire():
    n = 256
    r, _ = radial(n)
    noise = fbm(n, 5, 2)
    core = np.clip(1.0 - r * (1.0 + noise * 0.6), 0, 1)
    t = core ** 0.7
    col = np.dstack([np.ones_like(t), 0.25 + 0.65 * t, 0.05 + 0.5 * t ** 2])
    rgba = np.dstack([col, np.clip(core * 1.5, 0, 1)])
    save("fire.png", rgba)


def muzzle():
    n = 256
    r, a = radial(n)
    rays = np.zeros_like(r)
    for k in range(5):
        ang = k * math.tau / 5 + 0.3
        d = np.abs(np.angle(np.exp(1j * (a - ang))))
        rays = np.maximum(rays, np.clip(1 - d / (0.18 + 0.1 * (k % 2)), 0, 1) * np.clip(1 - r / (0.7 + 0.25 * (k % 2)), 0, 1))
    core = np.clip(1 - r / 0.35, 0, 1) ** 1.5
    v = np.clip(rays ** 1.5 + core, 0, 1)
    rgba = np.dstack([np.ones_like(v), 0.55 + 0.4 * v, 0.2 + 0.6 * v ** 2, v])
    save("muzzle.png", rgba)


def bullet_hole():
    n = 128
    r, a = radial(n)
    noise = fbm(n, 4, 3)
    hole = np.clip(1 - r / 0.16, 0, 1)
    ring = np.clip(1 - np.abs(r - 0.22) / 0.1, 0, 1) * (0.6 + noise * 0.6)
    cracks = np.zeros_like(r)
    for k in range(7):
        ang = k * math.tau / 7 + rng.random()
        d = np.abs(np.angle(np.exp(1j * (a - ang))))
        cracks = np.maximum(cracks, np.clip(1 - d / 0.05, 0, 1) * np.clip(1 - r / (0.5 + rng.random() * 0.3), 0, 1))
    soot = np.clip(1 - r / 0.75, 0, 1) ** 2 * 0.6 * (0.5 + noise)
    dark = np.clip(hole + ring * 0.7 + cracks * 0.6 + soot, 0, 1)
    lum = 0.04 + 0.12 * (1 - dark)
    rgba = np.dstack([lum, lum * 0.95, lum * 0.9, np.clip(dark * 1.2, 0, 1)])
    save("bullet_hole.png", rgba)


def scorch():
    n = 256
    r, _ = radial(n)
    noise = fbm(n, 6, 4)
    a = np.clip(1 - r * (0.9 + noise * 0.7), 0, 1) ** 0.8
    lum = 0.02 + 0.05 * noise
    rgba = np.dstack([lum, lum * 0.9, lum * 0.8, np.clip(a * 1.3, 0, 0.95)])
    save("scorch.png", rgba)


def oil():
    n = 256
    r, _ = radial(n)
    noise = fbm(n, 5, 5)
    a = np.clip(1 - r * (0.7 + noise * 1.1), 0, 1) ** 0.6
    lum = 0.03 + 0.02 * noise
    rgba = np.dstack([lum, lum, lum * 1.1, a * 0.75])
    save("oil.png", rgba)


def spark():
    n = 64
    y, x = np.mgrid[0:n, 0:n]
    c = (n - 1) / 2
    d = np.sqrt(((x - c) / c) ** 2 * 1.0 + ((y - c) / c) ** 2)
    v = np.clip(1 - d, 0, 1) ** 2
    rgba = np.dstack([np.ones_like(v), 0.8 * np.ones_like(v), 0.5 * np.ones_like(v), v])
    save("spark.png", rgba)


if __name__ == "__main__":
    smoke()
    fire()
    muzzle()
    bullet_hole()
    scorch()
    oil()
    spark()

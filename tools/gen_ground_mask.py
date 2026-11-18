"""Маска покрытия земли: R — асфальт, G — трава/земля, B — бетон (остальное).
Карта 512×512 покрывает мир от -150 до 150 м по X и Z.
Запуск: python tools/gen_ground_mask.py → assets/ground_mask.png
"""
import os
import numpy as np
from PIL import Image

import importlib.util
spec = importlib.util.spec_from_file_location("fx", os.path.join(os.path.dirname(__file__), "gen_fx_textures.py"))
fx = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fx)

N = 512
W = 300.0
xs = (np.arange(N) + 0.5) / N * W - W / 2
X, Z = np.meshgrid(xs, xs)          # строка = Z, столбец = X
n1 = fx.fbm(N, 6, 11)
n2 = fx.fbm(N, 6, 12)
wob = (n1 - 0.5) * 3.0

# асфальт: дорога восток-запад, дорога север-юг, парковка
road = np.zeros((N, N))
road = np.maximum(road, np.clip(6.5 - np.abs(Z - 2.0 + wob), 0, 1))
road = np.maximum(road, np.clip(5.5 - np.abs(X + 6.0 + wob), 0, 1))
park = (X > -44) & (X < -18) & (Z > 16) & (Z < 42)
road = np.maximum(road, park * np.clip((n2 - 0.25) * 4, 0, 1))
# трещины и проплешины в асфальте
road *= np.clip(1.4 - n2 * 1.2, 0, 1)

# трава: у стен, по углам и пятнами
edge = np.maximum(np.abs(X), np.abs(Z))
grass = np.clip((edge - 34.0 + wob * 2) / 6.0, 0, 1)
grass = np.maximum(grass, np.clip((n1 - 0.5) * 5.0, 0, 1) * np.clip((n2 - 0.35) * 4.0, 0, 1))
grass *= np.clip(1.0 - road * 1.5, 0, 1)
# центр арены — бетонная площадка
plaza = np.clip(1.0 - (np.sqrt(X ** 2 + Z ** 2) - 16.0 + wob * 2) / 4.0, 0, 1)
grass *= 1.0 - plaza * 0.9
road *= 1.0 - plaza * 0.6

img = np.dstack([road, grass, plaza, np.ones_like(road)])
out = os.path.join(os.path.dirname(__file__), "..", "assets", "ground_mask.png")
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(out)
print("saved", out)

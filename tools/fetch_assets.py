"""Скачивает CC0-ассеты с Poly Haven (https://polyhaven.com, лицензия CC0) в папку assets/.

Запуск: python tools/fetch_assets.py
Модели — glTF 1k, текстуры — 2k (цвет, нормаль, ARM: AO/шероховатость/металл), небо — HDRI 4k.
"""
import json
import os
import sys
import urllib.request

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets")

MODELS = [
    # постройки и укрытия
    "modular_factory_facade", "modular_urban_apartments_facade", "concrete_road_barrier",
    "concrete_road_barrier_02", "covered_car", "modular_chainlink_fence", "modular_electricity_poles",
    "street_lamp_01", "utility_box_01", "modular_industrial_pipes_01", "water_manhole_cover",     # мелочь
    "barrel_03", "old_tyre", "rusted_wheel_rim_01", "metal_jerrycan", "wooden_crate_01",
    "cardboard_box_01", "ammo_box", "medical_box",
    # природа
    "grass_medium_01", "grass_medium_02", "shrub_02", "fern_02", "nettle_plant",
    "weed_plant_02", "dead_tree_trunk", "boulder_01", "rock_moss_set_01",
]

TEXTURES = [
    "worn_asphalt", "sparse_grass", "dirt", "cracked_concrete", "red_brick", "concrete_wall_006",
    "rusty_corrugated_iron", "metal_plate_02", "rusty_metal_02", "denim_fabric_04", "fabric_leather_01",
    "brown_mud_leaves_01",
]

HDRI = "kloofendal_48d_partly_cloudy_puresky"


def get(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "metallolom-fetch"})
    with urllib.request.urlopen(req, timeout=120) as r, open(path, "wb") as f:
        f.write(r.read())


def api(asset):
    req = urllib.request.Request(f"https://api.polyhaven.com/files/{asset}", headers={"User-Agent": "metallolom-fetch"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def main():
    only = sys.argv[1:]
    for m in MODELS:
        if only and m not in only:
            continue
        d = api(m)["gltf"]["1k"]["gltf"]
        base = os.path.join(ROOT, "models", m)
        get(d["url"], os.path.join(base, f"{m}.gltf"))
        for rel, inc in d["include"].items():
            get(inc["url"], os.path.join(base, rel))
        print("model", m)
    for t in TEXTURES:
        if only and t not in only:
            continue
        d = api(t)
        base = os.path.join(ROOT, "textures", t)
        for key, short in (("Diffuse", "diff"), ("nor_gl", "nor"), ("arm", "arm")):
            if key in d:
                get(d[key]["2k"]["jpg"]["url"], os.path.join(base, f"{t}_{short}.jpg"))
        print("texture", t)
    if not only or HDRI in only:
        d = api(HDRI)
        get(d["hdri"]["4k"]["hdr"]["url"], os.path.join(ROOT, "sky", f"{HDRI}.hdr"))
        print("hdri", HDRI)


if __name__ == "__main__":
    main()

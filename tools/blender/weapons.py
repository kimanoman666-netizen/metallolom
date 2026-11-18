"""Оружие МЕТАЛЛОЛОМА. Запуск: python weapons.py <папка_моделей> [--render <папка>]

Оси Blender: +Y — ствол вперёд, +Z — вверх, начало координат — у спускового крючка.
Подвижные детали (контракт с игрой): lever, drum, barrels; точка вылета — muzzle.
"""
import math
import bpy  # noqa: F401
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from lib import Part, mat, reset, empty, update, export_glb  # noqa: E402

SW = lambda: mat("steel_worn")  # noqa: E731
SD = lambda: mat("steel_dark")  # noqa: E731
RU = lambda: mat("rust")  # noqa: E731
WH = lambda: mat("paint_white")  # noqa: E731
BR = lambda: mat("brass")  # noqa: E731
RB = lambda: mat("rubber")  # noqa: E731
CB = lambda: mat("cable")  # noqa: E731
GL = lambda: mat("glass")  # noqa: E731
BL = lambda: mat("glow_blue")  # noqa: E731


def skeletal_stock(p, y0=-0.1, y1=-0.52, z_top=0.03, z_bot=-0.07):
    p.rod((0, y0, z_top), (0, y1, z_top - 0.03), 0.012, SD())
    p.rod((0, y0 - 0.03, z_bot), (0, y1, z_bot - 0.06), 0.012, SD())
    p.rod((0, y1 + 0.08, z_top - 0.025), (0, y1 + 0.08, z_bot - 0.05), 0.01, SD())
    p.box((0.045, 0.035, 0.17), RB(), loc=(0, y1 - 0.01, (z_top + z_bot) / 2 - 0.035), bevel=0.008)
    p.box((0.05, 0.05, 0.19), SD(), loc=(0, y1 + 0.02, (z_top + z_bot) / 2 - 0.035), bevel=0.008)


def pistol_grip(p, y=-0.06, z=-0.05):
    p.box((0.035, 0.05, 0.12), SD(), loc=(0, y, z - 0.05), rot=(-18, 0, 0), bevel=0.01)


def trigger(p):
    p.bent_bar([(0, 0.02, -0.04), (0, 0.025, -0.075), (0, -0.04, -0.08), (0, -0.05, -0.05)], 0.005, SD(), n=6)
    p.box((0.008, 0.012, 0.03), SD(), loc=(0, 0.0, -0.055), rot=(15, 0, 0), bevel=0.0)


# ============================================================ рычажная винтовка

def rifle():
    w = Part("body")
    w.box((0.06, 0.3, 0.1), SW(), loc=(0, 0.04, 0.0), bevel=0.01)          # ствольная коробка
    w.box((0.062, 0.12, 0.04), RU(), loc=(0, 0.02, -0.02), bevel=0.006)
    w.cyl(0.017, 0.95, SD(), loc=(0, 0.62, 0.03), rot=(90, 0, 0), n=14)    # ствол
    # кожух с прорезями
    w.box((0.055, 0.62, 0.06), SW(), loc=(0, 0.52, 0.03), bevel=0.008)
    for i in range(5):
        for sx in (-1, 1):
            w.box((0.004, 0.08, 0.03), SD(), loc=(sx * 0.0285, 0.3 + i * 0.11, 0.03), bevel=0.0)
    w.cyl(0.015, 0.6, RU(), loc=(0, 0.5, -0.015), rot=(90, 0, 0), n=10)    # подствольный магазин
    w.box((0.06, 0.05, 0.08), SD(), loc=(0, 0.86, 0.02), bevel=0.008)     # дульный узел
    w.ring(0.024, 0.016, 0.03, SW(), loc=(0, 1.1, 0.03), rot=(90, 0, 0), n=14)
    w.box((0.02, 0.04, 0.03), SD(), loc=(0, 1.04, 0.07), bevel=0.003)    # мушка
    w.box((0.03, 0.05, 0.03), SD(), loc=(0, 0.12, 0.065), bevel=0.004)   # целик
    w.cyl(0.018, 0.08, SW(), loc=(0, 0.18, 0.085), rot=(90, 0, 0), n=10)
    # проволочная обмотка
    for y in (0.24, 0.27, 0.66, 0.69):
        w.ring(0.036, 0.032, 0.008, CB(), loc=(0, y, 0.03), rot=(90, 0, 0), n=12)
    pistol_grip(w)
    trigger(w)
    skeletal_stock(w)
    ob = w.build()
    lv = Part("lever")
    lv.bent_bar([(0, 0.0, 0.0), (0, 0.0, -0.06), (0, -0.05, -0.1), (0, -0.13, -0.1), (0, -0.16, -0.06), (0, -0.12, -0.03)],
                0.008, SW(), n=8)
    lv.build(parent=ob, loc=(0, 0.03, -0.05))
    empty("muzzle", parent=ob, loc=(0, 1.13, 0.03))
    return ob


# ============================================================ дробовик

def shotgun():
    w = Part("body")
    w.box((0.075, 0.8, 0.09), SW(), loc=(0, 0.4, 0.02), bevel=0.01)
    w.box((0.08, 0.25, 0.11), SD(), loc=(0, 0.02, 0.02), bevel=0.01)
    w.box((0.03, 0.75, 0.015), SD(), loc=(0, 0.42, 0.072), bevel=0.003)   # планка
    for i in range(6):
        w.box((0.034, 0.02, 0.012), SD(), loc=(0, 0.1 + i * 0.13, 0.083), bevel=0.0)
    w.box((0.085, 0.06, 0.1), SD(), loc=(0, 0.82, 0.02), bevel=0.01)
    w.cyl(0.026, 0.06, SD(), loc=(0, 0.86, 0.035), rot=(90, 0, 0), n=14)
    # ряд патронов под стволом
    for i in range(7):
        y = 0.18 + i * 0.09
        w.cyl(0.021, 0.07, RU(), loc=(0, y, -0.048), rot=(0, 90, 0), n=12)
        w.cyl(0.023, 0.012, BR(), loc=(0.036, y, -0.048), rot=(0, 90, 0), n=12)
        w.cyl(0.023, 0.012, BR(), loc=(-0.036, y, -0.048), rot=(0, 90, 0), n=12)
    w.box((0.02, 0.68, 0.02), SD(), loc=(0, 0.45, -0.075), bevel=0.003)
    # прицел-коробка и шланг
    w.box((0.045, 0.08, 0.05), WH(), loc=(0, 0.06, 0.1), bevel=0.006)
    w.cyl(0.015, 0.02, GL(), loc=(0, 0.1, 0.105), rot=(90, 0, 0), n=10)
    w.bent_bar([(0.03, 0.1, 0.06), (0.06, 0.0, 0.07), (0.06, -0.12, 0.02), (0.03, -0.2, -0.02)], 0.007, CB(), n=6)
    w.box((0.04, 0.05, 0.04), RU(), loc=(0.045, 0.22, 0.0), bevel=0.004)
    pistol_grip(w)
    trigger(w)
    skeletal_stock(w, y0=-0.1, y1=-0.5)
    ob = w.build()
    pump = Part("lever")
    pump.bent_bar([(0, 0.0, 0.0), (0, 0.0, -0.05), (0, -0.05, -0.09), (0, -0.13, -0.09), (0, -0.15, -0.05)], 0.008, SW(), n=8)
    pump.build(parent=ob, loc=(0, 0.03, -0.04))
    empty("muzzle", parent=ob, loc=(0, 0.9, 0.035))
    return ob


# ============================================================ миниган (вращающиеся стволы)

def minigun():
    w = Part("body")
    w.prism(10, 0.07, 0.07, -0.08, 0.5, WH(), rot=(-90, 0, 0), bevel=0.01)     # корпус-цилиндр
    w.box((0.1, 0.42, 0.04), WH(), loc=(0, 0.22, 0.075), bevel=0.008)
    for i in range(6):
        w.box((0.08, 0.03, 0.005), SD(), loc=(0, 0.08 + i * 0.05, 0.096), bevel=0.0)
    w.box((0.035, 0.05, 0.02), mat("glow_blue"), loc=(0.05, 0.4, 0.08), bevel=0.0)
    w.prism(10, 0.085, 0.085, 0.5, 0.56, SD(), rot=(-90, 0, 0), bevel=0.006)
    # клетка вокруг стволов
    for k in range(3):
        a = k * math.tau / 3 + 0.5
        x, z = math.cos(a) * 0.085, math.sin(a) * 0.085
        w.rod((x, 0.55, z), (x, 0.97, z), 0.007, SD())
    w.ring(0.095, 0.085, 0.02, SD(), loc=(0, 0.97, 0), rot=(90, 0, 0), n=16)
    w.ring(0.095, 0.085, 0.02, SD(), loc=(0, 0.75, 0), rot=(90, 0, 0), n=16)
    # ручка для переноски
    w.bent_bar([(0, 0.05, 0.09), (0, 0.06, 0.2), (0.02, 0.18, 0.25), (0.04, 0.24, 0.2)], 0.01, SD(), n=8)
    w.box((0.02, 0.05, 0.04), RU(), loc=(0.04, 0.25, 0.2), bevel=0.003)
    # мотор сзади и короб с лентой
    w.cyl(0.055, 0.12, SD(), loc=(0, -0.13, 0.0), rot=(90, 0, 0), n=14)
    w.cyl(0.04, 0.06, SW(), loc=(0, -0.21, 0.0), rot=(90, 0, 0), n=14)
    w.box((0.1, 0.22, 0.12), WH(), loc=(-0.02, 0.15, -0.13), bevel=0.012)
    w.box((0.102, 0.03, 0.12), SD(), loc=(-0.02, 0.06, -0.13), bevel=0.0)
    w.bent_bar([(0.05, -0.15, 0.05), (0.09, -0.05, 0.08), (0.08, 0.1, 0.06)], 0.008, CB(), n=6)
    pistol_grip(w, y=-0.02, z=-0.07)
    trigger(w)
    ob = w.build()
    br = Part("barrels")
    for k in range(6):
        a = k * math.tau / 6
        x, z = math.cos(a) * 0.045, math.sin(a) * 0.045
        br.cyl(0.016, 0.42, SD(), loc=(x, 0.21, z), rot=(90, 0, 0), n=10)
        br.ring(0.018, 0.012, 0.015, SW(), loc=(x, 0.42, z), rot=(90, 0, 0), n=10)
    br.cyl(0.07, 0.03, SW(), loc=(0, 0.05, 0), rot=(90, 0, 0), n=14)
    br.cyl(0.068, 0.025, SW(), loc=(0, 0.3, 0), rot=(90, 0, 0), n=14)
    br.cyl(0.02, 0.4, SD(), loc=(0, 0.2, 0), rot=(90, 0, 0), n=8)
    br.build(parent=ob, loc=(0, 0.56, 0))
    empty("muzzle", parent=ob, loc=(0, 1.0, 0))
    return ob


# ============================================================ барабанный гранатомёт

def launcher():
    w = Part("body")
    w.cyl(0.05, 0.6, SW(), loc=(0, 0.52, 0.03), rot=(90, 0, 0), n=16)    # ствол
    w.ring(0.058, 0.044, 0.05, SD(), loc=(0, 0.83, 0.03), rot=(90, 0, 0), n=16)
    w.ring(0.056, 0.05, 0.02, RU(), loc=(0, 0.45, 0.03), rot=(90, 0, 0), n=16)
    w.box((0.03, 0.55, 0.025), SD(), loc=(0, 0.5, -0.03), bevel=0.004)
    w.box((0.09, 0.2, 0.13), SW(), loc=(0, -0.02, 0.0), bevel=0.012)    # коробка
    w.box((0.092, 0.06, 0.13), RU(), loc=(0, 0.05, 0.0), bevel=0.006)
    # рама барабана
    w.box((0.03, 0.2, 0.02), SD(), loc=(0, 0.17, 0.115), bevel=0.003)
    w.box((0.03, 0.2, 0.02), SD(), loc=(0, 0.17, -0.06), bevel=0.003)
    # прицел и провода
    w.box((0.05, 0.09, 0.05), WH(), loc=(0, 0.04, 0.16), bevel=0.006)
    w.cyl(0.016, 0.02, GL(), loc=(0, 0.09, 0.165), rot=(90, 0, 0), n=10)
    w.box((0.02, 0.03, 0.05), SD(), loc=(0, 0.02, 0.11), bevel=0.003)
    for k, c in enumerate((CB(), RU())):
        off = 0.015 if k == 0 else -0.015
        w.bent_bar([(0.045 + off, 0.12, 0.13), (0.06 + off, 0.02, 0.17), (0.07 + off, -0.08, 0.1), (0.05 + off, -0.12, 0.02)], 0.006, c, n=6)
    # передняя рукоять
    w.box((0.035, 0.05, 0.11), SD(), loc=(0, 0.4, -0.08), rot=(10, 0, 0), bevel=0.008)
    pistol_grip(w)
    trigger(w)
    skeletal_stock(w, y0=-0.12, y1=-0.48)
    ob = w.build()
    dr = Part("drum")
    dr.prism(8, 0.085, 0.085, -0.08, 0.08, SW(), rot=(-90, 0, 0), bevel=0.008, phase=math.pi / 8)
    for k in range(4):
        a = k * math.tau / 4 + math.pi / 4
        x, z = math.cos(a) * 0.045, math.sin(a) * 0.045
        dr.cyl(0.028, 0.02, RB(), loc=(x, 0.075, z), rot=(90, 0, 0), n=14)
        dr.ring(0.032, 0.027, 0.02, BR(), loc=(x, 0.078, z), rot=(90, 0, 0), n=14)
    for k in range(8):
        a = k * math.tau / 8
        dr.box((0.012, 0.14, 0.012), SD(), loc=(math.cos(a) * 0.086, 0, math.sin(a) * 0.086), rot=(0, -math.degrees(a), 0), bevel=0.0)
    dr.build(parent=ob, loc=(0, 0.17, 0.03))
    empty("muzzle", parent=ob, loc=(0, 0.86, 0.03))
    return ob


BUILDERS = {"rifle": rifle, "shotgun": shotgun, "minigun": minigun, "launcher": launcher}

if __name__ == "__main__":
    out = sys.argv[1]
    render_dir = sys.argv[sys.argv.index("--render") + 1] if "--render" in sys.argv else None
    os.makedirs(out, exist_ok=True)
    for name, fn in BUILDERS.items():
        reset()
        fn()
        update()
        export_glb(os.path.join(out, f"{name}.glb"))
        print("exported", name)
        if render_dir:
            import render
            render.render_scene(os.path.join(render_dir, f"w_{name}.png"), name, yaw=75, pitch=8,
                                res=(1000, 460), floor=False, samples=32, dist_mul=1.0)

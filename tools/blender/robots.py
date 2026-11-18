"""Роботы МЕТАЛЛОЛОМА по референсам. Запуск: python robots.py <папка_моделей> [--render <папка_рендеров>]

Имена объектов — это контракт с игрой (scripts/robot*.gd):
  body          — корпус (смерть, если уничтожен)
  eye / core    — глаз/ядро
  thigh_N, shin_N, knee_N, calf_N, end_N — ноги (knee_N — слабая точка)
  rotor_N, blades_N — роторы дронов (blades крутятся)
  gun, pod_l, pod_r — оружие; muzzle* — точки вылета снарядов
"""
import math
import bpy  # noqa: F401  (bpy подгружает mathutils)
import sys
import os
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
from lib import Part, mat, reset, empty, update, aim_bone, solve_leg, export_glb  # noqa: E402


D = lambda: mat("metal_dark")  # noqa: E731
MID = lambda: mat("metal_mid")  # noqa: E731
LT = lambda: mat("metal_light")  # noqa: E731
J = lambda: mat("joint")  # noqa: E731
BLUE = lambda: mat("glow_blue")  # noqa: E731
RUB = lambda: mat("rubber")  # noqa: E731
GLASS = lambda: mat("glass")  # noqa: E731


# ============================================================ ПРЫГУН (4 длинные ноги)

def leaper():
    H = 2.4  # высота корпуса
    K = 1.35  # масштаб корпуса
    body = Part("body")
    # основной гранёный корпус
    body.hull([(0.32, 0.95, 0.15), (0.28, 0.85, -0.45), (0.55, 0.15, 0.45), (0.52, 0.1, -0.55),
               (0.45, -0.75, 0.35), (0.34, -0.75, -0.38), (0.0, 0.1, 0.62), (0.0, -0.55, 0.52)],
              D(), mirror_x=True, bevel=0.035)
    # верхняя бронепластина
    body.hull([(0.3, 0.7, 0.42), (0.42, 0.0, 0.62), (0.32, -0.6, 0.55), (0.0, 0.0, 0.72), (0.0, 0.6, 0.5),
               (0.25, 0.65, 0.3), (0.38, 0.0, 0.5), (0.28, -0.6, 0.42)], MID(), mirror_x=True, bevel=0.02)
    # «голова» спереди снизу
    body.hull([(0.3, 0.55, -0.3), (0.26, 1.05, -0.35), (0.3, 0.55, -0.95), (0.22, 1.0, -0.85)], D(),
              mirror_x=True, bevel=0.03)
    body.box((0.7, 0.4, 0.25), MID(), loc=(0, 0.55, -0.98), bevel=0.03)
    # оправа глаза
    body.cyl(0.26, 0.16, D(), loc=(0, 1.02, -0.6), rot=(90, 0, 0), n=8, smooth=False, bevel=0.01)
    # механика снизу
    body.cyl(0.18, 0.9, MID(), loc=(0, -0.2, -0.62), rot=(90, 0, 0), n=10, smooth=False)
    for sx in (-1, 1):
        body.box((0.12, 0.6, 0.12), LT(), loc=(sx * 0.22, -0.2, -0.75))
    # крепления ног
    for sx in (-1, 1):
        for sy in (-1, 1):
            body.hull([(0.0, 0.0, 0.0), (0.38, 0.0, 0.0), (0.0, 0.38, 0.0), (0.0, 0.0, 0.4), (0.3, 0.3, 0.25)],
                      MID(), loc=(sx * 0.42, sy * 0.45, 0.05), rot=(0, 0, {(1, 1): 0, (-1, 1): 90, (-1, -1): 180, (1, -1): 270}[(sx, sy)]),
                      bevel=0.02)
    # задний «хвост» с огнями
    body.box((0.5, 0.18, 0.3), MID(), loc=(0, -0.85, 0.1), bevel=0.03)
    body.box((0.3, 0.02, 0.05), BLUE(), loc=(0, -0.95, 0.15), bevel=0.0)
    # масштабируем всю геометрию корпуса
    import bmesh as _bm
    from mathutils import Matrix as _M
    _bm.ops.scale(body.bm, vec=(K, K, K), verts=body.bm.verts)
    ob_body = body.build(loc=(0, 0, H))

    eye = Part("eye")
    eye.ring(0.2, 0.14, 0.06, BLUE(), loc=(0, 0.05, 0), rot=(90, 0, 0), n=28)
    eye.sphere(0.15, GLASS(), loc=(0, 0.0, 0), scale=(1, 0.6, 1))
    eye.cyl(0.05, 0.02, BLUE(), loc=(0, 0.1, 0), rot=(90, 0, 0), n=16)
    eye.ring(0.24, 0.2, 0.05, mat("metal_light"), loc=(0, 0.02, 0), rot=(90, 0, 0), n=28)
    _bm.ops.scale(eye.bm, vec=(K, K, K), verts=eye.bm.verts)
    eye.build(parent=ob_body, loc=(0, 1.08 * K, -0.6 * K))

    La, Lb, Lk, Lc = 2.0, 1.5, 0.3, 2.1
    corners = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
    for i, (sx, sy) in enumerate(corners):
        thigh = Part(f"thigh_{i}")
        thigh.prism(6, 0.3, 0.23, 0.0, -La, D(), sx=1.0, sy=1.25, bevel=0.03)
        thigh.hull([(0.2, -0.26, -0.15), (0.2, 0.26, -0.15), (0.14, -0.22, -La + 0.25), (0.14, 0.22, -La + 0.25),
                    (0.31, 0.0, -0.4), (0.27, 0.0, -La + 0.4)], MID(), bevel=0.02)
        thigh.cyl(0.05, La * 0.6, LT(), loc=(-0.27, 0.0, -La * 0.45), n=8)
        thigh.cyl(0.27, 0.46, MID(), loc=(0, 0, 0), rot=(0, 90, 0), n=8, smooth=False)
        thigh.hull([(0.27, 0.3, 0.0), (0.27, -0.3, 0.0), (0.0, 0.0, 0.42), (-0.27, 0.3, 0.0), (-0.27, -0.3, 0.0),
                    (0.0, 0.0, -0.35)], D(), loc=(0, 0, -La), bevel=0.03)
        o_thigh = thigh.build(parent=ob_body, loc=(sx * 0.62, sy * 0.62, 0.05))

        shin = Part(f"shin_{i}")
        shin.prism(6, 0.26, 0.21, 0.0, -Lb, D(), sx=1.0, sy=1.2, bevel=0.03)
        shin.hull([(0.17, -0.2, -0.1), (0.17, 0.2, -0.1), (0.14, -0.18, -Lb + 0.1), (0.14, 0.18, -Lb + 0.1),
                   (0.27, 0.0, -0.3), (0.23, 0.0, -Lb + 0.3)], MID(), bevel=0.02)
        o_shin = shin.build(parent=o_thigh, loc=(0, 0, -La))

        knee = Part(f"knee_{i}")
        knee.cyl(0.19, 0.48, J(), loc=(0, 0, -Lk / 2), rot=(0, 90, 0), n=10)
        knee.hull([(0.17, 0.0, 0.0), (-0.17, 0.0, 0.0), (0.0, 0.21, -Lk / 2), (0.0, -0.21, -Lk / 2),
                   (0.17, 0.0, -Lk), (-0.17, 0.0, -Lk)], J(), bevel=0.015)
        knee.cyl(0.07, 0.58, LT(), loc=(0, 0, -Lk / 2), rot=(0, 90, 0), n=8)
        o_knee = knee.build(parent=o_shin, loc=(0, 0, -Lb))

        calf = Part(f"calf_{i}")
        calf.prism(6, 0.23, 0.15, 0.0, -Lc + 0.2, D(), sx=1.0, sy=1.2, bevel=0.03)
        calf.hull([(0.15, -0.18, -0.15), (0.15, 0.18, -0.15), (0.1, -0.12, -Lc + 0.4), (0.1, 0.12, -Lc + 0.4),
                   (0.23, 0.0, -0.4)], MID(), bevel=0.02)
        # стопа-клин
        calf.hull([(0.26, 0.34, -Lc), (-0.26, 0.34, -Lc), (0.26, -0.28, -Lc), (-0.26, -0.28, -Lc),
                   (0.15, 0.15, -Lc + 0.38), (-0.15, 0.15, -Lc + 0.38), (0.15, -0.15, -Lc + 0.34), (-0.15, -0.15, -Lc + 0.34)],
                  RUB(), bevel=0.02)
        o_calf = calf.build(parent=o_knee, loc=(0, 0, -Lk))
        empty(f"end_{i}", parent=o_calf, loc=(0, 0, -Lc))

        # поза покоя через IK
        update()
        hip = o_thigh.matrix_world.translation.copy()
        foot = Vector((sx * 2.8, sy * 2.6, 0.0))
        pole = Vector((sx * 0.6, sy * 0.6, 2.5))
        b_len = Lb + Lk + Lc
        knee_p = solve_leg(hip, foot, La, b_len, pole)
        n = (foot - hip).cross(pole).normalized()
        aim_bone(o_thigh, hip, knee_p, n)
        aim_bone(o_shin, knee_p, foot, n)
    return ob_body


# ============================================================ КРАБ (чаша на 4 ногах)

def crab():
    H = 1.0
    body = Part("body")
    n = 10
    top, bot = [], []
    for i in range(n):
        a = i * math.tau / n + math.pi / n
        top.append((math.cos(a) * 1.35, math.sin(a) * 1.15, 1.15))
        bot.append((math.cos(a) * 0.72, math.sin(a) * 0.62, 0.3))
    body.hull(top + bot, D(), bevel=0.05)
    # ободок и крышка
    lid = [(math.cos(i * math.tau / n + math.pi / n) * 1.22, math.sin(i * math.tau / n + math.pi / n) * 1.04, 1.22) for i in range(n)]
    body.hull(lid + [(p[0] * 0.95, p[1] * 0.95, 1.12) for p in lid], MID(), bevel=0.02)
    body.box((0.9, 0.5, 0.18), MID(), loc=(0, 0.1, 1.33), bevel=0.04)
    # лицевой модуль
    body.hull([(0.48, 0.95, 1.05), (0.48, 1.12, 0.35), (0.3, 1.25, 0.95), (0.3, 1.3, 0.45),
               (0.48, 0.7, 1.05), (0.48, 0.7, 0.35)], MID(), mirror_x=True, bevel=0.03)
    for sx in (-1, 1):
        body.hull([(0.05, 1.24, 0.9), (0.28, 1.2, 0.9), (0.05, 1.29, 0.6), (0.28, 1.23, 0.6),
                   (0.05, 1.1, 0.9), (0.28, 1.1, 0.6)], D(), loc=(sx * 0.0, 0.03, 0) if sx > 0 else (0, 0.03, 0),
                  rot=(0, 0, 0) if sx > 0 else (0, 0, 0), bevel=0.012)
    body.box((0.22, 0.1, 0.18), RUB(), loc=(0, 1.31, 0.55), bevel=0.02)
    # нижний «бочонок»
    body.prism(10, 0.45, 0.45, -0.75, 0.75, D(), rot=(0, 90, 0), bevel=0.03)
    for x in (-0.5, -0.17, 0.17, 0.5):
        body.prism(10, 0.48, 0.48, -0.05, 0.05, MID(), loc=(x, 0, 0), rot=(0, 90, 0), bevel=0.01)
    ob_body = body.build(loc=(0, 0, H))

    core = Part("eye")
    core.sphere(0.06, BLUE(), loc=(0, 0, 0))
    core.cyl(0.09, 0.04, D(), loc=(0, -0.02, 0), rot=(90, 0, 0), n=12)
    core.build(parent=ob_body, loc=(0, 1.22, 1.08))

    La, Lk, Lc = 0.78, 0.2, 1.45
    angs = [40, 140, 220, 320]
    for i, ang in enumerate(angs):
        a = math.radians(ang)
        thigh = Part(f"thigh_{i}")
        thigh.prism(6, 0.21, 0.17, 0.05, -La, D(), sx=1.0, sy=1.15, bevel=0.025)
        thigh.cyl(0.2, 0.42, MID(), rot=(0, 90, 0), n=8, smooth=False)
        o_thigh = thigh.build(parent=ob_body, loc=(math.cos(a) * 0.62, math.sin(a) * 0.5, 0.0))

        knee = Part(f"knee_{i}")
        knee.hull([(0.17, -0.17, 0.0), (-0.17, -0.17, 0.0), (0.17, 0.17, 0.0), (-0.17, 0.17, 0.0),
                   (0.14, -0.14, -Lk), (-0.14, -0.14, -Lk), (0.14, 0.14, -Lk), (-0.14, 0.14, -Lk)], J(), bevel=0.03)
        knee.cyl(0.07, 0.46, LT(), loc=(0, 0, -Lk / 2), rot=(0, 90, 0), n=10)
        o_knee = knee.build(parent=o_thigh, loc=(0, 0, -La))

        calf = Part(f"calf_{i}")
        calf.hull([(0.18, 0.2, 0.0), (-0.18, 0.2, 0.0), (0.18, -0.2, 0.0), (-0.18, -0.2, 0.0),
                   (0.15, 0.14, -0.5), (-0.15, 0.14, -0.5), (0.15, -0.24, -0.45), (-0.15, -0.24, -0.45),
                   (0.03, 0.03, -Lc), (-0.03, 0.03, -Lc), (0.0, -0.05, -Lc)], D(), bevel=0.025)
        calf.hull([(0.16, -0.2, -0.1), (-0.16, -0.2, -0.1), (0.13, -0.24, -0.42), (-0.13, -0.24, -0.42),
                   (0.1, -0.12, -0.9), (-0.1, -0.12, -0.9)], MID(), bevel=0.02)
        o_calf = calf.build(parent=o_knee, loc=(0, 0, -Lk))
        empty(f"end_{i}", parent=o_calf, loc=(0, 0, -Lc))

        update()
        hip = o_thigh.matrix_world.translation.copy()
        foot = Vector((math.cos(a) * 1.95, math.sin(a) * 1.75, 0.0))
        pole = Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, 1.5))
        knee_p = solve_leg(hip, foot, La, Lk + Lc, pole)
        nrm = (foot - hip).cross(pole).normalized()
        aim_bone(o_thigh, hip, knee_p, nrm)
        aim_bone(o_knee, knee_p, foot, nrm)
    return ob_body


# ============================================================ ШЕРШЕНЬ (2 ротора, глаз на стойке, пушка)

def rotor_dish(name, parent, loc, r_top, r_bot, depth, blades_name):
    rp = Part(name)
    rp.prism(12, r_bot, r_top, -depth / 2, depth / 2, D(), bevel=0.02)
    rp.ring(r_top, r_top - 0.06, 0.05, MID(), loc=(0, 0, depth / 2), n=24)
    rp.cyl(r_top - 0.07, 0.02, RUB(), loc=(0, 0, depth / 2 - 0.06), n=24)
    rp.cyl(0.1, 0.12, MID(), loc=(0, 0, depth / 2 - 0.02), n=12)
    for k in range(4):
        a = k * math.tau / 4 + math.pi / 4
        rp.box((0.03, r_top * 0.95, 0.02), MID(), loc=(math.cos(a) * r_top * 0.5, math.sin(a) * r_top * 0.5, depth / 2 - 0.035),
               rot=(0, 0, math.degrees(a) - 90), bevel=0.0)
    ob = rp.build(parent=parent, loc=loc)
    bl = Part(blades_name)
    for k in range(3):
        a = k * 120
        bl.box((0.08, r_top * 0.85, 0.012), LT(), loc=(0, 0, 0), rot=(12, 0, a), bevel=0.0)
        bl.box((0.08, r_top * 0.85, 0.012), LT(), loc=(0, 0, 0), rot=(12, 0, a + 180), bevel=0.0)
    bl.build(parent=ob, loc=(0, 0, depth / 2 - 0.04))
    return ob


def hornet():
    body = Part("body")
    body.hull([(0.3, 0.28, 0.0), (0.3, -0.28, 0.0), (0.26, 0.3, 0.55), (0.26, -0.25, 0.6), (0.12, 0.0, 0.7)],
              D(), mirror_x=True, bevel=0.03)
    body.hull([(0.28, 0.25, 0.0), (0.28, -0.26, 0.0), (0.24, 0.22, -0.42), (0.24, -0.24, -0.45)], MID(),
              mirror_x=True, bevel=0.03)
    for sx in (-1, 1):
        body.box((0.02, 0.18, 0.12), BLUE(), loc=(sx * 0.31, 0.05, 0.3), bevel=0.0)
        # кронштейн ротора
        body.box((0.6, 0.22, 0.16), MID(), loc=(sx * 0.55, 0.0, 0.25), bevel=0.03)
    body.cyl(0.13, 0.16, D(), loc=(0, 0, -0.5), n=10, smooth=False)
    ob_body = body.build(loc=(0, 0, 0))

    rotor_dish("rotor_0", ob_body, (-0.98, 0.0, 0.28), 0.58, 0.24, 0.36, "blades_0")
    rotor_dish("rotor_1", ob_body, (0.98, 0.0, 0.28), 0.58, 0.24, 0.36, "blades_1")

    eye = Part("eye")
    eye.bent_bar([(0, 0, 0), (-0.15, 0.12, 0.0), (-0.32, 0.3, 0.06)], 0.04, MID(), n=8)
    eye.sphere(0.16, D(), loc=(-0.42, 0.4, 0.08), scale=(1, 1, 0.85))
    eye.cyl(0.11, 0.06, GLASS(), loc=(-0.42, 0.55, 0.08), rot=(90, 0, 0), n=20)
    eye.ring(0.12, 0.09, 0.03, BLUE(), loc=(-0.42, 0.57, 0.08), rot=(90, 0, 0), n=20)
    eye.box((0.34, 0.05, 0.06), MID(), loc=(-0.42, 0.4, 0.2), bevel=0.01)
    eye.build(parent=ob_body, loc=(-0.22, 0.25, 0.15))

    gun = Part("gun")
    gun.box((0.22, 0.4, 0.22), MID(), loc=(0, 0.05, -0.12), bevel=0.03)
    gun.box((0.3, 0.55, 0.22), D(), loc=(0, 0.2, -0.32), bevel=0.03)
    for sx in (-1, 1):
        gun.cyl(0.045, 0.75, LT(), loc=(sx * 0.07, 0.75, -0.32), rot=(90, 0, 0), n=12)
        gun.cyl(0.06, 0.12, D(), loc=(sx * 0.07, 1.1, -0.32), rot=(90, 0, 0), n=12)
        gun.cyl(0.06, 0.04, D(), loc=(sx * 0.07, 0.6, -0.32), rot=(90, 0, 0), n=12)
    gun.box((0.12, 0.25, 0.12), D(), loc=(0, 0.05, -0.5), bevel=0.02)
    o_gun = gun.build(parent=ob_body, loc=(0, 0.0, -0.55))
    empty("muzzle", parent=o_gun, loc=(0, 1.2, -0.32))
    return ob_body


# ============================================================ РАКЕТЧИК (4 ротора, ракетные блоки)

def rocketeer():
    body = Part("body")
    body.hull([(0.25, 1.25, 0.25), (0.2, 1.3, 0.0), (0.45, 0.6, 0.2), (0.45, 0.6, -0.2), (0.5, -0.2, 0.25),
               (0.5, -0.2, -0.22), (0.35, -0.9, 0.3), (0.3, -0.9, -0.15), (0.2, -1.3, 0.45), (0.15, -1.25, 0.2),
               (0.0, 0.2, 0.42), (0.0, -0.6, 0.5)], D(), mirror_x=True, bevel=0.035)
    body.hull([(0.3, 0.6, 0.25), (0.35, -0.2, 0.32), (0.25, -0.8, 0.38), (0.0, 0.0, 0.47), (0.0, 0.6, 0.35),
               (0.28, 0.6, 0.18), (0.32, -0.2, 0.25)], MID(), mirror_x=True, bevel=0.02)
    for sx in (-1, 1):
        body.box((0.03, 0.14, 0.14), BLUE(), loc=(sx * 0.5, 0.0, 0.03), bevel=0.0)
        body.box((0.12, 0.45, 0.2), MID(), loc=(sx * 0.48, 0.55, -0.02), bevel=0.03)
        body.box((0.12, 0.45, 0.2), MID(), loc=(sx * 0.48, -0.55, 0.05), bevel=0.03)
    # подвес ракетных блоков
    body.box((0.9, 0.3, 0.18), MID(), loc=(0, 0.15, -0.3), bevel=0.03)
    body.cyl(0.08, 0.3, D(), loc=(0, 0.15, -0.45), n=10)
    ob_body = body.build(loc=(0, 0, 0))

    rotor_pos = [(1.6, 1.05, 0.6), (-1.6, 1.05, 0.6), (-1.55, -1.1, 0.7), (1.55, -1.1, 0.7)]
    for i, rp in enumerate(rotor_pos):
        sx = 1 if rp[0] > 0 else -1
        sy = 1 if rp[1] > 0 else -1
        # рука-трубка (часть корпуса)
        arm = Part(f"arm_{i}")
        a0 = (sx * 0.4, sy * 0.6, 0.15)
        a1 = (sx * 0.8, sy * 0.85, 0.5)
        a2 = (rp[0] - sx * 0.35, rp[1] - sy * 0.1, rp[2] - 0.05)
        arm.bent_bar([a0, a1, a2], 0.06, MID(), n=10)
        arm.cyl(0.085, 0.14, D(), loc=a1, n=10)
        arm.build(parent=ob_body)
        pod = Part(f"rotor_{i}")
        pod.prism(8, 0.42, 0.46, -0.28, 0.12, D(), bevel=0.04)
        pod.prism(8, 0.46, 0.38, 0.12, 0.3, MID(), bevel=0.03)
        pod.cyl(0.33, 0.02, RUB(), loc=(0, 0, 0.28), n=24)
        pod.prism(8, 0.16, 0.2, -0.36, -0.28, D(), bevel=0.02)
        pod.box((0.12, 0.2, 0.14), MID(), loc=(-sx * 0.42, 0, -0.06), bevel=0.02)
        o_pod = pod.build(parent=ob_body, loc=rp)
        bl = Part(f"blades_{i}")
        for k in range(4):
            bl.box((0.06, 0.6, 0.012), LT(), rot=(10, 0, k * 90), bevel=0.0)
        bl.build(parent=o_pod, loc=(0, 0, 0.26))

    for nm, sx in (("pod_l", -1), ("pod_r", 1)):
        pod = Part(nm)
        pod.box((0.4, 0.62, 0.38), D(), loc=(0, 0, 0), bevel=0.04)
        pod.box((0.42, 0.1, 0.4), MID(), loc=(0, 0.3, 0), bevel=0.02)
        for ix in (-1, 1):
            for iz in (-1, 1):
                pod.cyl(0.065, 0.06, RUB(), loc=(ix * 0.1, 0.34, iz * 0.1), rot=(90, 0, 0), n=12)
                pod.ring(0.08, 0.065, 0.04, LT(), loc=(ix * 0.1, 0.36, iz * 0.1), rot=(90, 0, 0), n=12)
        pod.box((0.12, 0.3, 0.1), MID(), loc=(-sx * 0.22, -0.05, 0.14), bevel=0.02)
        o = pod.build(parent=ob_body, loc=(sx * 0.32, 0.15, -0.6))
        empty("muzzle", parent=o, loc=(0, 0.42, 0)).name = f"muzzle_{nm[-1]}"
    return ob_body


BUILDERS = {"leaper": leaper, "crab": crab, "hornet": hornet, "rocketeer": rocketeer}

if __name__ == "__main__":
    out = sys.argv[1]
    render_dir = None
    if "--render" in sys.argv:
        render_dir = sys.argv[sys.argv.index("--render") + 1]
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1].split(",")
    os.makedirs(out, exist_ok=True)
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        reset()
        fn()
        update()
        export_glb(os.path.join(out, f"{name}.glb"))
        print("exported", name)
        if render_dir:
            import render
            render.render_scene(os.path.join(render_dir, f"{name}.png"), name)

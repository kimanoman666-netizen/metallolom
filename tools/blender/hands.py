"""Руки от первого лица: тактические перчатки + рукава куртки.
Запуск: python hands.py <папка_моделей> [--render <папка>]

Начало координат — центр рукояти, которую держит рука.
  hand_r_grip  — правая рука на пистолетной рукояти (ось рукояти = Z, ствол вперёд = +Y)
  hand_l_guard — левая рука под цевьём (ось цевья = Y)
  hand_l_grip  — левая рука на вертикальной рукояти (зеркало правой)
"""
import math
import bpy
import bmesh
import sys
import os
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
from lib import Part, mat, reset, update, export_glb, PALETTE  # noqa: E402

PALETTE["glove"] = dict(color=(0.045, 0.04, 0.035), metal=0.0, rough=0.62)
PALETTE["glove_pad"] = dict(color=(0.11, 0.11, 0.11), metal=0.1, rough=0.45)
PALETTE["sleeve"] = dict(color=(0.24, 0.23, 0.17), metal=0.0, rough=0.9)
PALETTE["strap"] = dict(color=(0.03, 0.03, 0.03), metal=0.0, rough=0.7)
PALETTE["device"] = dict(color=(0.08, 0.08, 0.09), metal=0.6, rough=0.4)


def capsule(p, a, b, r, m, n=12):
    p.rod(a, b, r, m, n=n)
    p.sphere(r, m, loc=a, seg=n)
    p.sphere(r, m, loc=b, seg=n)


def finger(p, pts, radii, m):
    for i in range(len(pts) - 1):
        capsule(p, pts[i], pts[i + 1], radii[i], m)


def organic(ob, voxel=0.0022, ratio=0.35):
    """Сплавляет капсулы в одну мягкую форму (перчатка), сглаживает и упрощает."""
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    rm = ob.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = voxel
    rm.adaptivity = 0.0
    sm = ob.modifiers.new("smooth", "SMOOTH")
    sm.iterations = 6
    sm.factor = 0.6
    dc = ob.modifiers.new("decimate", "DECIMATE")
    dc.ratio = ratio
    for md in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=md.name)
    for poly in ob.data.polygons:
        poly.use_smooth = True
    ob.select_set(False)


def sleeve(name, wrist, elbow, r0, r1, parent):
    """Рукав со складками ткани от запястья до локтя."""
    wrist = Vector(wrist)
    elbow = Vector(elbow)
    axis = elbow - wrist
    L = axis.length
    q = Vector((0, 0, 1)).rotation_difference(axis.normalized())
    bm = bmesh.new()
    rings, seg = 18, 28
    verts = []
    for i in range(rings + 1):
        t = i / rings
        row = []
        for j in range(seg):
            a = j * math.tau / seg
            r = r0 + (r1 - r0) * t
            fold = 0.0035 * math.sin(a * 3 + t * 9.0) + 0.0025 * math.sin(a * 5 - t * 14.0 + 1.3)
            fold *= 0.4 + t
            r += fold
            row.append(bm.verts.new(Vector((math.cos(a) * r, math.sin(a) * r * 0.92, t * L))))
        verts.append(row)
    for i in range(rings):
        for j in range(seg):
            k = (j + 1) % seg
            bm.faces.new((verts[i][j], verts[i][k], verts[i + 1][k], verts[i + 1][j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat("sleeve"))
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    ob.matrix_world = __import__("mathutils").Matrix.Translation(wrist) @ q.to_matrix().to_4x4()
    # манжета
    cuff = Part(name + "_cuff")
    cuff.ring(r0 + 0.006, r0 - 0.004, 0.025, mat("strap"), loc=(0, 0, 0.012), n=24)
    cuff.box((0.018, 0.012, 0.03), mat("glove_pad"), loc=(r0 + 0.004, 0, 0.012), bevel=0.003)
    c = cuff.build()
    c.parent = parent
    c.matrix_world = ob.matrix_world.copy()
    return ob


def right_grip(name="hand_r_grip", mirror=False):
    """Правая рука обхватывает вертикальную рукоять. mirror=True — левая на вертикальной рукояти."""
    G = mat("glove")
    hand = Part(name)
    s = -1.0 if mirror else 1.0
    def P(x, y, z):
        return (x * s, y, z)
    # ладонь: с правой стороны рукояти, тыльная сторона наружу (+X)
    hand.hull([P(0.028, -0.012, 0.045), P(0.05, -0.008, 0.045), P(0.03, 0.006, -0.035), P(0.052, 0.004, -0.035),
               P(0.03, -0.055, -0.06), P(0.052, -0.05, -0.058), P(0.03, -0.045, 0.02), P(0.05, -0.04, 0.02)], G, bevel=0.0)
    # указательный — на спуске
    finger(hand, [P(0.042, 0.004, 0.04), P(0.034, 0.042, 0.046), P(0.016, 0.066, 0.04), P(0.003, 0.072, 0.026)],
           [0.0095, 0.0088, 0.008], G)
    # средний, безымянный, мизинец — обхватывают рукоять
    for z, k in ((0.012, 1.0), (-0.012, 0.95), (-0.034, 0.82)):
        finger(hand, [P(0.042, 0.006, z), P(0.03, 0.036 * k, z - 0.004), P(0.002, 0.04 * k, z - 0.006), P(-0.022, 0.024 * k, z - 0.006)],
               [0.0098 * k, 0.009 * k, 0.0082 * k], G)
    # большой палец — обхватывает сзади сверху
    finger(hand, [P(0.03, -0.03, -0.005), P(0.012, -0.036, 0.028), P(-0.012, -0.026, 0.046), P(-0.024, -0.008, 0.05)],
           [0.011, 0.0095, 0.0085], G)
    # запястье
    capsule(hand, P(0.04, -0.045, -0.04), P(0.045, -0.085, -0.085), 0.03, G, n=14)
    ob = hand.build()
    organic(ob)
    # накладки на костяшки и тыльную сторону
    pad = Part(name + "_pads")
    for z in (0.04, 0.012, -0.012, -0.034):
        pad.box((0.012, 0.016, 0.016), mat("glove_pad"), loc=P(0.054, 0.006, z), bevel=0.003)
    pad.hull([P(0.05, -0.008, 0.03), P(0.058, -0.012, 0.03), P(0.052, -0.045, 0.0), P(0.06, -0.045, 0.0),
              P(0.05, -0.03, -0.04), P(0.058, -0.03, -0.04)], mat("glove_pad"), bevel=0.003)
    pad.box((0.05, 0.03, 0.012), mat("strap"), loc=P(0.046, -0.07, -0.066), rot=(45, 0, 0), bevel=0.003)
    pd = pad.build()
    pd.parent = ob
    sleeve(name + "_sleeve", P(0.046, -0.09, -0.09), P(0.09, -0.32, -0.36), 0.037, 0.05, ob)
    if not mirror:
        dev = Part(name + "_device")
        dev.box((0.035, 0.05, 0.016), mat("device"), loc=(0.088, -0.15, -0.165), rot=(45, 0, 8), bevel=0.004)
        dev.box((0.026, 0.036, 0.004), mat("glow_blue"), loc=(0.094, -0.152, -0.159), rot=(45, 0, 8), bevel=0.0)
        d = dev.build()
        d.parent = ob
    return ob


def left_guard(name="hand_l_guard"):
    """Левая рука снизу держит цевьё (ось цевья = Y)."""
    G = mat("glove")
    hand = Part(name)
    # ладонь снизу-слева
    hand.hull([(-0.035, 0.03, -0.03), (-0.045, 0.03, -0.012), (-0.03, -0.04, -0.034), (-0.045, -0.045, -0.015),
               (0.005, 0.03, -0.045), (0.005, -0.04, -0.048), (0.0, 0.03, -0.03), (0.0, -0.04, -0.034)], G, bevel=0.0)
    # пальцы оборачивают цевьё снизу направо и вверх
    for y, k in ((0.028, 1.0), (0.008, 1.0), (-0.012, 0.95), (-0.03, 0.82)):
        finger(hand, [(0.005, y, -0.044), (0.03 * k, y + 0.002, -0.036), (0.042 * k, y + 0.002, -0.012), (0.04 * k, y, 0.012)],
               [0.0098 * k, 0.009 * k, 0.0082 * k], G)
    # большой палец вдоль левой стороны
    finger(hand, [(-0.04, -0.035, -0.02), (-0.044, -0.005, 0.0), (-0.04, 0.025, 0.012), (-0.034, 0.045, 0.018)],
           [0.011, 0.0095, 0.0085], G)
    capsule(hand, (-0.03, -0.045, -0.04), (-0.05, -0.085, -0.075), 0.03, G, n=14)
    ob = hand.build()
    organic(ob)
    pad = Part(name + "_pads")
    for y in (0.028, 0.008, -0.012, -0.03):
        pad.box((0.016, 0.014, 0.012), mat("glove_pad"), loc=(0.02, y, -0.052), bevel=0.003)
    pad.box((0.045, 0.03, 0.012), mat("strap"), loc=(-0.048, -0.075, -0.07), rot=(40, 0, -30), bevel=0.003)
    pd = pad.build()
    pd.parent = ob
    sleeve(name + "_sleeve", (-0.052, -0.09, -0.08), (-0.16, -0.33, -0.3), 0.036, 0.05, ob)
    return ob


if __name__ == "__main__":
    out = sys.argv[1]
    render_dir = sys.argv[sys.argv.index("--render") + 1] if "--render" in sys.argv else None
    os.makedirs(out, exist_ok=True)
    reset()
    a = right_grip()
    b = left_guard()
    c = right_grip("hand_l_grip", mirror=True)
    update()
    export_glb(os.path.join(out, "hands.glb"))
    print("exported hands")
    if render_dir:
        import render
        a.location = (0.0, 0.0, 0.4)
        b.location = (0.0, 0.25, 0.4)
        c.location = (-0.2, 0.0, 0.4)
        # рукояти для наглядности
        g = Part("grip_vis")
        g.box((0.03, 0.045, 0.12), mat("steel_dark"), loc=(0, 0, 0.4), bevel=0.006)
        g.box((0.03, 0.045, 0.12), mat("steel_dark"), loc=(-0.2, 0, 0.4), bevel=0.006)
        g.cyl(0.03, 0.2, mat("steel_dark"), loc=(0, 0.25, 0.4), rot=(90, 0, 0), n=16)
        g.build()
        update()
        render.render_scene(os.path.join(render_dir, "hands.png"), "hands", yaw=60, pitch=12,
                            res=(1000, 700), floor=False, samples=48, dist_mul=0.8)

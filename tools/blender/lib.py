"""Библиотека hard-surface моделирования для МЕТАЛЛОЛОМА.

Модели строятся скриптами (Blender как Python-модуль `bpy`).
Оси Blender: Z — вверх, +Y — ВПЕРЁД робота/оружия (в Godot это станет -Z).
Каждая «часть» — отдельный объект с точкой вращения (origin) в суставе.
Кости ног всегда направлены вдоль локальной оси -Z.
"""
import math
import bmesh
import bpy
from mathutils import Matrix, Vector, Euler

MATS = {}

# Палитра в стиле ARC: тёмный оружейный металл, латунные суставы, синее свечение.
PALETTE = {
    "metal_dark": dict(color=(0.045, 0.047, 0.052), metal=0.75, rough=0.42),
    "metal_mid": dict(color=(0.11, 0.115, 0.125), metal=0.8, rough=0.36),
    "metal_light": dict(color=(0.42, 0.43, 0.45), metal=0.9, rough=0.3),
    "rubber": dict(color=(0.02, 0.02, 0.022), metal=0.0, rough=0.85),
    "joint": dict(color=(0.55, 0.38, 0.16), metal=0.85, rough=0.38),
    "glow_blue": dict(color=(0.05, 0.45, 1.0), metal=0.0, rough=0.3, emit=(0.1, 0.55, 1.0), strength=12.0),
    "glow_red": dict(color=(1.0, 0.1, 0.05), metal=0.0, rough=0.3, emit=(1.0, 0.12, 0.04), strength=10.0),
    "glass": dict(color=(0.01, 0.012, 0.02), metal=0.2, rough=0.08),
    # оружие
    "steel_worn": dict(color=(0.5, 0.5, 0.49), metal=0.9, rough=0.42),
    "steel_dark": dict(color=(0.13, 0.13, 0.13), metal=0.85, rough=0.45),
    "rust": dict(color=(0.32, 0.16, 0.08), metal=0.4, rough=0.75),
    "paint_white": dict(color=(0.62, 0.62, 0.6), metal=0.3, rough=0.5),
    "brass": dict(color=(0.62, 0.45, 0.2), metal=0.9, rough=0.35),
    "wood": dict(color=(0.28, 0.15, 0.07), metal=0.0, rough=0.65),
    "cable": dict(color=(0.55, 0.42, 0.25), metal=0.1, rough=0.6),
    "olive": dict(color=(0.22, 0.25, 0.15), metal=0.3, rough=0.6),
    "glow_coil": dict(color=(0.1, 0.6, 0.9), metal=0.0, rough=0.3, emit=(0.2, 0.8, 1.0), strength=6.0),
    "glow_laser": dict(color=(1.0, 0.3, 0.2), metal=0.0, rough=0.2, emit=(1.0, 0.25, 0.1), strength=6.0),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def mat(name):
    if name in MATS:
        return MATS[name]
    p = PALETTE[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*p["color"], 1.0)
    b.inputs["Metallic"].default_value = p["metal"]
    b.inputs["Roughness"].default_value = p["rough"]
    if "emit" in p:
        b.inputs["Emission Color"].default_value = (*p["emit"], 1.0)
        b.inputs["Emission Strength"].default_value = p["strength"]
    MATS[name] = m
    return m


def M(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Матрица из положения, поворота (градусы XYZ) и масштаба."""
    r = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    s = Matrix.Diagonal((*scale, 1.0))
    return Matrix.Translation(Vector(loc)) @ r @ s


class Part:
    """Набор кусков геометрии, которые станут одним объектом-частью."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []

    def _mi(self, m):
        if m not in self.mats:
            self.mats.append(m)
        return self.mats.index(m)

    def _merge(self, tmp, m, matrix, bevel=0.0, smooth=False, bevel_segments=1):
        if bevel > 0.0:
            edges = [e for e in tmp.edges if not e.is_wire]
            bmesh.ops.bevel(tmp, geom=edges, offset=bevel, offset_type="OFFSET",
                            segments=bevel_segments, profile=0.5, affect="EDGES", clamp_overlap=True)
        bmesh.ops.transform(tmp, matrix=matrix, verts=tmp.verts)
        mi = self._mi(m)
        for f in tmp.faces:
            f.material_index = mi
            f.smooth = smooth
        me = bpy.data.meshes.new("_tmp")
        tmp.to_mesh(me)
        tmp.free()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        return self

    # ---------------------------------------------------------------- примитивы

    def box(self, size, m, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.02):
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        bmesh.ops.scale(t, vec=Vector(size), verts=t.verts)
        return self._merge(t, m, M(loc, rot), bevel)

    def hull(self, pts, m, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.02, mirror_x=False):
        """Выпуклая оболочка точек — гранёная бронепанель."""
        t = bmesh.new()
        pp = list(pts)
        if mirror_x:
            pp += [(-p[0], p[1], p[2]) for p in pts]
        for p in pp:
            t.verts.new(Vector(p))
        bmesh.ops.convex_hull(t, input=t.verts)
        # удаляем вершины внутри оболочки
        loose = [v for v in t.verts if not v.link_faces]
        bmesh.ops.delete(t, geom=loose, context="VERTS")
        bmesh.ops.dissolve_limit(t, angle_limit=math.radians(1.0), verts=t.verts, edges=t.edges)
        return self._merge(t, m, M(loc, rot), bevel)

    def tbox(self, w0, d0, w1, d1, z0, z1, m, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.02, shift1=(0, 0)):
        """Усечённая пирамида: низ w0×d0 на z0, верх w1×d1 на z1."""
        pts = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                pts.append((sx * w0 / 2, sy * d0 / 2, z0))
                pts.append((sx * w1 / 2 + shift1[0], sy * d1 / 2 + shift1[1], z1))
        return self.hull(pts, m, loc, rot, bevel)

    def prism(self, n, r0, r1, z0, z1, m, loc=(0, 0, 0), rot=(0, 0, 0), bevel=0.015, sx=1.0, sy=1.0, phase=0.0):
        """Гранёная призма (n граней) вдоль Z от z0 (радиус r0) до z1 (радиус r1)."""
        pts = []
        for i in range(n):
            a = phase + i * math.tau / n
            pts.append((math.cos(a) * r0 * sx, math.sin(a) * r0 * sy, z0))
            pts.append((math.cos(a) * r1 * sx, math.sin(a) * r1 * sy, z1))
        return self.hull(pts, m, loc, rot, bevel)

    def cyl(self, r, depth, m, loc=(0, 0, 0), rot=(0, 0, 0), n=16, r2=None, bevel=0.0, smooth=True):
        t = bmesh.new()
        bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=n, radius1=r,
                              radius2=r if r2 is None else r2, depth=depth)
        return self._merge(t, m, M(loc, rot), bevel, smooth=smooth and n >= 12)

    def sphere(self, r, m, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), seg=20):
        t = bmesh.new()
        bmesh.ops.create_uvsphere(t, u_segments=seg, v_segments=max(seg // 2, 6), radius=r)
        return self._merge(t, m, M(loc, rot, scale), smooth=True)

    def ring(self, r_out, r_in, depth, m, loc=(0, 0, 0), rot=(0, 0, 0), n=24):
        """Кольцо (шайба с отверстием) вдоль Z."""
        t = bmesh.new()
        outer = []
        inner = []
        for z in (-depth / 2, depth / 2):
            o = [t.verts.new((math.cos(i * math.tau / n) * r_out, math.sin(i * math.tau / n) * r_out, z)) for i in range(n)]
            ii = [t.verts.new((math.cos(i * math.tau / n) * r_in, math.sin(i * math.tau / n) * r_in, z)) for i in range(n)]
            outer.append(o)
            inner.append(ii)
        for i in range(n):
            j = (i + 1) % n
            t.faces.new((outer[0][i], outer[0][j], outer[1][j], outer[1][i]))
            t.faces.new((inner[0][j], inner[0][i], inner[1][i], inner[1][j]))
            t.faces.new((outer[1][i], outer[1][j], inner[1][j], inner[1][i]))
            t.faces.new((outer[0][j], outer[0][i], inner[0][i], inner[0][j]))
        bmesh.ops.recalc_face_normals(t, faces=t.faces)
        return self._merge(t, m, M(loc, rot), smooth=True)

    def rod(self, a, b, r, m, n=10):
        """Цилиндр-трубка между двумя точками."""
        a = Vector(a)
        b = Vector(b)
        d = b - a
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        t = bmesh.new()
        bmesh.ops.create_cone(t, cap_ends=True, segments=n, radius1=r, radius2=r, depth=d.length)
        mtx = Matrix.Translation((a + b) / 2) @ q.to_matrix().to_4x4()
        return self._merge(t, m, mtx, smooth=True)

    def bent_bar(self, pts, r, m, n=8):
        """Изогнутая трубка по точкам (скоба рычага, ручка, шланг)."""
        for i in range(len(pts) - 1):
            self.rod(pts[i], pts[i + 1], r, m, n)
            if 0 < i:
                self.sphere(r, m, loc=pts[i], seg=n)
        return self

    # ---------------------------------------------------------------- в объект

    def build(self, parent=None, loc=(0, 0, 0), rot=(0, 0, 0)):
        me = bpy.data.meshes.new(self.name)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=0.0005)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(ob)
        if parent is not None:
            ob.parent = parent
        ob.location = loc
        ob.rotation_euler = [math.radians(a) for a in rot]
        return ob


def empty(name, parent=None, loc=(0, 0, 0)):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = 0.1
    bpy.context.collection.objects.link(ob)
    ob.parent = parent
    ob.location = loc
    return ob


def update():
    bpy.context.view_layer.update()


def aim_bone(ob, start, end, pole_n):
    """Ставит кость (меш вдоль локальной -Z) из точки start в end, в мировых координатах."""
    d = (Vector(end) - Vector(start)).normalized()
    z = -d
    x = Vector(pole_n).normalized()
    x = (x - z * x.dot(z)).normalized()
    y = z.cross(x)
    rot = Matrix((x, y, z)).transposed().to_4x4()
    ob.matrix_world = Matrix.Translation(Vector(start)) @ rot
    update()


def solve_leg(hip, foot, a, b, pole):
    """Двухзвенная IK: возвращает положение «колена»."""
    hip = Vector(hip)
    foot = Vector(foot)
    d = foot - hip
    dist = min(max(d.length, abs(a - b) + 1e-3), a + b - 1e-3)
    dn = d.normalized()
    cos_a = (a * a + dist * dist - b * b) / (2 * a * dist)
    ang = math.acos(max(-1.0, min(1.0, cos_a)))
    p = Vector(pole)
    p = (p - dn * p.dot(dn)).normalized()
    return hip + dn * math.cos(ang) * a + p * math.sin(ang) * a


def export_glb(path):
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False,
                              export_apply=True, export_yup=True, export_extras=False,
                              export_cameras=False, export_lights=False)

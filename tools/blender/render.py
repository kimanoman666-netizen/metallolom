"""Студийный рендер текущей сцены (Cycles, CPU) для превью моделей."""
import math
import bpy
from mathutils import Vector


def _bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in bpy.data.objects:
        if ob.type != "MESH":
            continue
        for c in ob.bound_box:
            w = ob.matrix_world @ Vector(c)
            lo = Vector((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
            hi = Vector((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
    return lo, hi


def render_scene(path, label="", yaw=35.0, pitch=14.0, res=(1000, 760), floor=True, samples=48, dist_mul=1.0):
    scn = bpy.context.scene
    lo, hi = _bounds()
    center = (lo + hi) / 2
    size = (hi - lo).length

    if floor:
        bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, min(lo.z, 0.0) - 0.001))
        fl = bpy.context.active_object
        m = bpy.data.materials.new("floor")
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (0.42, 0.43, 0.46, 1)
        b.inputs["Roughness"].default_value = 0.85
        fl.data.materials.append(m)

    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.42, 0.44, 0.48, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7
    scn.world = world

    def light(name, kind, loc, energy, size_l=3.0, color=(1, 1, 1)):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = color
        if kind == "AREA":
            ld.size = size_l
        o = bpy.data.objects.new(name, ld)
        bpy.context.collection.objects.link(o)
        o.location = loc
        d = center - Vector(loc)
        o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        return o

    s = max(size, 1.0)
    light("key", "AREA", center + Vector((-1.2, -1.0, 1.4)) * s, 900 * s * s / 9, size_l=s * 1.2)
    light("fill", "AREA", center + Vector((1.4, -0.6, 0.6)) * s, 350 * s * s / 9, size_l=s, color=(0.85, 0.9, 1.0))
    light("rim", "AREA", center + Vector((0.2, 1.4, 1.0)) * s, 700 * s * s / 9, size_l=s * 0.8)

    cam_d = bpy.data.cameras.new("cam")
    cam_d.lens = 50
    cam = bpy.data.objects.new("cam", cam_d)
    bpy.context.collection.objects.link(cam)
    yr = math.radians(yaw)
    pr = math.radians(pitch)
    dist = size * 1.55 * dist_mul
    # камера спереди-сбоку (робот смотрит в +Y)
    cam.location = center + Vector((math.sin(yr) * math.cos(pr), math.cos(yr) * math.cos(pr), math.sin(pr))) * dist
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam

    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = samples
    try:
        scn.cycles.use_denoising = True
        scn.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        scn.cycles.use_denoising = False
    scn.render.resolution_x, scn.render.resolution_y = res
    scn.render.film_transparent = False
    scn.view_settings.view_transform = "AgX"
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)

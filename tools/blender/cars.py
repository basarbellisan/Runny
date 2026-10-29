"""Araba modelleri Blender'da Python ile kurulur ve .glb olarak dışa aktarılır.

Kullanım (bpy modülü kurulu Python ile):
    python tools/blender/cars.py --out models/cars [--render DIR] [--only kutu]

Kurallar (oyun bunlara göre okur):
- 1 birim = 1 m. Burun +Y, yer Z = 0, araba X = 0'da ortalı.
- Tekerler ayrı objeler: wheel_FL, wheel_FR, wheel_RL, wheel_RR; orijin teker
  merkezinde, aks X boyunca. Oyun bunları süspansiyon/direksiyon düğümlerine taşır.
- Malzeme adları: Paint (gövde rengi, oyun değiştirebilir), Dark, Tire, Glass,
  Light, Tail, Hub.
"""
import argparse
import math
import os
import sys

import bpy  # önce bpy: bmesh/mathutils onunla gelir
import bmesh
from mathutils import Matrix, Vector

COLORS = {
    "Paint": ((1.0, 0.353, 0.122), 0.5, 0.0),
    "Dark": ((0.165, 0.173, 0.188), 0.85, 0.0),
    "Tire": ((0.11, 0.114, 0.125), 0.95, 0.0),
    "Glass": ((0.137, 0.145, 0.161), 0.15, 0.0),
    "Light": ((1.0, 1.0, 1.0), 0.3, 2.0),
    "Tail": ((0.847, 0.196, 0.165), 0.4, 1.5),
    "Hub": ((0.984, 0.98, 0.969), 0.5, 0.0),
}


def srgb_to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def material(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    color, rough, emit = COLORS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    lin = srgb_to_linear(color) + (1.0,)
    b.inputs["Base Color"].default_value = lin
    b.inputs["Roughness"].default_value = rough
    if emit > 0:
        b.inputs["Emission Color"].default_value = lin
        b.inputs["Emission Strength"].default_value = emit
    return m


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def new_object(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        ob.data.materials.append(material(m))
    return ob


def bevel(ob, width, segments=2, angle=30.0):
    mod = ob.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    mod.harden_normals = False
    return mod


def flat(ob):
    for p in ob.data.polygons:
        p.use_smooth = False


def extrude_profile(name, pts, half_w, taper=None, mat="Paint"):
    """Yandan görünüş (y, z) çokgenini X boyunca ±half_w kalınlıkta katı yapar.
    taper(z) -> o yükseklikte genişlik çarpanı (camlı kabinin içe eğimi)."""
    bm = bmesh.new()
    left, right = [], []
    for y, z in pts:
        k = taper(z) if taper else 1.0
        left.append(bm.verts.new((-half_w * k, y, z)))
        right.append(bm.verts.new((half_w * k, y, z)))
    n = len(pts)
    bm.faces.new(left)
    bm.faces.new(list(reversed(right)))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((left[i], left[j], right[j], right[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def arch(cy, r, z_cut, from_rear=True, steps=9):
    """Teker kemeri: z_cut çizgisinden yukarı yarım çember (arkadan öne)."""
    s = max(-1.0, min(1.0, (z_cut - 0.0) / r))
    a0 = math.asin(s)  # z_cut'ta kesişme açısı
    out = []
    for i in range(steps + 1):
        a = math.pi - a0 - (math.pi - 2 * a0) * i / steps
        out.append((cy + r * math.cos(a), r * math.sin(a)))
    return out


def box(name, size, pos, mat, bevel_w=0.0, rot=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    ob = new_object(name, bm, [mat])
    ob.location = pos
    if rot:
        ob.rotation_euler = rot
    if bevel_w > 0:
        bevel(ob, bevel_w, 1)
    flat(ob)
    return ob


def wheel(name, pos, r, w, rim_ratio=0.62, spokes=5, seg=16):
    """Lastik (yuvarlatılmış silindir) + jant (diskte kollar) + göbek. Aks X."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=w)
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
    tire = new_object(name, bm, ["Tire"])
    bevel(tire, 0.06, 2)
    flat(tire)
    # Jant: iki yanda biraz içe gömülü disk + kollar + göbek
    for side in (-1, 1):
        bm = bmesh.new()
        rr = r * rim_ratio
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=rr, radius2=rr, depth=0.03)
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
        bmesh.ops.translate(bm, verts=bm.verts, vec=(side * (w * 0.5 - 0.005), 0, 0))
        rim = new_object(name + "_rim%d" % side, bm, ["Dark"])
        rim.parent = tire
        flat(rim)
        for k in range(spokes):
            a = 2 * math.pi * k / spokes
            sp = box(name + "_spoke", (0.03, 0.07, rr * 0.92), (side * (w * 0.5 + 0.005), 0, 0), "Hub")
            sp.rotation_euler = (a, 0, 0)
            # kol göbekten dışa: kutunun ortası yarıçapın yarısında
            sp.location = (side * (w * 0.5 + 0.005), -math.sin(a) * rr * 0.46, math.cos(a) * rr * 0.46)
            sp.parent = tire
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=rr * 0.28, radius2=rr * 0.22, depth=0.05)
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(side * math.pi / 2, 3, "Y"), cent=(0, 0, 0))
        bmesh.ops.translate(bm, verts=bm.verts, vec=(side * (w * 0.5 + 0.02), 0, 0))
        cap = new_object(name + "_cap%d" % side, bm, ["Hub"])
        cap.parent = tire
        flat(cap)
    tire.location = pos
    return tire


def mirror_x(ob):
    """Objenin X'e göre aynasını kopyalar (sol/sağ parçalar)."""
    c = ob.copy()
    c.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(c)
    c.location.x = -ob.location.x
    c.rotation_euler.z = -ob.rotation_euler.z
    c.rotation_euler.y = -ob.rotation_euler.y
    return c


# ---------------------------------------------------------------- Kutu
def build_kutu():
    """İskandinav station wagon: uzun düz tavan, dik arka, köşeli far ve ızgara,
    dikey stop lambaları, tavan rayları, siyah tamponlar."""
    r, tw, track, base = 0.42, 0.30, 0.86, 1.30
    hw = 0.88
    sill = 0.30
    belt = 0.92
    # Alt gövde: arkadan öne alt çizgi (kemerlerle), ön yüz, kaput, kemer çizgisi, arka yüz
    pts = [(-2.0, sill + 0.02)]
    pts += arch(-base, r + 0.08, sill)
    pts += arch(base, r + 0.08, sill)
    pts += [(2.0, sill + 0.02), (2.04, 0.52), (2.0, 0.80), (1.92, 0.86),
            (0.95, belt), (-1.95, belt), (-2.02, 0.86)]
    body = new_object("body", extrude_profile("body", pts, hw), ["Paint"])
    bevel(body, 0.045, 2)
    flat(body)

    # Kabin: dik arka, eğik ön cam, uzun düz tavan; yukarı doğru içe eğik
    cab_pts = [(0.95, belt - 0.04), (0.18, 1.44), (-1.78, 1.46), (-1.93, belt - 0.04)]
    top_k = 0.86
    taper = lambda z: 1.0 - (1.0 - top_k) * max(0.0, (z - belt) / (1.46 - belt))
    bm = extrude_profile("cabin", cab_pts, hw - 0.06, taper)
    # Ön ve arka cam: yüz içe basık cam
    glass_faces = [f for f in bm.faces if abs(f.normal.x) < 0.7 and (f.normal.y > 0.3 or f.normal.y < -0.5)]
    bmesh.ops.inset_individual(bm, faces=glass_faces, thickness=0.07, depth=-0.012)
    for f in glass_faces:
        f.material_index = 1
    cabin = new_object("cabin", bm, ["Paint", "Glass"])
    bevel(cabin, 0.03, 2)
    flat(cabin)

    # Yan camlar: kabinin eğik yan yüzüne oturan üç cam (aralarında direkler kalır)
    def side_x(z):
        return (hw - 0.06) * taper(z) + 0.004

    def line_y(a, b, z):
        return a[0] + (b[0] - a[0]) * (z - a[1]) / (b[1] - a[1])

    z0, z1 = belt + 0.05, 1.37
    front = lambda z: line_y(cab_pts[0], cab_pts[1], z) - 0.11
    rear = lambda z: line_y(cab_pts[3], cab_pts[2], z) + 0.1
    windows = [
        [(-0.36, z0), (front(z0), z0), (front(z1), z1), (-0.36, z1)],
        [(-1.08, z0), (-0.48, z0), (-0.48, z1), (-1.08, z1)],
        [(rear(z0), z0), (-1.2, z0), (-1.2, z1), (rear(z1), z1)],
    ]
    for side in (-1, 1):
        bm = bmesh.new()
        for w in windows:
            f = bm.faces.new([bm.verts.new((side * side_x(z), y, z)) for y, z in w])
            f.normal_update()
            if f.normal.x * side < 0:
                f.normal_flip()
        new_object("side_glass", bm, ["Glass"])

    # Tavan rayları ve ayakları
    for x in (-0.55, 0.55):
        box("rail", (0.05, 1.9, 0.04), (x, -0.78, 1.53), "Dark", 0.01)
        for y in (0.05, -1.62):
            box("rail_leg", (0.06, 0.08, 0.08), (x, y, 1.49), "Dark")

    # Ön: siyah ızgara, köşeli farlar, tampon
    box("grille", (0.78, 0.04, 0.2), (0, 2.03, 0.66), "Dark", 0.01)
    for x in (-0.6, 0.6):
        box("headlight", (0.3, 0.04, 0.17), (x, 2.035, 0.66), "Light", 0.008)
        box("indicator", (0.12, 0.04, 0.08), (x * 1.32, 2.0, 0.66), "Tail")
    box("bumper_f", (1.84, 0.16, 0.16), (0, 2.08, 0.42), "Dark", 0.03)
    box("bumper_r", (1.84, 0.16, 0.16), (0, -2.08, 0.42), "Dark", 0.03)
    # Arka: dikey stop lambaları, plaka yeri
    for x in (-0.74, 0.74):
        box("taillight", (0.2, 0.04, 0.4), (x, -2.03, 0.7), "Tail", 0.01)
    box("plate", (0.5, 0.03, 0.14), (0, -2.035, 0.62), "Dark")
    # Kapı altı siyah şerit ve aynalar
    for x in (-1, 1):
        box("sill", (0.04, 2.0, 0.1), (x * (hw + 0.005), 0.0, sill + 0.08), "Dark")
        box("mirror", (0.16, 0.08, 0.1), (x * (hw + 0.04), 0.86, belt + 0.1), "Dark", 0.015)

    wheels = []
    for name, x, y in (("wheel_FL", -track, base), ("wheel_FR", track, base),
                       ("wheel_RL", -track, -base), ("wheel_RR", track, -base)):
        wheels.append(wheel(name, (x, y, r), r, tw))
    return wheels


BUILDERS = {"kutu": build_kutu}


# ---------------------------------------------------------------- çıktı
def join_body():
    """Teker dışındaki her şeyi tek "body" objesinde birleştirir (az çizim çağrısı)."""
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            bpy.context.view_layer.objects.active = ob
            ob.select_set(True)
            for m in list(ob.modifiers):
                bpy.ops.object.modifier_apply(modifier=m.name)
            ob.select_set(False)
    parts = [o for o in bpy.context.scene.objects
             if o.type == "MESH" and not o.name.startswith("wheel_") and o.parent is None]
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    body = [o for o in parts if o.name == "body"][0]
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    # Tekerin parçaları tekerle birleşir
    for w in [o for o in bpy.context.scene.objects if o.name.startswith("wheel_") and o.parent is None]:
        bpy.ops.object.select_all(action="DESELECT")
        kids = list(w.children)
        for k in kids:
            mw = k.matrix_world.copy()
            k.parent = None
            k.matrix_world = mw
            k.select_set(True)
        w.select_set(True)
        bpy.context.view_layer.objects.active = w
        bpy.ops.object.join()


def triangles():
    n = 0
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            for p in ob.data.polygons:
                n += len(p.vertices) - 2
    return n


def export(path):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True,
                              export_apply=True, export_animations=False, export_cameras=False,
                              export_lights=False)


def render(dirpath, name):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = srgb_to_linear((0.949, 0.941, 0.922)) + (1,)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    scene.world = world
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=30)
    floor = new_object("floor", bm, [])
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = srgb_to_linear((0.165, 0.173, 0.188)) + (1,)
    floor.data.materials.append(fm)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(40), math.radians(-20), math.radians(-35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    views = {"on": (6.2, 6.0, 2.6), "yan": (8.5, 0.0, 1.4), "arka": (-5.5, -6.5, 3.0), "ust": (4.0, 2.0, 9.0)}
    for view, loc in views.items():
        cam.location = loc
        d = Vector((0, 0, 0.75)) - Vector(loc)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(dirpath, "%s_%s.png" % (name, view))
        bpy.ops.render.render(write_still=True)
    floor.select_set(True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="models/cars")
    ap.add_argument("--render", default="")
    ap.add_argument("--only", default="")
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    for name, build in BUILDERS.items():
        if a.only and name != a.only:
            continue
        clear_scene()
        build()
        join_body()
        print("%s: %d üçgen" % (name, triangles()))
        export(os.path.join(a.out, name + ".glb"))
        if a.render:
            os.makedirs(a.render, exist_ok=True)
            render(a.render, name)


if __name__ == "__main__":
    main()

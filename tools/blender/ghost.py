"""Hayalet modeli (alt katmanda kayaların yerine): Blender'da Python ile kurulur, .glb olarak çıkar.

Tasarım (kullanıcının yandan / tepeden çizimi): düz kenarlı silindir gövde, üstte yarım küre
kubbe, altta dalgalı etek; kubbenin tepesinde koyu yuvarlak yüz diski (tepeden bakınca çapın
%63'ü), içinde iki beyaz dikey hap göz. Oyunda başı önde, ekseni yataydan 20° yukarı eğik
bize doğru uçar: oyuncu onu tepeden görünüşüyle (yüzüyle) görür.

Kullanım (bpy modülü kurulu Python ile):
    python3.11 tools/blender/ghost.py --out models/ghosts [--render DIR]

Kurallar: 1 birim = 1 m, eksen +Z (tepe), orijin gövdenin ortasında. Tek obje "Ghost", malzemeler
Body (örtü; oyun yarı saydam hayalet gölgelendiricisiyle değiştirir), Face (koyu yüz), Eye.
UV: u = çevre (0.5 ön/üst taraf, dikiş arkada), v = örtü boyunca (0 etek ucu, 1 tepe): oyundaki
gölgelendirici etek dalgasını v'ye göre yapar.
"""
import argparse
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

R = 1.6              # gövde yarıçapı
CYL = 2.8            # silindir boyu (etek ucundan kubbeye)
HEM_WAVES = 8        # etek ucunda çevre boyunca dalga
HEM_AMP = 0.11       # etek dalgasının genliği
FACE = 0.63          # yüz diskinin yarıçapı / gövde yarıçapı (tepeden)
EYE_X = 0.16         # gözlerin merkezden uzaklığı (R kesri)
EYE_W = 0.135        # göz genişliği (R kesri)
EYE_H = 0.27         # göz boyu (R kesri)
SEG = 96             # çevre bölümü (HEM_WAVES'e bölünür)

COLORS = {
    "Body": ((0.97, 0.96, 1.0), 0.6, 0.0),
    "Face": ((0.122, 0.118, 0.11), 0.5, 0.0),
    "Eye": ((1.0, 1.0, 1.0), 0.4, 0.4),
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


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    face_phi = math.asin(FACE)  # yüz diskinin kenarı: kutuptan açı
    # Satırlar: (z veya kutup açısı, v). Silindir etekten kubbeye; kubbe ekvatordan kutba,
    # yüz diskinin kenarında tam bir satır (malzeme sınırı düzgün olsun)
    rows = []
    cyl_rows = 18
    for j in range(cyl_rows + 1):
        rows.append(("cyl", CYL * j / cyl_rows))
    dome_a = [math.pi / 2 - (math.pi / 2 - face_phi) * k / 10 for k in range(1, 11)]
    dome_b = [face_phi * (1 - k / 8) for k in range(1, 8)]
    for phi in dome_a + dome_b:
        rows.append(("dome", phi))
    # Örtü boyunca uzunluk (v için)
    pts = []
    for kind, val in rows:
        if kind == "cyl":
            pts.append((R, val))
        else:
            pts.append((R * math.sin(val), CYL + R * math.cos(val)))
    pts.append((0.0, CYL + R))
    lens = [0.0]
    for i in range(1, len(pts)):
        lens.append(lens[-1] + math.dist(pts[i - 1], pts[i]))
    total = lens[-1]

    grid = []
    for j, (kind, val) in enumerate(rows):
        ring = []
        for i in range(SEG):
            th = 2 * math.pi * i / SEG - math.pi / 2  # i = 0: -Y (dikiş arkada / altta)
            r, z = pts[j]
            if kind == "cyl":
                # Etek ucu dalgalı; dalga birkaç satırda söner (yanlar düz)
                fade = max(0.0, 1.0 - val / 0.35)
                z += HEM_AMP * math.sin(HEM_WAVES * th) * fade
            ring.append(bm.verts.new((r * math.cos(th), r * math.sin(th), z)))
        grid.append(ring)
    pole = bm.verts.new((0.0, 0.0, CYL + R))
    bm.verts.ensure_lookup_table()

    def phi_of(row):
        kind, val = rows[row]
        return math.pi / 2 if kind == "cyl" else val

    for j in range(len(grid) - 1):
        for i in range(SEG):
            i2 = (i + 1) % SEG
            f = bm.faces.new((grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i]))
            f.material_index = 1 if phi_of(j + 1) <= face_phi + 1e-6 else 0
            for loop, (ii, jj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                loop[uv].uv = (ii / SEG, lens[jj] / total)
    for i in range(SEG):
        i2 = (i + 1) % SEG
        f = bm.faces.new((grid[-1][i], grid[-1][i2], pole))
        f.material_index = 1
        for loop, (u, v) in zip(f.loops, ((i / SEG, lens[-2] / total), ((i + 1) / SEG, lens[-2] / total),
                                          ((i + 0.5) / SEG, 1.0))):
            loop[uv].uv = (u, v)

    # Gözler: tepeden bakınca dikey hap (uzun ekseni Y), kubbenin yüzeyine oturur, biraz önde
    for side in (-1.0, 1.0):
        cx = side * EYE_X * R
        hw = EYE_W * R / 2
        hh = EYE_H * R / 2
        outline = []
        n = 40
        for k in range(n):
            a = 2 * math.pi * k / n
            # Hap: yarım daire uçlu dikdörtgen
            x = hw * math.cos(a)
            y = (hh - hw) * (1 if math.sin(a) >= 0 else -1) + hw * math.sin(a)
            outline.append((x, y))
        rings_e = []
        for s in (0.34, 0.67, 1.0):
            rings_e.append([bm.verts.new(on_dome(cx + x * s, y * s)) for x, y in outline])
        center = bm.verts.new(on_dome(cx, 0.0))
        for k in range(n):
            k2 = (k + 1) % n
            f = bm.faces.new((center, rings_e[0][k], rings_e[0][k2]))
            f.material_index = 2
            for a in range(2):
                f = bm.faces.new((rings_e[a][k], rings_e[a + 1][k], rings_e[a + 1][k2], rings_e[a][k2]))
                f.material_index = 2
        for f in bm.faces:
            if f.material_index == 2:
                for loop in f.loops:
                    loop[uv].uv = (0.5, 1.0)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Orijin gövdenin ortası
    mid = (CYL + R) / 2
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, -mid))
    me = bpy.data.meshes.new("Ghost")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new("Ghost", me)
    bpy.context.scene.collection.objects.link(ob)
    for name in ("Body", "Face", "Eye"):
        me.materials.append(material(name))
    return ob


def on_dome(x, y, lift=0.012):
    """Kubbe yüzeyinde (tepeden x, y) nokta, yüzeyden lift kadar dışarıda."""
    rr = R + lift
    z = math.sqrt(max(rr * rr - x * x - y * y, 0.0))
    return (x, y, CYL + z)


def render(dirpath, ob):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    scene.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.data.angle = math.radians(20)
    sun.rotation_euler = (math.radians(35), math.radians(-20), math.radians(-35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam

    def shot(name, loc, target, ortho=None, size=(600, 600), bg_col=(1, 1, 1), strength=1.0):
        bg.inputs[0].default_value = srgb_to_linear(bg_col) + (1,)
        bg.inputs[1].default_value = strength
        cam.data.type = "ORTHO" if ortho else "PERSP"
        if ortho:
            cam.data.ortho_scale = ortho
        else:
            cam.data.lens = 50
        cam.location = loc
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x, scene.render.resolution_y = size
        scene.render.filepath = os.path.join(dirpath, "ghost_%s.png" % name)
        bpy.ops.render.render(write_still=True)

    # Çizimdeki görünüşler: yandan ve tepeden (dik)
    grey = (0.86, 0.85, 0.84)
    shot("yandan", (0, -20, 0), (0, 0, 0), ortho=6.5, bg_col=grey)
    shot("tepeden", (0, 0, 20), (0, 0, 0), ortho=6.5, bg_col=grey)
    # Uçuş duruşu: ekseni yataydan 20° yukarı, başı bize (kameraya) doğru; mercan ortam
    ob.rotation_euler = (math.radians(70), 0, 0)  # +Z ekseni -Y'ye (kameraya) yatar
    coral = (0.941, 0.537, 0.463)
    shot("ucus_karsidan", (0, -16, 3.0), (0, 0, 0.3), size=(600, 600), bg_col=coral, strength=1.2)
    shot("ucus_capraz", (8, -13, 4.0), (0, 0, 0), size=(600, 600), bg_col=coral, strength=1.2)
    shot("ucus_yandan", (16, 0, 0.5), (0, 0, 0), size=(600, 600), bg_col=coral, strength=1.2)
    ob.rotation_euler = (0, 0, 0)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="models/ghosts")
    ap.add_argument("--render", default="")
    a = ap.parse_args(argv)
    ob = build()
    os.makedirs(a.out, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(a.out, "ghost.glb"), export_format="GLB",
                              use_selection=True, export_yup=True)
    print("yazıldı", os.path.join(a.out, "ghost.glb"))
    if a.render:
        os.makedirs(a.render, exist_ok=True)
        render(a.render, ob)


if __name__ == "__main__":
    main()

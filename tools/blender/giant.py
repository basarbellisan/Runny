"""Dev (boşlukta duran uzun dekor blokların yerine): Blender'da Python ile kurulur, .glb olarak çıkar.

Tasarım (kullanıcının önden çizimi): düz üstlü, öne-arkaya gövdeden kalın baş ve iki yatay göz
yarığı; uzun gövde ve altında ortada açık gri oluk; omuzdan dışa açılan uzun kollar, kolla gövde
arasında açık gri üçgen. Çizim koordinatları (piksel) doğrudan kullanılır: 1128 px = 10 m (baş tepesinden
çizimdeki gövde dibine). Gövde çizimdeki dipten 5 m daha aşağı uzar: oyunda bu kısım aşağıya doğru erir.

Kullanım (bpy modülü kurulu Python ile):
    python3.11 tools/blender/giant.py --out models/giants [--render DIR]

Kurallar: 1 birim = 1 m, +Z yukarı, ön yüz -Y (oyunda +Z: bize bakar), orijin tabanın ortasında
(uzatılmış gövdenin dibi z = 0; çizimdeki gövde dibi z = 5, baş tepesi z = 15). Tek obje "Giant"; malzemeler Main (gövde rengi), Accent (açık ton: oluk,
üçgenler), Slot (göz yarıklarının içi). Oyun renkleri malzeme adına göre verir.
"""
import argparse
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

PX = 10.0 / 1128.0      # çizimin pikseli (m): başın tepesinden çizimdeki gövde dibine 10 m
CX = 406.5              # gövde ortası (px)
LEG = 564.0             # gövde (bacaklar) çizimdeki dipten bu kadar aşağı uzar (px, 5 m): oyunda erir
BOTTOM = 1236.0 + LEG   # en alt nokta: uzatılmış gövdenin dibi (px)

# Kalınlıklar (m, ön-arka): gövde, baş (gövdeden belirgin kalın), kollar, üçgenler, kanatçıklar;
# oyuk derinliği
D_BODY = 1.3
D_HEAD = 2.2
D_ARM = 0.8
D_GUSSET = 0.5
D_CUT = 0.12

COLORS = {
    "Main": ((0.95, 0.95, 0.94), 0.8),
    "Accent": ((0.84, 0.84, 0.83), 0.8),
    "Slot": ((0.16, 0.16, 0.17), 0.8),
}


def srgb_to_linear(c):
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def material(name):
    m = bpy.data.materials.get(name)
    if m:
        return m
    color, rough = COLORS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb_to_linear(color) + (1.0,)
    b.inputs["Roughness"].default_value = rough
    return m


def P(x, y):
    """Çizim pikseli -> (x, z) metre"""
    return ((x - CX) * PX, (BOTTOM - y) * PX)


def prism(name, pts_px, depth, mat, y0=0.0):
    """Önden çizilmiş çokgeni (piksel) ön-arka yönde depth kalınlığında katı yapar (y0 merkez)."""
    bm = bmesh.new()
    pts = [P(*p) for p in pts_px]
    # Saat yönünün tersine (önden bakınca dışa bakan yüz) sırala
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    if area < 0:
        pts = pts[::-1]
    front = [bm.verts.new((x, y0 - depth / 2, z)) for x, z in pts]
    face = bm.faces.new(front)
    face.normal_update()
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    verts = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, depth, 0), verts=verts)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(material(mat))
    bpy.context.scene.collection.objects.link(ob)
    return ob


def cut(target, pts_px, depth, mat, thick=D_BODY):
    """Hedefin (ön-arka kalınlığı thick) ön yüzüne depth derinliğinde oyuk açar; oyuğun içi mat malzemesinde."""
    c = prism("cut", pts_px, depth * 2.0, mat, y0=-thick / 2)
    target.data.materials.append(material(mat))
    mod = target.modifiers.new("cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.object = c
    mod.material_mode = "TRANSFER"
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(c)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    parts = []
    # Baş: düz üst kenarlı blok (çizimdeki dişlerin dibine kadar)
    head = [(258, 375), (555, 375), (555, 108), (258, 108)]
    h = prism("head", head, D_HEAD, "Main")
    cut(h, [(331, 181), (482, 181), (482, 211), (331, 211)], D_CUT, "Slot", D_HEAD)
    cut(h, [(331, 248), (482, 248), (482, 278), (331, 278)], D_CUT, "Slot", D_HEAD)
    parts.append(h)
    # Gövde ve ortadaki oluk
    b = prism("body", [(297, 375), (516, 375), (516, BOTTOM), (297, BOTTOM)], D_BODY, "Main")
    cut(b, [(382, 753), (431, 753), (431, BOTTOM + 4), (382, BOTTOM + 4)], D_CUT, "Accent")
    parts.append(b)
    # Kollar (omuzdan dışa açılır) ve kolla gövde arasındaki üçgenler
    parts.append(prism("arm_l", [(206, 375), (297, 375), (138, 920), (57, 897)], D_ARM, "Main"))
    parts.append(prism("arm_r", [(516, 375), (607, 375), (756, 897), (674, 920)], D_ARM, "Main"))
    parts.append(prism("gus_l", [(297, 375), (237, 578), (297, 668)], D_GUSSET, "Accent"))
    parts.append(prism("gus_r", [(516, 375), (576, 578), (516, 668)], D_GUSSET, "Accent"))
    # Tek obje
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "Giant"
    ob.data.name = "Giant"
    # Aynı adlı malzemeleri birleştir (her parça kendi kopyasını eklemişti)
    seen = {}
    for i, slot in enumerate(ob.material_slots):
        seen.setdefault(slot.material.name, i)
    remap = {i: seen[s.material.name] for i, s in enumerate(ob.material_slots)}
    for poly in ob.data.polygons:
        poly.material_index = remap[poly.material_index]
    bpy.ops.object.material_slot_remove_unused()
    # Düz yüzler: her yüz tek renk (düz dünya)
    for poly in ob.data.polygons:
        poly.use_smooth = False
    return ob


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
    sun.rotation_euler = (math.radians(40), math.radians(-25), math.radians(-30))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam

    def shot(name, loc, target, ortho=None, size=(700, 1000)):
        bg.inputs[0].default_value = srgb_to_linear((0.74, 0.73, 0.65)) + (1,)
        bg.inputs[1].default_value = 1.0
        cam.data.type = "ORTHO" if ortho else "PERSP"
        if ortho:
            cam.data.ortho_scale = ortho
        else:
            cam.data.lens = 50
        cam.location = loc
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.render.resolution_x, scene.render.resolution_y = size
        scene.render.filepath = os.path.join(dirpath, "giant_%s.png" % name)
        bpy.ops.render.render(write_still=True)

    shot("onden", (0, -30, 7.5), (0, 0, 7.5), ortho=16)
    shot("capraz", (14, -28, 9), (0, 0, 7.5))
    shot("yandan", (30, 0, 7.5), (0, 0, 7.5), ortho=16)
    shot("alttan", (10, -26, -6), (0, 0, 7.5))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="models/giants")
    ap.add_argument("--render", default="")
    a = ap.parse_args(argv)
    ob = build()
    os.makedirs(a.out, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(a.out, "giant.glb"), export_format="GLB",
                              use_selection=True, export_yup=True)
    print("yazıldı", os.path.join(a.out, "giant.glb"))
    if a.render:
        os.makedirs(a.render, exist_ok=True)
        render(a.render, ob)


if __name__ == "__main__":
    main()

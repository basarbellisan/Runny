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
    "Light": ((1.0, 1.0, 1.0), 0.3, 0.6),
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


# ---------------------------------------------------------------- Dragster
def loft(name, stations, mat="Paint", cap=True):
    """Kesitlerden gövde: her kesit (y, alt yarı genişlik, üst yarı genişlik, z alt, z üst)
    dikdörtgen/yamuk; ardışık kesitler düz yüzlerle bağlanır (köşeli, yontulmuş görünüm)."""
    bm = bmesh.new()
    rings = []
    for y, hb, ht, zb, zt in stations:
        rings.append([bm.verts.new((-hb, y, zb)), bm.verts.new((hb, y, zb)),
                      bm.verts.new((ht, y, zt)), bm.verts.new((-ht, y, zt))])
    for a, b in zip(rings, rings[1:]):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap:
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[-1])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_object(name, bm, [mat])
    flat(ob)
    return ob


def poly_wheel(name, pos, r, w, seg=8, hub_ratio=0.56):
    """Sekizgen lastik (kenarları pahlı) ve iki yanda düz beyaz göbek diski."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=w)
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
    # Sekizgenin bir kenarı yere otursun
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / seg, 3, "X"), cent=(0, 0, 0))
    tire = new_object(name, bm, ["Tire"])
    bevel(tire, r * 0.13, 1)
    flat(tire)
    for side in (-1, 1):
        bm = bmesh.new()
        hr = r * hub_ratio
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=hr, radius2=hr, depth=0.02)
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / seg, 3, "X"), cent=(0, 0, 0))
        bmesh.ops.translate(bm, verts=bm.verts, vec=(side * (w * 0.5 + 0.005), 0, 0))
        hub = new_object(name + "_hub%d" % side, bm, ["Hub"])
        hub.parent = tire
        flat(hub)
    tire.location = pos
    return tire


def build_dragster_foto():
    """(İlk deneme, fotoğraftan; yerine Figma çiziminden yapılan build_dragster geldi.)
    Dragster: uzun dar burun, kabine doğru yontularak genişleyen gövde, kabinin
    önünde üç parçalı koyu hava girişi, öne taşan düz tavan, arkada sivri kuyruk,
    sekizgen iri tekerler (öndekiler buruna çubuklarla bağlı)."""
    rf, wf, rr, wr = 0.45, 0.36, 0.54, 0.48
    yf, yr = 1.62, -1.38
    xf, xr = 0.78, 0.95
    # Gövde: burun (sabit dar), yontulu genişleme, arka gövde (alt kenarı içe çekik)
    loft("body", [
        (2.02, 0.29, 0.29, 0.47, 0.77),
        (0.55, 0.29, 0.29, 0.46, 0.86),
        (0.05, 0.34, 0.52, 0.45, 0.93),
        (-0.45, 0.38, 0.62, 0.45, 0.97),
        (-1.35, 0.40, 0.64, 0.47, 0.99),
        (-1.75, 0.34, 0.56, 0.52, 0.97),
    ])
    # Kabin: eğik ön cam, düz tavan, arkaya inen sırt
    cab = loft("cabin", [
        (-0.10, 0.50, 0.50, 0.91, 0.93),
        (-0.40, 0.52, 0.48, 0.93, 1.34),
        (-1.00, 0.56, 0.52, 0.95, 1.36),
        (-1.55, 0.56, 0.54, 0.96, 1.02),
    ])
    # Camlar: ön cam ve yan camlar (kabin yüzlerine oturan koyu paneller)
    bm = bmesh.new()
    def quad(pts):
        f = bm.faces.new([bm.verts.new(p) for p in pts])
        return f
    k = 0.92  # cam, kabin yüzünün içinde kalsın
    quad([(-0.46 * k, -0.13, 0.96), (0.46 * k, -0.13, 0.96), (0.44 * k, -0.38, 1.30), (-0.44 * k, -0.38, 1.30)])
    for sx in (-1, 1):
        pts = [(sx * 0.51, -0.18, 0.98), (sx * 0.54, -0.95, 0.99), (sx * 0.52, -0.95, 1.30), (sx * 0.49, -0.44, 1.30)]
        f = quad([(x + sx * 0.012, y, z) for x, y, z in pts])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        c = f.calc_center_median()
        if (abs(c.x) > 0.3 and f.normal.x * c.x < 0) or (abs(c.x) <= 0.3 and f.normal.y < 0):
            f.normal_flip()
    g = new_object("glass", bm, ["Glass"])
    flat(g)
    # Tavan: öne taşan düz plaka (siperlik)
    loft("roof", [
        (-0.14, 0.48, 0.48, 1.34, 1.42),
        (-1.10, 0.53, 0.53, 1.34, 1.42),
    ])
    # Sivri kuyruk: arka köşelerden yukarı-geri kalkan kanatçıklar
    for sx in (-1, 1):
        bm = bmesh.new()
        v = [bm.verts.new(p) for p in [
            (sx * 0.40, -1.05, 0.96), (sx * 0.62, -1.05, 0.96), (sx * 0.56, -1.75, 0.94), (sx * 0.38, -1.75, 0.94),
            (sx * 0.50, -1.80, 1.36)]]
        bm.faces.new((v[0], v[1], v[2], v[3]))
        for a, b in ((0, 1), (1, 2), (2, 3), (3, 0)):
            bm.faces.new((v[a], v[b], v[4]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        fin = new_object("fin", bm, ["Paint"])
        flat(fin)
    # Hava girişi (blower): alçak taban + üç koyu blok, öndeki basamak
    box("blower_base", (0.46, 0.42, 0.06), (0, 0.32, 0.87), "Dark")
    for i, x in enumerate((-0.15, 0.0, 0.15)):
        h = (0.36, 0.32, 0.28)[i]
        box("blower", (0.12, 0.26, h), (x, 0.26, 0.9 + h / 2), "Dark")
    box("blower_step", (0.40, 0.12, 0.08), (0, 0.50, 0.94), "Dark")
    # Farlar
    for x in (-0.13, 0.13):
        box("headlight", (0.15, 0.03, 0.13), (x, 2.025, 0.58), "Light")
    # Ön aks çubukları (iki), arka aks göbeği
    for sx in (-1, 1):
        for dy in (-0.07, 0.07):
            box("rod", ((xf - wf / 2) - 0.28, 0.05, 0.05), (sx * (0.28 + (xf - wf / 2 - 0.28) / 2), yf + dy, rf), "Dark")
        box("stub", (xr - wr / 2 - 0.6, 0.16, 0.16), (sx * (0.6 + (xr - wr / 2 - 0.6) / 2), yr, rr), "Dark")
    for name, x, y, r, w in (("wheel_FL", -xf, yf, rf, wf), ("wheel_FR", xf, yf, rf, wf),
                             ("wheel_RL", -xr, yr, rr, wr), ("wheel_RR", xr, yr, rr, wr)):
        poly_wheel(name, (x, y, r), r, w)
    stretch_y(1.18)


# Figma "RUNNY / Araba 01" çizimi (yan, arka, ön görünüş; aynı ölçek). Ölçüler çizimin
# piksel koordinatlarıdır: yan görünüşte x arabanın boyu (burun solda, x=147), y aşağı
# (yer y=334); ön/arka görünüşte x yarı genişlik (orta çizgiden uzaklık).
DS = 0.0125          # metre / piksel (toplam genişlik ~2.3 m, boy ~3.7 m)
D_MID = 296.0        # yan görünüşte arabanın ortası


def dp(x, y):
    """Yan görünüş pikseli -> (Y, Z) metre."""
    return (D_MID - x) * DS, (334.0 - y) * DS


def build_dragster():
    """Dragster (Figma çiziminden): uzun dar burun; geniş arka gövdenin eğik ön yüzü
    burunla çapraz bir çizgide birleşir; kabinin önünde üç hava girişi; öne taşan,
    öne doğru daralan tavan; yan, ön ve arka camlar; kalın arka tekerler."""
    w = lambda px: px * DS

    def prism(name, pts, hw_of_y, mat="Paint"):
        bm = bmesh.new()
        left, right = [], []
        for x, y in pts:
            Y, Z = dp(x, y)
            hw = w(hw_of_y(y))
            left.append(bm.verts.new((-hw, Y, Z)))
            right.append(bm.verts.new((hw, Y, Z)))
        n = len(pts)
        bm.faces.new(left)
        bm.faces.new(list(reversed(right)))
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((left[i], left[j], right[j], right[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        ob = new_object(name, bm, [mat])
        flat(ob)
        return ob

    # Burun: önden 79 px geniş, ön yüzü hafif geriye yatık
    prism("nose", [(147, 283.55), (323.5, 270), (420, 270), (420, 313.11), (155.36, 313.11)], lambda y: 39.5)

    # Geniş arka gövde: ön yüzü yan görünüşteki çapraz çizgi; üst kenarları pahlı
    # (önden görünüşteki küçük üçgenler), alta doğru hafif daralır
    def body_hw(y):
        return 60.3 - (271 - y) * 0.833 if y < 271 else 60.3 - (y - 271) * 0.1395
    prism("deck", [(323.5, 270), (381, 261.6), (436, 261.6), (434.4, 271), (325.5, 271)], body_hw)
    prism("body", [(325.5, 271), (434.4, 271), (430.4, 295), (445, 297.8), (445, 313.11), (411.6, 313.11)], body_hw)

    # Kabin: ön cam eğik, yanlar arkaya doğru genişler, arka direk eğimle güverteye iner
    def st(x, hb, ht, zb, zt):
        Y, Zb = dp(x, zb)
        _, Zt = dp(x, zt)
        return (Y, w(hb), w(ht), Zb, Zt)
    cab = [st(322.5, 39, 39, 273, 271), st(330.7, 41, 37.5, 271.5, 251.1), st(383, 53.5, 46, 263.5, 251.1),
           st(404.6, 53.75, 42.1, 263.5, 240.5), st(415.8, 53.75, 53, 264, 261.6)]
    loft("cabin", cab)
    # Tavan: öne taşan siperlik, plan görünüşte öne doğru daralır
    bm = bmesh.new()
    def rv(x, y, hw):
        Y, Z = dp(x, y)
        return [bm.verts.new((-w(hw), Y, Z)), bm.verts.new((w(hw), Y, Z))]
    tf, tr = rv(325.3, 244.2, 33.5), rv(404.6, 240, 42.1)
    bf, br = rv(321.8, 251.1, 35.5), rv(404.6, 251.1, 42.1)
    for q in ((tf[0], tf[1], tr[1], tr[0]), (bf[0], br[0], br[1], bf[1]), (tf[0], bf[0], bf[1], tf[1]),
              (tr[0], tr[1], br[1], br[0]), (tf[0], tr[0], br[0], bf[0]), (tf[1], bf[1], br[1], tr[1])):
        bm.faces.new(q)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    roof = new_object("roof", bm, ["Paint"])
    flat(roof)

    # Camlar (kabin yüzeylerinin biraz dışında koyu paneller)
    bm = bmesh.new()

    def glass(pts):
        f = bm.faces.new([bm.verts.new(p) for p in pts])
        f.normal_update()
        return f

    def cab_side(x, y, side):
        # Kabinin S1-S2 yan yüzü üstünde nokta (çift doğrusal), biraz dışarı
        u = (x - 330.7) / (383 - 330.7)
        zb = 271.5 + u * (263.5 - 271.5)
        v = (zb - y) / (zb - 251.1)
        hb = 41 + u * (53.5 - 41)
        ht = 37.5 + u * (46 - 37.5)
        Y, Z = dp(x, y)
        return (side * (w(hb + (ht - hb) * v) + 0.012), Y, Z)

    for side in (-1, 1):
        f = glass([cab_side(337.0, 252.6, side), cab_side(381, 252.6, side),
                   cab_side(381, 262.8, side), cab_side(330.6, 269.6, side)])
        if f.normal.x * side < 0:
            f.normal_flip()

    def on_line(hw, y, a, b, push):
        # (a, b): yan görünüşte yüzeyin iki ucu (x, y); push: yüzeyden dışarı (m, +Y ön)
        x = a[0] + (y - a[1]) / (b[1] - a[1]) * (b[0] - a[0])
        Y, Z = dp(x, y)
        return (w(hw), Y + push, Z)

    def mirrored(pts):
        # Sağ yarının noktalarından simetrik dörtgen (sol alt, sağ alt, sağ üst, sol üst)
        (x0, y0, z0), (x1, y1, z1) = pts
        return [(-x0, y0, z0), (x0, y0, z0), (x1, y1, z1), (-x1, y1, z1)]

    # Ön cam: kabinin eğik ön yüzünde (önden görünüşte 35-38.5 px yarı genişlik)
    ws_a, ws_b = (322.5, 271), (330.7, 251.1)
    f = glass(mirrored([on_line(38.5, 270, ws_a, ws_b, 0.006), on_line(35.3, 252, ws_a, ws_b, 0.006)]))
    if f.normal.y < 0:
        f.normal_flip()
    # Arka cam: arka direkte ince yarık (arka görünüş y 247-255)
    rw_a, rw_b = (404.6, 240.5), (415.8, 261.6)
    f = glass(mirrored([on_line(41.6, 255, rw_a, rw_b, -0.006), on_line(38.0, 247, rw_a, rw_b, -0.006)]))
    if f.normal.y > 0:
        f.normal_flip()
    g = new_object("glass", bm, ["Glass"])
    flat(g)

    # Hava girişleri: yan görünüşte art arda üç kule; çizimdekinden %20 büyük
    # (aralarındaki mesafe de büyür, tabanları kaportada aynı yükseklikte kalır)
    k = 1.2
    for xc in (254.69, 267.46, 280.22):
        xc = 267.46 + (xc - 267.46) * k
        Y, Z = dp(xc, 279.69 - 16.71 * k / 2)
        box("blower", (w(9.28 * k), w(9.28 * k), w(16.71 * k)), (0, Y, Z), "Dark")

    # Farlar: burnun eğik ön yüzünde siyah. Arkada stop lambası yok (oradan yeşil iz çıkar).
    tilt_f = math.atan2(155.36 - 147, 313.11 - 283.55)
    for x in (-15.9, 15.9):
        Y, Z = dp(151.2 - 0.6, 298.5)
        box("headlight", (w(18.46), 0.02, w(11)), (w(x), Y, Z), "Dark", rot=(-tilt_f, 0, 0))

    # Ön aks çubukları (burundan tekere), arka aks (boydan boya)
    yf, _ = dp(203.94, 0)
    yr, _ = dp(393.49, 0)
    rf, rr = w(29.94), w(33.42)
    for sx in (-1, 1):
        box("rod", (w(16), w(4), w(4)), (sx * w(39.5 + 8), yf, rf), "Dark")
    box("axle", (w(150), w(5), w(5)), (0, yr, rr), "Dark")

    # Tekerler: yuvarlak lastik (köşeleri yuvarlatılmış), düz beyaz göbek diski,
    # dışarı taşan göbek kapağı ve ortada koyu somun
    def round_wheel(name, pos, r, tw, hub_r, cap_r, cap_out, nut_r):
        seg = 16
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=tw)
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
        tire = new_object(name, bm, ["Tire"])
        bevel(tire, w(4), 2)
        flat(tire)
        for side in (-1, 1):
            parts = ((hub_r, 0.01, tw / 2, "Hub"), (cap_r, cap_out + 0.004, tw / 2 + cap_out / 2, "Hub"),
                     (nut_r, 0.01, tw / 2 + cap_out + 0.003, "Dark"))
            for k, (rad, depth, off, mat) in enumerate(parts):
                bm = bmesh.new()
                bmesh.ops.create_cone(bm, cap_ends=True, segments=seg if k < 2 else 8, radius1=rad, radius2=rad, depth=depth)
                bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
                bmesh.ops.translate(bm, verts=bm.verts, vec=(side * off, 0, 0))
                ob = new_object(name + "_p", bm, [mat])
                ob.parent = tire
                flat(ob)
        tire.location = pos
        return tire

    xf, xr = w(66.7), w(77.8)
    for name, x, y, r, tw, hub, cap, out, nut in (
            ("wheel_FL", -xf, yf, rf, w(27.73), w(17.4), w(8.5), w(3.75), w(4.9)),
            ("wheel_FR", xf, yf, rf, w(27.73), w(17.4), w(8.5), w(3.75), w(4.9)),
            ("wheel_RL", -xr, yr, rr, w(30.97), w(19.43), w(9.5), w(4.18), w(5.44)),
            ("wheel_RR", xr, yr, rr, w(30.97), w(19.43), w(9.5), w(4.18), w(5.44))):
        round_wheel(name, (x, y, r), r, tw, hub, cap, out, nut)


def build_yarisci():
    """Yarışçı (Figma "RUNNY / Araba 2" çiziminden): yükselerek genişleyen dar burun,
    açık kokpit ve üstünden öne uzanan koruma çubuğu (iki dikmeyle), eğimli motor
    kapağı, iki dikmeye oturan büyük arka kanat, geniş yan gövdeler, kalın arka tekerler.
    Ölçüler çizimin pikselleri: yan görünüşte x boy (burun solda), y aşağı (yer y=326)."""
    MID, GROUND = 300.0, 326.0
    w = lambda px: px * DS

    def P(x, y):
        return (MID - x) * DS, (GROUND - y) * DS

    def st(x, hb, ht, yb, yt):
        Y, Zb = P(x, yb)
        _, Zt = P(x, yt)
        return (Y, w(hb), w(ht), Zb, Zt)

    def slab(name, pts, x_in, x_out, mat="Paint"):
        """Yan görünüş çokgeni (x, y) iki düzlem arasında (iç ve dış yarı genişlik, y'ye bağlı)."""
        bm = bmesh.new()
        a, b = [], []
        for x, y in pts:
            Y, Z = P(x, y)
            a.append(bm.verts.new((w(x_in(y)), Y, Z)))
            b.append(bm.verts.new((w(x_out(y)), Y, Z)))
        bm.faces.new(a)
        bm.faces.new(list(reversed(b)))
        n = len(pts)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        ob = new_object(name, bm, [mat])
        flat(ob)
        return ob

    # Alt gövde: burun önde dar (önden 35 px), yukarı çıkarak genişler; kokpitin önünde
    # basamak; yan gövdeler arkaya doğru genişler; arkada alçak tampon kutusu
    loft("body", [
        st(155, 17.5, 17.5, 311, 288),
        st(274, 38, 36, 311, 260),
        st(285, 42, 38, 311, 273),
        st(339, 44, 38, 311, 265.5),
        st(379, 46, 38, 311, 260),
        st(423, 47.5, 40, 311, 258),
        st(424, 47.5, 47.5, 311, 288),
        st(439, 47.5, 47.5, 311, 288),
    ])
    # Motor kapağı: kokpitin arkasında eğik ön yüz, tepeden arkaya doğru alçalır
    loft("cover", [
        st(339, 36, 36, 266, 265),
        st(348, 38, 29.5, 266, 239.5),
        st(359, 38, 29.5, 264, 230),
        st(401.5, 38, 29.5, 262, 250),
        st(423, 40, 34, 262, 258),
    ])
    # Koruma çubuğu: kokpitin arka üstünde kısa düz plaka (önden 51 px geniş)
    loft("halo", [
        st(316, 25.5, 25.5, 239.5, 232),
        st(359, 25.5, 25.5, 239.5, 230),
    ])
    # Çubuğun iki yan dikmesi (yan görünüşte motor kapağının ön kenarı boyunca)
    for sx in (-1, 1):
        bm = bmesh.new()
        Y0, Z0 = P(348, 239.5)
        Y1, Z1 = P(339, 265.5)
        a = Vector((sx * w(25.0), Y0, Z0))
        b = Vector((sx * w(28.5), Y1, Z1))
        mid, d = (a + b) / 2, (b - a)
        ob = box("halo_post", (w(4), w(4), d.length), mid, "Paint")
        ob.rotation_euler = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_euler()

    # Arka kanat ve iki dikmesi
    slab("wing", [(405, 217.5), (445, 214), (445, 226), (405, 226)], lambda y: -74.5, lambda y: 74.5)
    strut = [(415.5, 224), (431.5, 224), (423.5, 290), (405, 290), (401.5, 250)]
    out = lambda y: 24.5 + (y - 225) / (289 - 225) * 5.0
    slab("strut_r", strut, lambda y: 14.5, out)
    slab("strut_l", strut, lambda y: -out(y), lambda y: -14.5)

    # Kırmızı yüzeyler (siyah gövdede far ve camlar): burun ağzı, kokpit açıklığı,
    # motor kapağının ön yüzü ve arkadaki menfez
    bm = bmesh.new()

    def quad(pts, face_dir):
        f = bm.faces.new([bm.verts.new(p) for p in pts])
        f.normal_update()
        if f.normal.dot(Vector(face_dir)) < 0:
            f.normal_flip()

    Y, _ = P(155, 0)
    _, z0 = P(0, 306)
    _, z1 = P(0, 293)
    quad([(-w(9.5), Y + 0.004, z0), (w(9.5), Y + 0.004, z0), (w(9.5), Y + 0.004, z1), (-w(9.5), Y + 0.004, z1)], (0, 1, 0))
    # Kokpit: yan gövdenin üstünde, çubuğun altında
    pts = []
    for x, y, hw in ((287, 272.6, -22), (287, 272.6, 22), (337, 265.9, 22), (337, 265.9, -22)):
        Y, Z = P(x, y)
        pts.append((w(hw), Y, Z + 0.004))
    quad(pts, (0, 0, 1))
    # Motor kapağının ön yüzü (önden görünüşte siyah)
    pts = []
    for x, y, hw in ((339.4, 264.5, -36), (339.4, 264.5, 36), (347.6, 240.5, 29.8), (347.6, 240.5, -29.8)):
        Y, Z = P(x, y)
        pts.append((w(hw), Y + 0.004, Z))
    quad(pts, (0, 1, 0.3))
    # Arka menfez: kapağın eğik sırtında, kanat dikmelerinin arasında
    pts = []
    for x, y, hw in ((384, 242.0, -14), (384, 242.0, 14), (400.5, 249.6, 14), (400.5, 249.6, -14)):
        Y, Z = P(x, y)
        pts.append((w(hw), Y, Z + 0.006))
    quad(pts, (0, -0.4, 1))
    g = new_object("red", bm, ["Tail"])
    flat(g)

    # Akslar
    yf, _ = P(203.59, 0)
    yr, _ = P(381.8, 0)
    rf, rr = w(26.59), w(33.8)
    for sx in (-1, 1):
        box("rod", (w(31.25), w(3.5), w(3.5)), (sx * w(30.55 + 15.6), yf, rf), "Dark")
    box("axle", (w(150), w(5), w(5)), (0, yr, rr), "Dark")

    # Tekerler (Dragster'daki gibi: göbek diski, kapak, somun)
    def round_wheel(name, pos, r, tw, hub_r, cap_r, cap_out, nut_r):
        seg = 16
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=tw)
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
        tire = new_object(name, bm, ["Tire"])
        bevel(tire, w(4), 2)
        flat(tire)
        for side in (-1, 1):
            # Jant (göbek diski ve kapak) siyah, lastik kırmızı (TIRE_COLORS)
            parts = ((hub_r, 0.01, tw / 2, "Dark"), (cap_r, cap_out + 0.004, tw / 2 + cap_out / 2, "Dark"),
                     (nut_r, 0.01, tw / 2 + cap_out + 0.003, "Dark"))
            for k, (rad, depth, off, mat) in enumerate(parts):
                bm = bmesh.new()
                bmesh.ops.create_cone(bm, cap_ends=True, segments=seg if k < 2 else 8, radius1=rad, radius2=rad, depth=depth)
                bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
                bmesh.ops.translate(bm, verts=bm.verts, vec=(side * off, 0, 0))
                ob = new_object(name + "_p", bm, [mat])
                ob.parent = tire
                flat(ob)
        tire.location = pos
        return tire

    xf, xr = w(52.2), w(67.8)
    for name, x, y, r, tw, hub, cap, cout, nut in (
            ("wheel_FL", -xf, yf, rf, w(27.73), w(15.46), w(7.5), w(3.75), w(4.33)),
            ("wheel_FR", xf, yf, rf, w(27.73), w(15.46), w(7.5), w(3.75), w(4.33)),
            ("wheel_RL", -xr, yr, rr, w(30.97), w(19.65), w(9.5), w(4.18), w(5.5)),
            ("wheel_RR", xr, yr, rr, w(30.97), w(19.65), w(9.5), w(4.18), w(5.5))):
        round_wheel(name, (x, y, r), r, tw, hub, cap, cout, nut)


def build_latte():
    """Latte (Figma "RUNNY / Araba 3" çiziminden; krem, turuncu lastikler ve motor çıkıntıları): keski gibi sivri burun, kaputta orta
    çizgide üç küçük motor çıkıntısı, tavanı öne siperlik gibi uzanan kabin (önü ve arka camı
    siyah), arkada orta çizgide ince yüksek yüzgeç, lambasız kutu arka tampon, gövdenin dışında
    açıkta duran tekerler (akslarla). Ölçüler çizimin pikselleri: yan görünüşte x boy
    (burun solda), y aşağı (yer y=326); önden/arkadan görünüşte orta çizgi 994.3 / 634.3."""
    MID, GROUND = A3_MID, 326.0
    w = lambda px: px * DS

    def P(x, y):
        return (MID - x) * DS, (GROUND - y) * DS

    def st(x, hb, ht, yb, yt):
        Y, Zb = P(x, yb)
        _, Zt = P(x, yt)
        return (Y, w(hb), w(ht), Zb, Zt)

    def hexa(name, bot, top, mat="Paint"):
        """Alt ve üst dikdörtgenden (x ön, x arka, y, yarı genişlik) eğik yüzlü blok."""
        bm = bmesh.new()
        vs = []
        for x0, x1, y, hw in (bot, top):
            for x, sx in ((x0, -1), (x0, 1), (x1, 1), (x1, -1)):
                Y, Z = P(x, y)
                vs.append(bm.verts.new((sx * w(hw), Y, Z)))
        b, t = vs[:4], vs[4:]
        bm.faces.new(b)
        bm.faces.new(list(reversed(t)))
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((b[i], b[j], t[j], t[i]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        ob = new_object(name, bm, [mat])
        flat(ob)
        return ob

    # Gövde: önü keski (üst yüz 156→140, alt pah 154→140), üstü arkaya doğru hafif alçalır,
    # arkası eğik iner; önden/arkadan altta 100, üstte 88 px geniş
    top_y = lambda x: 258.9 + 3.18 * (x - 156.4) / (395.98 - 156.4)
    loft("body", [
        st(140.5, 47, 47, 282.0, 281.3),
        st(154.0, 50, 44.5, 302.35, 262.4),
        st(156.4, 50, 44, 302.35, 258.9),
        st(396.0, 50, 44, 302.35, top_y(396.0)),
        st(401.3, 50, 47, 302.35, 282.2),
    ])
    # Arka tampon kutusu
    loft("bumper", [st(399.2, 50, 50, 302.35, 281.15), st(414.0, 50, 50, 302.35, 281.15)])
    # Kabin: önden/arkadan tepede 55, altta 77-79 px; yandan ön dikme 325→317, arka 368→380
    hexa("cabin", (316.6, 380.5, 262.6, 38.75), (325.3, 368.3, 220.2, 27.5))
    # Tavanın öne uzanan siperliği (önden 55 px geniş)
    hexa("visor", (273.6, 326.8, 231.0, 27.5), (280.0, 332.9, 221.0, 25.5))
    # Kaputta orta çizgide üç motor çıkıntısı (önden 11 px geniş), lastiklerle aynı turuncu
    for x0, x1 in ((197, 208), (214, 226), (232, 243)):
        hexa("scoop", (x0, x1, top_y((x0 + x1) / 2) + 1.5, 5.5), (x0, x1, 248.0, 5.5), "Tire")
    # Arkada orta çizgide yüzgeç (arkadan 13 px geniş)
    bm = bmesh.new()
    pts = [(355.1, 241.0), (428.5, 241.0), (401.0, 283.0), (350.0, 283.0)]
    a = [bm.verts.new((-w(6.5),) + P(x, y)) for x, y in pts]
    b = [bm.verts.new((w(6.5),) + P(x, y)) for x, y in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((a[i], a[j], b[j], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    flat(new_object("fin", bm, ["Paint"]))

    # Yüzeye yapışık levhalar: ön cam ve arka cam (siyah), farlar ve stoplar
    def plate(name, mat, quads):
        bm = bmesh.new()
        for pts, face_dir in quads:
            f = bm.faces.new([bm.verts.new(q) for q in pts])
            f.normal_update()
            if f.normal.dot(Vector(face_dir)) < 0:
                f.normal_flip()
        ob = new_object(name, bm, [mat])
        flat(ob)

    def on_edge(p0, p1, y, hw, push):
        """Yan görünüşte p0→p1 kenarının y yüksekliğindeki noktası, ±hw genişlikte."""
        (x0, y0), (x1, y1) = p0, p1
        x = x0 + (x1 - x0) * (y - y0) / (y1 - y0)
        Y, Z = P(x, y)
        return Y + push, Z

    # Ön cam: kabinin ön yüzünde siperliğin altından gövdeye (üstte 55, altta 67 px)
    f0, f1 = (325.3, 220.2), (316.6, 262.6)
    q = []
    for y, hw in ((260.0, 33.5), (231.0, 27.5)):
        Y, Z = on_edge(f0, f1, y, hw, 0.006)
        q.append([(-w(hw), Y, Z), (w(hw), Y, Z)])
    windshield = [q[0][0], q[0][1], q[1][1], q[1][0]]
    # Arka cam: kabinin arka yüzünün üstünde (54 → 48 px)
    r0, r1 = (368.3, 220.2), (380.5, 262.6)
    q = []
    for y, hw in ((233.0, 27.0), (242.0, 24.1)):
        Y, Z = on_edge(r0, r1, y, hw, -0.006)
        q.append([(-w(hw), Y, Z), (w(hw), Y, Z)])
    rear_win = [q[0][0], q[0][1], q[1][1], q[1][0]]
    plate("glass", "Glass", [(windshield, (0, 1, 0.2)), (rear_win, (0, -1, 0.3))])
    # Farlar: burnun alt pahında (önden 13 px); arkada lamba yok (yeşil iz oradan çıkar)
    n0, n1 = (140.5, 281.15), (154.0, 302.35)
    lights = []
    for c in (-33.8, 33.2):
        (Ya, Za), (Yb, Zb) = on_edge(n0, n1, 286.0, 0, 0.004), on_edge(n0, n1, 297.0, 0, 0.004)
        lights.append(([(w(c - 6.5), Ya, Za), (w(c + 6.5), Ya, Za), (w(c + 6.5), Yb, Zb), (w(c - 6.5), Yb, Zb)], (0, 1, -0.6)))
    plate("lights", "Light", lights)

    # Tekerler: gövdenin dışında (iz yarısı 66.7 px), aks çubuklarıyla gövdeye bağlı
    yf, _ = P(190.98, 0)
    yr, _ = P(363.75, 0)
    r, tw = w(28.18), w(27.73)
    xt = w(66.7)
    for y in (yf, yr):
        for sx in (-1, 1):
            box("rod", (w(31.25), w(3.73), w(3.73)), (sx * w(60.7), y, w(326 - 298)), "Dark")

    def wheel3(name, pos):
        seg = 18
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=tw)
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
        tire = new_object(name, bm, ["Tire"])
        bevel(tire, w(4), 2)
        flat(tire)
        for side in (-1, 1):
            # Jant diski (çizimde iç çember) ve dışa taşan göbek, ortada koyu somun
            for rad, depth, off, mat, sg in ((w(16.4), 0.01, tw / 2, "Hub", seg),
                                             (w(7.9), w(5.6), tw / 2 + w(2.8), "Hub", 12),
                                             (w(4.6), 0.01, tw / 2 + w(5.6) + 0.003, "Dark", 8)):
                bm = bmesh.new()
                bmesh.ops.create_cone(bm, cap_ends=True, segments=sg, radius1=rad, radius2=rad, depth=depth)
                bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
                bmesh.ops.translate(bm, verts=bm.verts, vec=(side * off, 0, 0))
                ob = new_object(name + "_p", bm, [mat])
                ob.parent = tire
                flat(ob)
        tire.location = pos
        return tire

    for name, x, y in (("wheel_FL", -xt, yf), ("wheel_FR", xt, yf), ("wheel_RL", -xt, yr), ("wheel_RR", xt, yr)):
        wheel3(name, (x, y, r))


def build_falcon():
    """Falcon (Figma "RUNNY / Araba 4" çiziminden; yandan, arkadan ve üstten görünüş;
    turuncu, beyaz lastikler, turuncu jantlar):
    kama gibi alçak sivri burun; altta arkaya doğru genişleyen gövde (arkadan iki yan
    blok, dışa doğru eğik); onun üstünde arkaya doğru yükselen, ortası sırtlı çatı
    biçimli güverte (arkadan beşgen: omuzlar ve tepede sırt); güvertenin üstünde ok
    biçimli siyah kokpit camı; arkada altta ince panel ve ortada yüzgeç; arka tekerler
    büyük. Ölçüler çizimin pikselleri: yan görünüşte x boy (burun solda, 128 → 454),
    y aşağı (yer y=320); arkadan orta çizgi x=620.5; üstten orta çizgi x=970, burun aşağıda.
    Üstten görünüş enine 1.38 kat geniş çizilmiş (arka teker izi ve gövde arkadan
    görünüşle bu oranla örtüşür): üstten alınan enine ölçüler K ile küçültülür."""
    MID, GROUND = A4_MID, 320.0
    K = 70.5 / 97.4
    w = lambda px: px * DS

    def P(x, y):
        return (MID - x) * DS, (GROUND - y) * DS

    def side_x(ty):
        """Üstten görünüşteki y → yan görünüşteki x (burun 450 → 128, arka 121 → 454)."""
        return 128.0 + (450.0 - ty) * (326.0 / 329.0)

    def lerp_pts(pts, x):
        """(x, değer) noktaları arasında doğrusal ara değer."""
        pts = sorted(pts)
        if x <= pts[0][0]:
            return pts[0][1]
        for (x0, v0), (x1, v1) in zip(pts, pts[1:]):
            if x <= x1:
                return v0 + (v1 - v0) * (x - x0) / (x1 - x0)
        return pts[-1][1]

    def ring_loft(name, rings, mat="Paint"):
        """Her kesit aynı sayıda (x_yanal_px, y_px) noktalı çokgen, yan görünüş x'inde."""
        bm = bmesh.new()
        vs = []
        for x, ring in rings:
            Y, _ = P(x, 0)
            vs.append([bm.verts.new((w(dx), Y, (GROUND - y) * DS)) for dx, y in ring])
        n = len(vs[0])
        for a, b in zip(vs, vs[1:]):
            for i in range(n):
                k = (i + 1) % n
                bm.faces.new((a[i], a[k], b[k], b[i]))
        bm.faces.new(vs[0])
        bm.faces.new(list(reversed(vs[-1])))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        ob = new_object(name, bm, [mat])
        flat(ob)
        return ob

    def loft3(name, rings, mat="Paint"):
        """Her kesit aynı sayıda (x_yan, yanal_px, y_px) noktası; kesitler arası düz kenarlar."""
        bm = bmesh.new()
        vs = [[bm.verts.new((w(z),) + P(x, y)) for x, z, y in ring] for ring in rings]
        n = len(vs[0])
        for a, b in zip(vs, vs[1:]):
            for i in range(n):
                k = (i + 1) % n
                bm.faces.new((a[i], a[k], b[k], b[i]))
        caps = [bm.faces.new(vs[0]), bm.faces.new(list(reversed(vs[-1])))]
        bmesh.ops.triangulate(bm, faces=caps)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        ob = new_object(name, bm, [mat])
        flat(ob)
        return ob

    # Bütün boyuna kenarlar burundan arkaya dümdüz (çizgiler doğru): sırt, omuz (= yan blokların
    # üst iç kenarı), yan blokların üst dış ve alt kenarları; yanal ölçüler x ile doğrusal.
    # Arkada arkadan görünüşün ölçüleri: blok üstü 57-69.5 (x 402.4), altı 43-83.5 (x 445; orta
    # çizgiden); burunda dış kenar üstten görünüşteki gibi ~31 (K ile). Yüzler düz (kırılmasız):
    # her yüzün iki kenarı uzatılınca aynı noktada buluşur (çatı: sırt ile omuz x 34.6'da;
    # yan yüzler: üst çizgi ile alt (307) x 85.5'te)
    lin = lambda x0, v0, x1, v1: (lambda x: v0 + (v1 - v0) * (x - x0) / (x1 - x0))
    crease = lin(128.0, 297.07, 402.4, 233.0)          # yandan Rect 42 üst çizgisi (uzatılabilir)
    ridge = lin(142.5, 287.0, 454.0, 195.0)            # yandan Rect 43 üst çizgisi
    x_roof = 128.0 + (crease(128.0) - ridge(128.0)) / ((crease(128.0) - crease(402.4)) / 274.4
                                                      - (ridge(128.0) - ridge(454.0)) / 326.0)
    x_wall = 128.0 - (307.0 - crease(128.0)) / ((crease(128.0) - crease(402.4)) / 274.4)
    TI = lin(x_roof, 0.0, 402.4, 57.0)                 # omuz / blok üst iç kenarı
    TO = lin(128.0, 31.3, 402.4, 69.5)                 # blok üst dış kenarı
    BI = lin(x_wall, TI(x_wall), 445.0, 43.0)          # blok alt iç kenarı
    BO = lin(x_wall, TO(x_wall), 445.0, 83.5)          # blok alt dış kenarı

    # Yan bloklar: yandan Rect 42 (burun önü 128,297 → 132,307 düz yüz; üst çizgi 402.4,233; arka eğik
    # yüz 445,307), arka tekerin üstünde kemer (344.6-417.4, tepe 250). Dış yüz aşağı doğru dışa, iç yüz
    # içe eğik (arkadan yamuk)
    arch_c, arch_r = (381.0, 286.4), 36.4
    a0 = math.atan2(282.7 - arch_c[1], 417.4 - arch_c[0])
    arch = []
    for k in range(13):
        a = a0 + (math.pi - 2 * a0) * k / 12  # 417.4'ten tepeden geçip 344.6'ya
        arch.append((arch_c[0] + arch_r * math.cos(a), arch_c[1] - arch_r * math.sin(a)))
    pod = [(445.0, 307.0), (417.4, 307.0)] + arch + [(344.6, 307.0), (132.0, 307.0), (128.0, 297.07), (402.4, 233.0)]
    def wall(x, y, lo, hi):
        s = (307.0 - y) / (307.0 - crease(x))
        return lo(x) + (hi(x) - lo(x)) * s
    for sx in (-1, 1):
        bm = bmesh.new()
        a_, b_ = [], []
        for x, y in pod:
            a_.append(bm.verts.new((sx * w(wall(x, y, BI, TI)),) + P(x, y)))
            b_.append(bm.verts.new((sx * w(wall(x, y, BO, TO)),) + P(x, y)))
        caps = [bm.faces.new(a_), bm.faces.new(list(reversed(b_)))]
        n = len(pod)
        for i2 in range(n):
            k2 = (i2 + 1) % n
            bm.faces.new((a_[i2], a_[k2], b_[k2], b_[i2]))
        bmesh.ops.triangulate(bm, faces=caps)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        flat(new_object("pod", bm, ["Paint"]))

    # Güverte (gövdenin ortası): çatı sırttan omuzlara iner, omuzdan aşağısı blokların iç yüzüne
    # oturur. Önde blokların ön yüzüyle aynı düz yüz (sırt biraz geride, 142.5,287); arkada ok ucu:
    # omuz çizgisi uzar, arka yüz yandan (454,195)→(423,269) çizgisinde (tepe, omuz köşeleri, alt)
    xw = 441.9                                          # omuz çizgisi ile arka yüz çizgisinin kesişimi
    ring = lambda xb, b, yb, xs, ys, xr, yr, sw: [(xb, -b, yb), (xb, b, yb), (xs, sw, ys), (xr, 0.0, yr),
                                                  (xs, -sw, ys)]
    loft3("body", [ring(132.0, BI(132.0), 307.0, 128.0, crease(128.0), 142.5, ridge(142.5), TI(128.0)),
                   ring(402.4, BI(402.4), 307.0, 402.4, crease(402.4), 402.4, ridge(402.4), TI(402.4)),
                   ring(423.0, 50.0, 269.0, xw, crease(xw), 454.0, ridge(454.0), TI(xw))])
    def roof(x, d):
        """Güverte çatısının yanal d (px) uzaklıktaki yüksekliği (sırttan omza düz iner)."""
        return ridge(x) + (crease(x) - ridge(x)) * min(abs(d) / TI(x), 1.0)
    # Kokpit camı: güverte çatısına oturan ok biçimi (üstten: arka dış ±48,249; arka orta 268;
    # ön dış ±33.3,321; ön orta 335; enine K ile)
    # Sırtın iki yanı ayrı parça: her yarı kendi çatı yüzeyine oturur (sırt camın içinden çıkmaz)
    bm = bmesh.new()
    for sgn in (-1.0, 1.0):
        half_pts = [(sgn * 48.0, 249.0), (0.0, 268.0), (0.0, 335.0), (sgn * 33.3, 321.0)]
        top, bot = [], []
        for dx, ty in half_pts:
            x, d = side_x(ty), dx * K
            Y, _ = P(x, 0)
            top.append(bm.verts.new((w(d), Y, (GROUND - roof(x, d) + 1.5) * DS)))
            bot.append(bm.verts.new((w(d), Y, (GROUND - roof(x, d) - 1.0) * DS)))
        ft = bm.faces.new(top)
        fb = bm.faces.new(list(reversed(bot)))
        for i in range(4):
            k = (i + 1) % 4
            bm.faces.new((top[i], bot[i], bot[k], top[k]))
        bmesh.ops.triangulate(bm, faces=[ft, fb])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    flat(new_object("canopy", bm, ["Glass"]))
    # Arka yüzgeç: yandan (401.5,250.5)-(454.5,250.5)-(435,294); arkadan tepede 13, altta 33 px
    bm = bmesh.new()
    pts = [(401.5, 250.5), (454.5, 250.5), (435.0, 294.0)]
    half = lambda y: 6.5 + (y - 250.5) / 56.0 * 10.0
    a = [bm.verts.new((-w(half(y)),) + P(x, y)) for x, y in pts]
    b = [bm.verts.new((w(half(y)),) + P(x, y)) for x, y in pts]
    bm.faces.new(a)
    bm.faces.new(list(reversed(b)))
    for i in range(3):
        k = (i + 1) % 3
        bm.faces.new((a[i], a[k], b[k], b[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    flat(new_object("fin", bm, ["Paint"]))
    # Arkada altta ince panel (arkadan 575-667, y 297-307)
    Yp, _ = P(438.0, 0)
    box("diffuser", (w(92), w(12), w(10)), (0, Yp, w(320 - 302)), "Paint")

    # Akslar (arkadan: arka aks tekerden gövdeye 539-574.5, y 286.5; ön: üstten, K ile)
    yf, _ = P(189.33, 0)
    yr, _ = P(381.2, 0)
    rf, rr = w(27.67), w(33.5)
    for sx in (-1, 1):
        box("axle_r", (w(35.4), w(4.5), w(4.5)), (sx * w(620.5 - 539.07 - 17.7), yr, rr), "Dark")
        box("axle_f", (w(44.25 * K), w(3.67), w(3.67)), (sx * w((970 - 868.33 - 22.1) * K), yf, rf), "Dark")

    def wheel4(name, pos, r, tw, hub_r, hub_out, nut_r):
        seg = 18
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=tw)
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
        tire = new_object(name, bm, ["Tire"])
        bevel(tire, w(4), 2)
        flat(tire)
        for side in (-1, 1):
            # Jantlar gövde renginde (turuncu)
            for rad, depth, off, mat, sg in ((r * 0.58, 0.01, tw / 2, "Paint", seg),
                                             (hub_r, hub_out, tw / 2 + hub_out / 2, "Paint", 12),
                                             (nut_r, 0.01, tw / 2 + hub_out + 0.003, "Dark", 8)):
                bm = bmesh.new()
                bmesh.ops.create_cone(bm, cap_ends=True, segments=sg, radius1=rad, radius2=rad, depth=depth)
                bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), cent=(0, 0, 0))
                bmesh.ops.translate(bm, verts=bm.verts, vec=(side * off, 0, 0))
                ob = new_object(name + "_p", bm, [mat])
                ob.parent = tire
                flat(ob)
        tire.location = pos
        return tire

    # Arka teker: arkadan iz yarısı 70.5, genişlik 31.4, göbek 4.25 px dışarı (19 px boy);
    # ön teker: üstten (K ile) iz yarısı 63.7, genişlik 28.4
    xf_, xr_ = w((970 - 881.95) * K), w(620.5 - 550.0)
    for name, x, y, r, tw, hub, out, nut in (
            ("wheel_FL", -xf_, yf, rf, w(39.26 * K), w(7.8), w(5.3 * K), w(4.5)),
            ("wheel_FR", xf_, yf, rf, w(39.26 * K), w(7.8), w(5.3 * K), w(4.5)),
            ("wheel_RL", -xr_, yr, rr, w(31.44), w(9.5), w(4.25), w(5.4)),
            ("wheel_RR", xr_, yr, rr, w(31.44), w(9.5), w(4.25), w(5.4))):
        wheel4(name, (x, y, r), r, tw, hub, out, nut)


def stretch_y(k):
    """Arabayı boyuna uzatır (tekerler büyümez, yalnız yerleri kayar)."""
    for ob in bpy.context.scene.objects:
        if ob.parent is not None or ob.type != "MESH":
            continue
        ob.location.y *= k
        if not ob.name.startswith("wheel_"):
            for v in ob.data.vertices:
                v.co.y *= k


A3_MID = 277.0       # Latte (Araba 3): yan görünüşte arabanın ortası (burun 140.5, arka 414)
A4_MID = 291.0       # Falcon (Araba 4): yan görünüşte arabanın ortası (burun 128, arka 454)
BUILDERS = {"kutu": build_kutu, "dragster": build_dragster, "yarisci": build_yarisci, "latte": build_latte,
            "falcon": build_falcon}
## Figma çizimli arabalar: yan görünüşte arabanın ortası ve yer çizgisi (piksel)
## (isteğe bağlı 3. değer: yan görünüşte kameranın baktığı x; yoksa 296.5)
ORTHO = {"dragster": (D_MID, 334.0), "yarisci": (300.0, 326.0), "latte": (A3_MID, 326.0, 284.5),
         "falcon": (A4_MID, 320.0, 291.0)}
## Modelin gövde rengi (oyun bu rengi alır)
PAINTS = {"dragster": ((1.0, 0.549, 0.255), 0.6, 0.0), "yarisci": ((0.11, 0.11, 0.12), 0.45, 0.0),
          "latte": ((0.886, 0.776, 0.596), 0.55, 0.0)}
## Lastik rengi (oyun bu rengi alır); yoksa koyu gri
TIRES = {"yarisci": ((0.82, 0.16, 0.13), 0.8, 0.0), "latte": ((1.0, 0.353, 0.122), 0.8, 0.0),
         "falcon": ((0.95, 0.945, 0.93), 0.9, 0.0)}


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


def render(dirpath, name, studio=False):
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
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.45 if studio else 0.9
    scene.world = world
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=300)
    floor = new_object("floor", bm, [])
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    floor_c = (0.8, 0.79, 0.77) if studio else (0.165, 0.173, 0.188)
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = srgb_to_linear(floor_c) + (1,)
    floor.data.materials.append(fm)
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.4 if studio else 3.5
    sun.data.angle = math.radians(25 if studio else 8)
    sun.rotation_euler = (math.radians(18 if studio else 30), math.radians(-12 if studio else -25), math.radians(-35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    views = {"on": (6.2, 6.0, 2.6), "yan": (8.5, 0.0, 1.4), "arka": (-5.5, -6.5, 3.0), "ust": (4.0, 2.0, 9.0),
             "ref": (-11.8, 9.4, 5.0)}
    for view, loc in views.items():
        cam.location = loc
        cam.data.lens = 118 if view == "ref" else 50
        scene.render.resolution_x = 700 if view == "ref" else 900
        scene.render.resolution_y = 700 if view == "ref" else 600
        d = Vector((0, 0, 0.75 if view != "ref" else 0.55)) - Vector(loc)
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(dirpath, "%s_%s.png" % (name, view))
        bpy.ops.render.render(write_still=True)
    floor.select_set(True)


def render_ortho(dirpath, name, views, scale, size=300):
    """Dik (ortografik) görünüşler: views = {ad: (kamera konumu, bakılan nokta)}; 1 piksel = scale m."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("wo")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scene.world = world
    sun = bpy.data.objects.new("sun_o", bpy.data.lights.new("sun_o", "SUN"))
    sun.data.energy = 2.5
    sun.rotation_euler = (math.radians(35), math.radians(-20), math.radians(-35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam_o", bpy.data.cameras.new("cam_o"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = size * scale
    scene.collection.objects.link(cam)
    scene.camera = cam
    for view, (loc, target) in views.items():
        cam.location = loc
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(dirpath, "%s_%s.png" % (name, view))
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="models/cars")
    ap.add_argument("--render", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--studio", action="store_true")
    ap.add_argument("--ortho", action="store_true")
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    for name, build in BUILDERS.items():
        if a.only and name != a.only:
            continue
        clear_scene()
        COLORS["Paint"] = PAINTS.get(name, ((1.0, 0.353, 0.122), 0.5, 0.0))
        COLORS["Tire"] = TIRES.get(name, ((0.11, 0.114, 0.125), 0.95, 0.0))
        build()
        join_body()
        print("%s: %d üçgen" % (name, triangles()))
        export(os.path.join(a.out, name + ".glb"))
        if a.render:
            os.makedirs(a.render, exist_ok=True)
            if a.ortho and name in ORTHO:
                # Figma çizimiyle aynı ölçek: her görünüş arabanın orta çizgisinde 300 px kare;
                # yan görünüş çizimin ızgara ortasında (x 296.5, y 281.5)
                mid, ground = ORTHO[name][:2]
                cx = ORTHO[name][2] if len(ORTHO[name]) > 2 else 296.5
                yc, zc = (mid - cx) * DS, (ground - 281.5) * DS
                views = {
                    "o_yan": ((-20, yc, zc), (0, yc, zc)),
                    "o_on": ((0, 20, zc), (0, 0, zc)),
                    "o_arka": ((0, -20, zc), (0, 0, zc)),
                }
                if name == "falcon":
                    # Bu çizimde önden görünüş yok, üstten görünüş var
                    views = {"o_yan": views["o_yan"], "o_arka": views["o_arka"], "o_ust": ((0, yc, 20), (0, yc, 0))}
                render_ortho(a.render, name, views, DS, 360 if name == "falcon" else 300)
            else:
                render(a.render, name, a.studio)


if __name__ == "__main__":
    main()

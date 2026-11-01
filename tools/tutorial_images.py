"""Tutorial sayfalarının görselleri: oyundan alınmış karelerin (720x1280) üstüne parmak, vurgu
halkası ve ok çizer; ui/tutorial/pN.png (640x640) yazar.
Kullanım: python3 tools/tutorial_images.py KARE_KLASÖRÜ   (a/ normal koşu, b/ uçuş; bkz. README)"""
import sys, os
from PIL import Image, ImageDraw

SRC = sys.argv[1]
OUT = os.path.join(os.path.dirname(__file__), "..", "ui", "tutorial")
ORANGE = (255, 90, 31)
INK = (34, 36, 40)
WHITE = (250, 249, 246)
S = 640


def crop(path, top):
    im = Image.open(os.path.join(SRC, path)).convert("RGB")
    return im.crop((0, top, 720, top + 720)).resize((S, S), Image.LANCZOS)


def ring(d, c, r, w=6, col=ORANGE):
    d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), outline=col, width=w)


def finger(d, c, r=30, ripple=True):
    """Dokunma: beyaz dolu daire, koyu kenar, çevresinde iki dalga"""
    if ripple:
        for k, a in ((1.9, 90), (1.45, 160)):
            ring(d, c, int(r * k), 4, WHITE + (a,))
    d.ellipse((c[0] - r, c[1] - r, c[0] + r, c[1] + r), fill=WHITE + (235,), outline=INK + (255,), width=4)


def arrow(d, c, direction, size=34, col=WHITE):
    x, y = c
    s = size
    pts = [(x + direction * s, y), (x - direction * s * 0.4, y - s * 0.75), (x - direction * s * 0.4, y + s * 0.75)]
    d.polygon(pts, fill=col + (240,), outline=INK + (255,))


def save(im, overlay, name):
    out = Image.alpha_composite(im.convert("RGBA"), overlay).convert("RGB")
    out.save(os.path.join(OUT, name))


def page(path, top):
    im = crop(path, top)
    ov = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ov, ImageDraw.Draw(ov)


# 1 Direksiyon: ekranın sol / sağ yarısı
im, ov, d = page("a/shot_120.png", 300)
d.rectangle((0, 0, S // 2 - 2, S), fill=(255, 255, 255, 38))
d.rectangle((S // 2 + 2, 0, S, S), fill=(255, 255, 255, 38))
d.line((S // 2, 30, S // 2, S - 30), fill=WHITE + (200,), width=3)
for side in (-1, 1):
    c = (S // 2 + side * 160, 470)
    finger(d, c)
    arrow(d, (c[0] + side * 85, c[1]), side)
save(im, ov, "p1.png")

# 2 Roket: yolun sonundaki kırmızı ışıklar + iki parmak
im, ov, d = page("a/shot_240.png", 300)
finger(d, (200, 590))
finger(d, (440, 590))
save(im, ov, "p2.png")

# 3 Enerji: sağ alttaki gösterge ve yoldaki kristaller
im, ov, d = page("a/shot_90.png", 560)
ring(d, (504, 508), 92)
save(im, ov, "p3.png")

# 4 Engeller: çizgili bloklar
im, ov, d = page("a/shot_180.png", 300)
save(im, ov, "p4.png")

# 5 Kanatlar: uçuş, turuncu halkalar, iki parmakla yüksel
im, ov, d = page("b/shot_345.png", 200)
ring(d, (310, 300), 80)
finger(d, (130, 590))
finger(d, (510, 590))
save(im, ov, "p5.png")

# 6 Puan: üst köşelerde mesafe ve puan
im, ov, d = page("a/shot_360.png", 0)
for box in ((4, 8, 222, 104), (440, 8, 636, 104)):
    d.rounded_rectangle(box, 14, outline=ORANGE, width=6)
save(im, ov, "p6.png")
print("ok")

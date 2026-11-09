"""Uçarken / yolda parçalanma sesi için tasarım denemeleri (oyuna girmez; dinleyip seçmek için).
Kullanım: python3 tools/smash_sound_designs.py ÇIKIŞ_KLASÖRÜ
make_sounds.py'nin yapı taşlarını kullanır."""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_sounds as ms  # noqa: E402
from make_sounds import (SR, n_of, sine, glide, env, noise, filt, place, room, fade, click,  # noqa: E402
                         normalize)


def r():
    return ms.rng


def d1_dijital():
    """Dijital kırılma: net bir 'çıt', bit bit dağılan tiz doku ve aşağı inen küçük piksel blipleri."""
    d = 1.3
    buf = np.zeros(n_of(d))
    place(buf, click(0.003), 0.0, 0.9)
    t = np.arange(n_of(0.6)) / SR
    held = np.repeat(noise(0.6)[::24], 24)[:len(t)]
    crush = filt(held, lo=1500, hi=9000) * np.exp(-t / 0.12)
    place(buf, crush, 0.0, 0.5)
    notes = [88, 84, 81, 79, 76, 74, 72, 69, 67, 64]
    at = 0.03
    for k, m in enumerate(notes):
        f = ms.midi(m)
        b = (sine(f, 0.06) + 0.25 * sine(2 * f, 0.06)) * env(0.06, 0.001, 0.03)
        place(buf, b, at, 0.32 * (1 - k / 14))
        at += r().uniform(0.04, 0.08)
    return room(fade(buf, 0.0003, 0.08), 0.12, 0.6)


def d2_yumusak():
    """Yumuşak tok + dağılan tıkırtı: sert olmayan, boğuk bir 'tump', ardından hafif plastik/ahşap
    tıkırtılar ve kısa bir hava sesi."""
    d = 1.5
    buf = np.zeros(n_of(d))
    thump = sine(glide(140, 60, 0.25, 0.6), 0.25) * env(0.25, 0.004, 0.09)
    place(buf, thump, 0.0, 0.8)
    place(buf, filt(noise(0.05), lo=200, hi=1600) * env(0.05, 0.001, 0.02), 0.0, 0.5)
    at = 0.05
    while at < d - 0.1:
        f = r().uniform(900, 2200)
        tk = sine(f, 0.025) * env(0.025, 0.0005, 0.008)
        nz = 0.4 * filt(noise(0.012), lo=1500, hi=5000) * env(0.012, 0.0003, 0.004)
        tk[:len(nz)] += nz
        place(buf, tk, at, 0.35 * np.exp(-at / 0.5), pan=r().uniform(-0.6, 0.6))
        at += r().uniform(0.03, 0.09) * (1 + at * 1.2)
    sw = filt(noise(0.5), lo=500, hi=2000) * env(0.5, 0.04, 0.2) * 0.18
    place(buf, sw, 0.02, 1.0)
    return room(fade(buf, 0.0005, 0.08), 0.1, 0.5)


def d3_voksel():
    """Voksel yağmuru: kısa bir dijital 'pat' ve iki yana dağılan, giderek seyrelen ve alçalan
    tonlu bipler (parçalar saçılıyor gibi)."""
    d = 1.6
    buf = np.zeros(n_of(d))
    pat = sine(glide(300, 90, 0.12, 0.5), 0.12) * env(0.12, 0.001, 0.05)
    place(buf, pat, 0.0, 0.7)
    place(buf, click(0.004), 0.0, 0.6)
    scale = [0, 3, 5, 7, 10, 12, 15]
    at = 0.04
    k = 0
    while at < d - 0.1:
        m = 84 - int(at * 14) + scale[r().integers(len(scale))]
        f = ms.midi(m)
        b = np.sign(sine(f, 0.04)) * 0.5 * env(0.04, 0.0008, 0.015)
        b = filt(b, hi=6000)
        place(buf, b, at, 0.22 * np.exp(-at / 0.6), pan=r().uniform(-0.8, 0.8))
        at += r().uniform(0.025, 0.07) * (1 + at)
        k += 1
    return room(fade(buf, 0.0005, 0.08), 0.14, 0.7)


def d4_cam():
    """Cam gibi kırılma: parlak, çınlayan kısa kırık tonlar (uyumsuz kısmiler), ardından saçılan
    ince cam şıngırtıları; bas yok, temiz."""
    d = 1.5
    buf = np.zeros(n_of(d))
    place(buf, filt(noise(0.03), lo=3000) * env(0.03, 0.0005, 0.01), 0.0, 0.8)
    for f in [2350, 3170, 4420, 5310, 6880]:
        ring = sine(f * r().uniform(0.97, 1.03), 0.4) * env(0.4, 0.001, r().uniform(0.06, 0.15))
        place(buf, ring, r().uniform(0.0, 0.015), 0.14)
    at = 0.06
    while at < d - 0.1:
        f = r().uniform(3000, 8000)
        tink = sine(f, 0.05) * env(0.05, 0.0005, 0.018)
        place(buf, tink, at, 0.2 * np.exp(-at / 0.45), pan=r().uniform(-0.7, 0.7))
        at += r().uniform(0.02, 0.08) * (1 + at * 1.5)
    return room(fade(buf, 0.0003, 0.08), 0.16, 0.8)


def d5_buyuk_tiss():
    """Işık bariyeri 'tıss'ının büyüğü: aynı aile (tık + tiz hışırtı + çıtırtı) ama daha dolgun:
    altında yumuşak bir gövde darbesi, hışırtı ve çıtırtılar daha uzun sürer."""
    d = 1.4
    n = n_of(d)
    t = np.arange(n) / SR
    buf = np.zeros(n)
    place(buf, click(0.003), 0.0, 0.9)
    body = sine(glide(170, 70, 0.3, 0.6), 0.3) * env(0.3, 0.003, 0.1)
    place(buf, body, 0.0, 0.55)
    nz = noise(d)
    bright = filt(nz, lo=5000, hi=12000) * np.exp(-t / 0.18)
    mid = filt(nz, lo=1800, hi=6000) * np.exp(-t / 0.32)
    hiss = (0.8 * bright + 0.6 * mid) * np.minimum(t / 0.008, 1.0)
    hiss *= 1.0 + 0.2 * np.sin(2 * np.pi * 30 * t) * np.exp(-t / 0.4)
    buf += 0.8 * hiss
    crackle = np.zeros(n)
    for _ in range(120):
        at = r().exponential(0.25)
        if at > d - 0.02:
            continue
        c = filt(click(0.0025), lo=2500) * r().uniform(0.3, 0.9) * np.exp(-at / 0.35)
        place(crackle, c, at)
    buf += 0.55 * crackle
    return room(fade(buf, 0.0003, 0.08), 0.09, 0.45)


def d6_metal():
    """Temiz metal kopma: kısa, net bir 'klank' (süzülmüş, rezonanslı), ardından hafif sekme
    tıkırtıları; gürültü az, ezilme yok."""
    d = 1.4
    buf = np.zeros(n_of(d))
    for f, g, dec in [(410, 0.4, 0.18), (1030, 0.25, 0.12), (1720, 0.15, 0.08), (2690, 0.08, 0.05)]:
        place(buf, sine(f, 0.6) * env(0.6, 0.001, dec), 0.0, g)
    place(buf, filt(noise(0.04), lo=600, hi=4000) * env(0.04, 0.0005, 0.015), 0.0, 0.5)
    at = 0.12
    while at < d - 0.1:
        f = r().uniform(1400, 3200)
        tk = sine(f, 0.03) * env(0.03, 0.0005, 0.01)
        place(buf, tk, at, 0.22 * np.exp(-at / 0.5), pan=r().uniform(-0.6, 0.6))
        at += r().uniform(0.05, 0.12) * (1 + at)
    return room(fade(buf, 0.0005, 0.08), 0.12, 0.6)


DESIGNS = [("1_dijital", d1_dijital), ("2_yumusak", d2_yumusak), ("3_voksel", d3_voksel),
           ("4_cam", d4_cam), ("5_buyuk_tiss", d5_buyuk_tiss), ("6_metal", d6_metal)]


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)
    import soundfile as sf
    allb = []
    for name, fn in DESIGNS:
        ms.rng = np.random.default_rng(sum(map(ord, name)))
        x = normalize(fn(), 0.8)
        sf.write(out / f"carpma_{name}.wav", np.clip(x, -1, 1), SR, subtype="PCM_16")
        allb.append(x if x.ndim == 1 else x.mean(axis=1))
        allb.append(np.zeros(n_of(0.9)))
        print("yazıldı", name)
    sf.write(out / "carpma_hepsi_sirayla.wav", np.clip(np.concatenate(allb), -1, 1), SR, subtype="PCM_16")


if __name__ == "__main__":
    main()

"""Uçarken / yolda parçalanma sesi için tasarım denemeleri (oyuna girmez; dinleyip seçmek için).
Kullanım: python3 tools/smash_sound_designs.py ÇIKIŞ_KLASÖRÜ [--tron]
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




# --- Tron havası: dijital alternatifler (1_dijital'den yürür) ---------------------------------

def _t(d):
    return np.arange(n_of(d)) / SR


def saw(freq, d):
    ph = np.cumsum(np.broadcast_to(freq, n_of(d)) / SR) if np.ndim(freq) else np.arange(n_of(d)) * freq / SR
    return 2.0 * (ph % 1.0) - 1.0


def square(freq, d, duty=0.5):
    ph = np.cumsum(np.broadcast_to(freq, n_of(d)) / SR) if np.ndim(freq) else np.arange(n_of(d)) * freq / SR
    return np.where((ph % 1.0) < duty, 1.0, -1.0)


def crush(x, bits=5, hold=8):
    """Bit ve örnekleme azaltma: dijital, 'piksel' doku"""
    q = 2 ** bits
    y = np.round(x * q) / q
    return np.repeat(y[::hold], hold)[:len(x)]


def sweep_lp(x, f0, f1, d, q=0.0):
    """Aşağı (ya da yukarı) kayan alçak geçiren (basit tek kutuplu, rezonanssız + isteğe bağlı vurgu)"""
    n = len(x)
    f = f0 * (f1 / f0) ** (np.arange(n) / max(n - 1, 1))
    a = np.exp(-2 * np.pi * f / SR)
    y = np.zeros(n)
    acc = 0.0
    for i in range(n):
        acc = (1 - a[i]) * x[i] + a[i] * acc
        y[i] = acc
    return y


def t1_derez():
    """Derez: parlak dijital 'çıt' + aşağı kayan filtreli testere/gürültü süpürmesi; ses giderek
    bitlere ayrışır (çözünürlüğü düşer), sonunda kekeleyerek söner."""
    d = 1.3
    t = _t(d)
    buf = np.zeros(len(t))
    place(buf, click(0.003), 0.0, 0.9)
    src = 0.6 * saw(glide(220, 55, d, 0.7), d) + 0.5 * noise(d)
    sw = sweep_lp(src, 9000, 150, d)
    e = np.exp(-t / 0.45)
    # Çözünürlük zamanla düşer: önce temiz, sonra bit bit
    k = np.clip(t / 0.6, 0, 1)
    rough = crush(sw, 4, 20)
    sig = (sw * (1 - k) + rough * k) * e
    # Sonda kekeleme (açılıp kapanan kapı)
    gate = np.where((t > 0.55) & (np.floor(t * 28) % 2 == 1), 0.25, 1.0)
    buf += 0.9 * sig * gate
    return room(fade(buf, 0.0003, 0.08), 0.12, 0.6)


def t2_isik_motoru():
    """Işık motoru çarpması: metalik FM 'vınk' aşağı süzülür + kısa bit patlaması + parlak yankı pırıltısı."""
    d = 1.4
    t = _t(d)
    buf = np.zeros(len(t))
    fc = 1800 * (120 / 1800) ** (t / d)
    mod = np.sin(2 * np.pi * np.cumsum(fc * 1.41) / SR) * (6.0 * np.exp(-t / 0.2))
    fm = np.sin(2 * np.pi * np.cumsum(fc) / SR + mod) * np.exp(-t / 0.35)
    buf += 0.7 * fm
    burst = crush(filt(noise(0.15), lo=800, hi=9000), 3, 12) * env(0.15, 0.001, 0.05)
    place(buf, burst, 0.0, 0.6)
    for k in range(6):
        f = ms.midi(96 - k * 2)
        place(buf, sine(f, 0.12) * env(0.12, 0.002, 0.05), 0.05 + k * 0.06, 0.12, pan=(-1) ** k * 0.6)
    return room(fade(buf, 0.0003, 0.1), 0.2, 0.9)


def t3_kekeleme():
    """Takılma (glitch): kısa bir çarpma parçası tekrar tekrar, her seferinde kısalıp alçalarak
    çalınır (bozuk tampon), sonra kesilir."""
    d = 1.2
    grain_d = 0.09
    g = (0.6 * square(glide(700, 300, grain_d, 0.6), grain_d, 0.3) + 0.6 * filt(noise(grain_d), lo=1500)) * env(grain_d, 0.0005, 0.04)
    g = crush(g, 5, 4)
    buf = np.zeros(n_of(d))
    place(buf, click(0.003), 0.0, 0.8)
    at = 0.0
    ln = len(g)
    step = 0
    while at < d - 0.05 and ln > 60:
        seg = g[:ln]
        # her tekrarda bir yarım ton alçalır (yeniden örnekleme)
        rate = 2 ** (-step / 12)
        idx = np.arange(0, len(seg) - 1, rate)
        seg = np.interp(idx, np.arange(len(seg)), seg)
        place(buf, seg, at, 0.8 * (0.92 ** step))
        at += len(seg) / SR
        ln = int(ln * 0.86)
        step += 1
    return room(fade(buf, 0.0003, 0.06), 0.1, 0.5)


def t4_izgara_arpej():
    """Izgara arpeji: tok dijital vuruş + hızlı, aşağı inen kare dalga arpeji (Tron ızgarası), iki
    yana atlayarak dağılır, yankısı uzar."""
    d = 1.6
    buf = np.zeros(n_of(d))
    hit = (saw(glide(160, 45, 0.3, 0.5), 0.3) * 0.5 + sine(glide(110, 40, 0.3, 0.5), 0.3)) * env(0.3, 0.002, 0.1)
    place(buf, sweep_lp(hit, 3000, 200, 0.3), 0.0, 0.8)
    seq = [91, 86, 83, 79, 74, 71, 67, 62, 59, 55, 50, 47]
    at = 0.03
    for k, m in enumerate(seq):
        f = ms.midi(m)
        b = filt(square(f, 0.07, 0.25), hi=5000) * env(0.07, 0.001, 0.03) * 0.5
        place(buf, b, at, 0.5 * (1 - k / 16), pan=(-1) ** k * 0.7)
        at += 0.045
    return room(fade(buf, 0.0003, 0.1), 0.22, 1.0)


def t5_piksel_cozulme():
    """Piksel çözülmesi: kısa parlak kırılma, ardından yüzlerce minik tonlu tane (pikseller) iki
    yana saçılır; seyrelir ve alçalır, her biri bitli."""
    d = 1.6
    buf = np.zeros(n_of(d))
    place(buf, filt(noise(0.02), lo=2500) * env(0.02, 0.0003, 0.008), 0.0, 0.9)
    scale = [0, 2, 4, 7, 9]
    for i in range(160):
        at = r().exponential(0.28)
        if at > d - 0.06:
            continue
        m = 96 - int(at * 22) - 12 * r().integers(0, 2) + scale[r().integers(5)]
        f = ms.midi(m)
        gd = 0.03
        gr = crush(sine(f, gd) * env(gd, 0.0005, 0.012), 4, 3)
        place(buf, gr, at, 0.16 * np.exp(-at / 0.55), pan=r().uniform(-0.9, 0.9))
    return room(fade(buf, 0.0003, 0.08), 0.15, 0.7)


def t6_lazer_kopma():
    """Lazer kopma: keskin lazer 'pyuuu' (tizden peseye hızlı kayan iki ses, hafif koro), kırık bit
    çıtırtısı ve kısa alçak gövde."""
    d = 1.0
    t = _t(d)
    buf = np.zeros(len(t))
    f = 3200 * (160 / 3200) ** np.clip(t / 0.35, 0, 1)
    las = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.6 * np.sin(2 * np.pi * np.cumsum(f * 1.012) / SR)
    buf += 0.5 * las * np.exp(-t / 0.18)
    place(buf, sine(glide(120, 45, 0.25, 0.5), 0.25) * env(0.25, 0.002, 0.08), 0.0, 0.7)
    cr = np.zeros(len(t))
    for _ in range(50):
        at = r().exponential(0.12)
        if at < d - 0.02:
            place(cr, crush(filt(click(0.004), lo=2000), 3, 6), at, r().uniform(0.2, 0.7) * np.exp(-at / 0.2))
    buf += 0.5 * cr
    return room(fade(buf, 0.0003, 0.08), 0.12, 0.6)


def t7_veri_patlamasi():
    """Veri patlaması: hızlı modem cıvıltıları (FM çırpıntıları) ve bip dizileri, bir anda dağılıp
    kesilir; altında yumuşak bir dijital 'tump'."""
    d = 1.1
    buf = np.zeros(n_of(d))
    place(buf, sine(glide(150, 60, 0.2, 0.5), 0.2) * env(0.2, 0.003, 0.07), 0.0, 0.7)
    at = 0.0
    while at < 0.7:
        cd = r().uniform(0.015, 0.04)
        f0 = r().uniform(800, 4000)
        ch = np.sin(2 * np.pi * np.cumsum(np.full(n_of(cd), f0) + 1500 * np.sin(2 * np.pi * 90 * np.arange(n_of(cd)) / SR)) / SR)
        place(buf, ch * env(cd, 0.0005, cd * 0.4), at, 0.3 * (1 - at / 0.8), pan=r().uniform(-0.7, 0.7))
        at += cd + r().uniform(0.0, 0.03)
    return room(fade(buf, 0.0003, 0.08), 0.12, 0.6)


def t8_synth_vurus():
    """Synth vuruşu + dijital kıymıklar: derin, filtresi kapanan testere bas darbesi (Tron'un tok
    vuruşları gibi), üstünde parlak, bitli kıymıklar saçılır."""
    d = 1.5
    buf = np.zeros(n_of(d))
    bass = 0.6 * saw(glide(98, 41, 0.6, 0.6), 0.6) + 0.6 * saw(glide(98.6, 41.3, 0.6, 0.6), 0.6)
    bass = sweep_lp(bass, 4000, 120, 0.6) * env(0.6, 0.002, 0.22)
    place(buf, bass, 0.0, 0.9)
    at = 0.02
    while at < d - 0.1:
        f = ms.midi(int(r().integers(84, 100)))
        sh = crush(square(f, 0.025, 0.2) * env(0.025, 0.0005, 0.01), 3, 4)
        place(buf, sh, at, 0.25 * np.exp(-at / 0.5), pan=r().uniform(-0.8, 0.8))
        at += r().uniform(0.02, 0.07) * (1 + at * 1.3)
    return room(fade(buf, 0.0005, 0.1), 0.14, 0.7)


def t9_halka_mod():
    """Halka modülasyonlu kırılma: gürültü ve tonun çarpımı (metalik, dijital, yabancı), aşağı kayan
    taşıyıcı; kısa ve sert değil, tınlayarak söner."""
    d = 1.2
    t = _t(d)
    carrier = np.sin(2 * np.pi * np.cumsum(2400 * (200 / 2400) ** (t / d)) / SR)
    src = filt(noise(d), lo=300, hi=6000)
    rm = src * carrier * np.exp(-t / 0.3)
    buf = 0.8 * rm
    place(buf, click(0.003), 0.0, 0.8)
    tone = (sine(ms.midi(79), d) + sine(ms.midi(86), d)) * np.exp(-t / 0.5) * 0.15
    buf = buf + crush(tone, 5, 6)
    return room(fade(buf, 0.0003, 0.08), 0.16, 0.8)


def t10_dijital_v2():
    """Dijital (1) inceltilmiş: daha keskin 'çıt', daha bitli ve iki yana açılan doku, piksel blipleri
    stereo ve yankılı; altında çok hafif bir dijital gövde."""
    d = 1.4
    t = _t(d)
    buf = np.zeros(len(t))
    place(buf, click(0.002), 0.0, 1.0)
    place(buf, sine(glide(180, 70, 0.18, 0.5), 0.18) * env(0.18, 0.002, 0.06), 0.0, 0.45)
    tex = crush(filt(noise(0.7), lo=1200, hi=10000), 4, 30) * np.exp(-_t(0.7) / 0.14)
    place(buf, tex, 0.0, 0.45)
    notes = [91, 88, 84, 81, 79, 76, 72, 69, 67, 64, 60]
    at = 0.025
    for k, m in enumerate(notes):
        f = ms.midi(m)
        b = crush((square(f, 0.05, 0.3) * 0.5 + sine(f, 0.05)) * env(0.05, 0.0008, 0.022), 5, 2)
        place(buf, b, at, 0.3 * (1 - k / 15), pan=(-1) ** k * 0.6)
        at += r().uniform(0.035, 0.065)
    return room(fade(buf, 0.0003, 0.1), 0.16, 0.8)


TRON = [("t01_derez", t1_derez), ("t02_isik_motoru", t2_isik_motoru), ("t03_kekeleme", t3_kekeleme),
        ("t04_izgara_arpej", t4_izgara_arpej), ("t05_piksel_cozulme", t5_piksel_cozulme),
        ("t06_lazer_kopma", t6_lazer_kopma), ("t07_veri_patlamasi", t7_veri_patlamasi),
        ("t08_synth_vurus", t8_synth_vurus), ("t09_halka_mod", t9_halka_mod), ("t10_dijital_v2", t10_dijital_v2)]


DESIGNS = [("1_dijital", d1_dijital), ("2_yumusak", d2_yumusak), ("3_voksel", d3_voksel),
           ("4_cam", d4_cam), ("5_buyuk_tiss", d5_buyuk_tiss), ("6_metal", d6_metal)]


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    designs = TRON if "--tron" in sys.argv else DESIGNS
    out.mkdir(parents=True, exist_ok=True)
    import soundfile as sf
    allb = []
    for name, fn in designs:
        ms.rng = np.random.default_rng(sum(map(ord, name)))
        x = normalize(fn(), 0.8)
        sf.write(out / f"carpma_{name}.wav", np.clip(x, -1, 1), SR, subtype="PCM_16")
        allb.append(x if x.ndim == 1 else x.mean(axis=1))
        allb.append(np.zeros(n_of(0.9)))
        print("yazıldı", name)
    sf.write(out / ("tron_hepsi_sirayla.wav" if "--tron" in sys.argv else "carpma_hepsi_sirayla.wav"), np.clip(np.concatenate(allb), -1, 1), SR, subtype="PCM_16")


if __name__ == "__main__":
    main()

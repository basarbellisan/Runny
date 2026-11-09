"""Arabanın motor sesi (döngü) ve zıplayıp yere inme sesi için tasarım denemeleri (oyuna girmez;
dinleyip seçmek için). Dijital / Tron havası ağırlıklı, bir kısmı gerçekçi.
Kullanım: python3 tools/engine_land_designs.py ÇIKIŞ_KLASÖRÜ [SES_GÜNLÜĞÜ]
          python3 tools/engine_land_designs.py ÇIKIŞ_KLASÖRÜ --cars [MODEL=GÜNLÜK ...]  (her arabanın motoru)
Ses günlüğü (oyunun --audtrace AUD/LAND satırları) verilirse her motor ve iniş tasarımı o sürüşün
devir, seviye ve iniş anlarıyla, oyundaki ses ayarlarıyla bir iz olarak da yazılır."""
import re
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_sounds as ms  # noqa: E402
from make_sounds import SR, n_of, sine, glide, env, noise, filt, place, room, fade, click, normalize  # noqa: E402
from smash_sound_designs import crush  # noqa: E402

LOOP = 2.0  # sn; tüm frekanslar 0.5 Hz'in katı: döngü dikişsiz


def r():
    return ms.rng


def _t():
    return np.arange(int(SR * LOOP)) / SR


def _saw(f, t):
    return 2.0 * ((f * t) % 1.0) - 1.0


def _sq(f, t, duty=0.5):
    return np.where(((f * t) % 1.0) < duty, 1.0, -1.0)


def _lp(x, hi):
    return filt(x, hi=hi, circular=True)


# --- Motorlar (2 sn dikişsiz döngü; oyunda devir pitch ile 0.75..1.9) ---

def e1_isik_motoru():
    """Işık motoru (Tron): iki testere + kare, hafif akortsuz, yavaş darbe genişliği; parlak elektrikli vızıltı."""
    t = _t()
    f = 110.0
    pw = 0.5 + 0.2 * np.sin(2 * np.pi * 1.5 * t)
    x = 0.5 * _saw(f, t) + 0.5 * _saw(f * 1.005 if False else 110.5, t) + 0.35 * np.where(((f * 2 * t) % 1.0) < pw, 1.0, -1.0)
    x = _lp(x, 2400) + 0.25 * np.sin(2 * np.pi * 55 * t)
    return normalize(x, 0.8)


def e2_elektrik():
    """Elektrik motoru: temiz dişli uğultusu (220 Hz ve katları) + tiz inverter sesi; yumuşak, sessiz araba."""
    t = _t()
    x = np.sin(2 * np.pi * 220 * t) + 0.5 * np.sin(2 * np.pi * 440 * t) + 0.3 * np.sin(2 * np.pi * 660 * t)
    x += 0.12 * np.sin(2 * np.pi * 1650 * t) * (1 + 0.3 * np.sin(2 * np.pi * 4 * t))
    x += 0.06 * filt(r().uniform(-1, 1, len(t)), lo=2000, hi=6000, circular=True)
    return normalize(x, 0.8)


def e3_synth_bas():
    """Synthwave bası: iki akortsuz testere + alt bas, alçak geçiren, 8 Hz nabız; 'vroom' synth."""
    t = _t()
    x = _saw(55.0, t) + _saw(55.5, t) + 0.8 * np.sin(2 * np.pi * 27.5 * t)
    x = _lp(x, 900)
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * 8.0 * t)
    return normalize(x, 0.8)


def e4_turbin():
    """Türbin: süzülmüş hava gürültüsü + yükselen ıslık tonları; jet gibi, havadar."""
    t = _t()
    air = filt(r().uniform(-1, 1, len(t)), lo=300, hi=3000, circular=True)
    whine = 0.5 * np.sin(2 * np.pi * 880 * t) + 0.3 * np.sin(2 * np.pi * 1320.5 * t) + 0.2 * np.sin(2 * np.pi * 2200 * t)
    x = 0.8 * air + 0.5 * whine + 0.4 * np.sin(2 * np.pi * 110 * t)
    return normalize(x, 0.8)


def e5_dijital_nabiz():
    """Dijital nabız: ateşleme hızında kare dalga darbeleri (90 Hz), bitli; eski oyun konsolu motoru."""
    t = _t()
    x = 0.6 * _sq(90.0, t, 0.25) + 0.4 * _sq(45.0, t, 0.5)
    x = crush(_lp(x, 3000), 4, 6)
    return normalize(_lp(x, 4000), 0.8)


def e6_hibrit():
    """Hibrit: şimdiki yanmalı motorun yumuşatılmış hali + üstünde elektrikli vızıltı; fütüristik araba."""
    base = ms.loop_engine()
    t = np.arange(len(base)) / SR
    whine = np.sin(2 * np.pi * 360 * t) + 0.4 * np.sin(2 * np.pi * 720 * t)
    x = 0.75 * _lp(base, 1400) + 0.25 * whine
    return normalize(x, 0.8)


def e7_hover():
    """Süzülme (anti-yerçekimi): alçak 80 Hz uğultu, titrek, üstünde ince parıltılı kısmiler."""
    t = _t()
    x = np.sin(2 * np.pi * 80 * t) * (0.8 + 0.2 * np.sin(2 * np.pi * 6.0 * t))
    x += 0.3 * np.sin(2 * np.pi * 160 * t) + 0.12 * np.sin(2 * np.pi * 1280 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.5 * t))
    x += 0.08 * np.sin(2 * np.pi * 1920.5 * t)
    return normalize(x, 0.8)


def e8_fm_hirilti():
    """FM hırıltı: FM bas (taşıyıcı 70 Hz, oran 2), hafif hırıltılı; Tron havasında güçlü motor."""
    t = _t()
    mod = np.sin(2 * np.pi * 140 * t) * (2.2 + 0.6 * np.sin(2 * np.pi * 2.0 * t))
    x = np.sin(2 * np.pi * 70 * t + mod) + 0.3 * np.sin(2 * np.pi * 35 * t)
    return normalize(_lp(x, 2500), 0.8)


ENGINES = [("m0_simdiki", None), ("m1_isik_motoru", e1_isik_motoru), ("m2_elektrik", e2_elektrik),
           ("m3_synth_bas", e3_synth_bas), ("m4_turbin", e4_turbin), ("m5_dijital_nabiz", e5_dijital_nabiz),
           ("m6_hibrit", e6_hibrit), ("m7_hover", e7_hover), ("m8_fm_hirilti", e8_fm_hirilti)]


# --- İnişler (tek seferlik) ---

def l1_dijital_tok():
    """Dijital tok: alçak, aşağı inen yumuşak darbe + bitli tık + kısa kare 'tok'."""
    d = 0.45
    x = np.zeros(n_of(d))
    place(x, sine(glide(130, 50, 0.3, 0.5), 0.3) * env(0.3, 0.002, 0.09), 0.0, 0.9)
    place(x, crush(filt(click(0.004), lo=1500), 4, 4), 0.0, 0.5)
    sq = np.sign(sine(glide(320, 200, 0.06, 0.5), 0.06)) * env(0.06, 0.0005, 0.02) * 0.3
    place(x, filt(sq, hi=3000), 0.002, 1.0)
    return fade(room(x, 0.06, 0.3), 0.0003, 0.05)


def l2_yaylanma():
    """Yaylanma: boğuk gövde 'tump' + süspansiyonun kısa yay sesi (hafif 'boing'), gerçekçi ama yumuşak."""
    d = 0.6
    x = np.zeros(n_of(d))
    place(x, normalize(filt(noise(0.3), lo=40, hi=200), 1.0) * env(0.3, 0.002, 0.08), 0.0, 0.8)
    place(x, sine(glide(180, 120, 0.25, 0.5), 0.25) * env(0.25, 0.005, 0.1) * (1 + 0.3 * np.sin(2 * np.pi * 18 * np.arange(n_of(0.25)) / SR)), 0.01, 0.35)
    return fade(room(x, 0.05, 0.3), 0.0003, 0.05)


def l3_synth_vurus():
    """Synth vuruşu (Tron): filtresi kapanan testere bas darbesi + üstünde kısa dijital pırıltı."""
    d = 0.6
    x = np.zeros(n_of(d))
    tt = np.arange(n_of(0.35)) / SR
    bass = (2.0 * ((np.cumsum(np.full(len(tt), 1.0)) / SR * 80) % 1.0) - 1.0)
    bass = filt(bass, hi=900) * env(0.35, 0.002, 0.1)
    place(x, bass, 0.0, 0.8)
    place(x, sine(glide(110, 45, 0.3, 0.5), 0.3) * env(0.3, 0.002, 0.08), 0.0, 0.6)
    for k in range(3):
        place(x, crush(sine(ms.midi(88 - k * 5), 0.04) * env(0.04, 0.0005, 0.015), 4, 3), 0.02 + k * 0.035, 0.15)
    return fade(room(x, 0.1, 0.4), 0.0003, 0.05)


def l4_elektrik_temas():
    """Elektrik teması: kısa elektrik çıtırtısı + alçak darbe; manyetik tekerler yola değmiş gibi."""
    d = 0.5
    x = np.zeros(n_of(d))
    place(x, sine(glide(100, 45, 0.25, 0.5), 0.25) * env(0.25, 0.002, 0.08), 0.0, 0.8)
    zap = filt(noise(0.06), lo=3000, hi=9000) * env(0.06, 0.0005, 0.015) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 120 * np.arange(n_of(0.06)) / SR)))
    place(x, zap, 0.0, 0.5)
    return fade(room(x, 0.06, 0.3), 0.0003, 0.05)


def l5_temiz_agir():
    """Temiz ağır: alt bas darbesi + kısa boğuk 'küt'; lastik çatırtısı ve tıkırtılar yok, sade."""
    d = 0.5
    x = np.zeros(n_of(d))
    place(x, normalize(filt(noise(0.35), lo=30, hi=140, order=3), 1.0) * env(0.35, 0.002, 0.1), 0.0, 0.9)
    place(x, filt(noise(0.1), lo=150, hi=600) * env(0.1, 0.001, 0.03), 0.0, 0.5)
    return fade(room(x, 0.04, 0.3), 0.0003, 0.05)


def l6_piksel_sekme():
    """Piksel sekme: alçak 'dum' + hızla alçalan iki-üç bip (sekiyormuş gibi), oyunsu."""
    d = 0.5
    x = np.zeros(n_of(d))
    place(x, sine(glide(120, 55, 0.25, 0.5), 0.25) * env(0.25, 0.002, 0.07), 0.0, 0.8)
    for k, m in enumerate([76, 71, 67]):
        b = crush(np.sign(sine(ms.midi(m), 0.035)) * env(0.035, 0.0005, 0.012) * 0.4, 4, 3)
        place(x, filt(b, hi=5000), 0.03 + k * 0.045, 0.35 * (1 - k * 0.25))
    return fade(room(x, 0.06, 0.3), 0.0003, 0.05)


def l7_hava_suspansiyon():
    """Havalı süspansiyon: gövde darbesi + kısa hava boşalması 'pşş' (yüksek bant gürültü, hızla sönen)."""
    d = 0.6
    x = np.zeros(n_of(d))
    place(x, normalize(filt(noise(0.3), lo=40, hi=220), 1.0) * env(0.3, 0.002, 0.08), 0.0, 0.8)
    place(x, filt(noise(0.35), lo=2500, hi=9000) * env(0.35, 0.01, 0.12), 0.03, 0.25)
    return fade(room(x, 0.05, 0.3), 0.0003, 0.05)


def l8_manyetik():
    """Manyetik kilit: metalik kısa 'klak' + alçalan uğultu; fütüristik araç yere tutundu."""
    d = 0.6
    x = np.zeros(n_of(d))
    for f, g, dec in [(620, 0.3, 0.06), (1540, 0.15, 0.04), (2900, 0.08, 0.025)]:
        place(x, sine(f, 0.3) * env(0.3, 0.0005, dec), 0.0, g)
    place(x, sine(glide(160, 70, 0.4, 0.5), 0.4) * env(0.4, 0.004, 0.14), 0.0, 0.6)
    return fade(room(x, 0.06, 0.35), 0.0003, 0.05)


LANDS = [("i0_simdiki", None), ("i1_dijital_tok", l1_dijital_tok), ("i2_yaylanma", l2_yaylanma),
         ("i3_synth_vurus", l3_synth_vurus), ("i4_elektrik_temas", l4_elektrik_temas), ("i5_temiz_agir", l5_temiz_agir),
         ("i6_piksel_sekme", l6_piksel_sekme), ("i7_hava_suspansiyon", l7_hava_suspansiyon), ("i8_manyetik", l8_manyetik)]


# --- Her arabaya kendi motoru: seçilen iki sesten (6 hibrit, 8 FM hırıltı) türetilir ---

def _combustion(f0, res):
    """make_sounds.loop_engine'in ayarlı hali: ateşleme f0 (0.5 Hz katı), rezonans res"""
    period = int(SR / f0)
    cycles = int(LOOP * f0)
    t = np.arange(period) / SR
    out = []
    for k in range(cycles):
        amp = (1.0, 0.82, 0.93, 0.78)[k % 4] * (1 + 0.08 * r().standard_normal())
        rr = res * (1 + 0.04 * r().standard_normal())
        burst = (np.exp(-t * 55) * np.sin(2 * np.pi * rr * t) + 0.6 * np.exp(-t * 25) * np.sin(2 * np.pi * 150 * t)
                 + 0.25 * np.exp(-t * 120) * np.sin(2 * np.pi * 2.4 * rr * t))
        out.append(amp * burst)
    s = np.concatenate(out)
    s = np.resize(s, int(SR * LOOP))
    tt = np.arange(len(s)) / SR
    s += 0.45 * np.sin(2 * np.pi * f0 * tt) + 0.2 * np.sin(2 * np.pi * f0 * 0.5 * tt)
    s += 0.18 * filt(r().uniform(-1, 1, len(s)), lo=80, hi=700, circular=True)
    return normalize(filt(s, lo=35, hi=2200, circular=True), 0.8)


def _hibrit(f0, res, whine, whine_mix, lp):
    base = _combustion(f0, res)
    t = np.arange(len(base)) / SR
    w = np.sin(2 * np.pi * whine * t) + 0.4 * np.sin(2 * np.pi * whine * 2 * t)
    return normalize((1 - whine_mix) * _lp(base, lp) + whine_mix * w, 0.8)


def _fm(fc, ratio, index, wobble, sub, lp, chorus=0.0, whine=0.0):
    t = _t()
    out = np.zeros(len(t))
    voices = [fc] if chorus <= 0 else [fc, fc + chorus]
    for f in voices:
        mod = np.sin(2 * np.pi * f * ratio * t) * (index + wobble * np.sin(2 * np.pi * 2.0 * t))
        out += np.sin(2 * np.pi * f * t + mod)
    out /= len(voices)
    out += sub * np.sin(2 * np.pi * fc / 2 * t)
    if whine > 0:
        out += whine * (np.sin(2 * np.pi * 1520 * t) + 0.5 * np.sin(2 * np.pi * 2280 * t))
    return normalize(_lp(out, lp), 0.8)


def c_gezgin():
    """GEZGİN (hibrit ailesi): derin, ağır, tok; vızıltı az"""
    return _hibrit(75.0, 320, 300.0, 0.15, 1100)


def c_latte():
    """LATTE (hibrit ailesi): seçilen hibrit, aynen"""
    ms.rng = np.random.default_rng(sum(map(ord, "m6_hibrit")))
    return e6_hibrit()


def c_gem():
    """GEM (hibrit ailesi): tiz, canlı, çevik; elektrikli vızıltı belirgin"""
    return _hibrit(105.0, 430, 420.0, 0.35, 1800)


def c_dragster():
    """DRAGSTER (FM ailesi): seçilen FM hırıltı, aynen"""
    return e8_fm_hirilti()


def c_dark_rose():
    """DARK ROSE (FM ailesi): pürüzsüz, zarif; hafif koro (iki ses), hırıltı az"""
    return _fm(82.0, 2.0, 1.6, 0.4, 0.25, 2200, chorus=0.5)


def c_falcon():
    """FALCON (FM ailesi): en tiz ve keskin; parlak FM (oran 3), üstünde ince türbin ıslığı"""
    return _fm(95.0, 3.0, 2.4, 0.5, 0.2, 3200, whine=0.06)


CARS = [(2, "GEZGIN", c_gezgin), (8, "LATTE", c_latte), (10, "GEM", c_gem),
        (6, "DRAGSTER", c_dragster), (7, "DARK ROSE", c_dark_rose), (9, "FALCON", c_falcon)]


def mono(x):
    return x if x.ndim == 1 else x.mean(axis=1)


def render_engine(loop, frames, total):
    """Oyundaki gibi: devir = pitch (döngü hızla okunur), seviye doğrusal; -9 dB motor ayarı"""
    n = n_of(total)
    fr = np.array([f for f, _, _ in frames], float) / 60.0
    pitch = np.interp(np.arange(n) / SR, fr, [p for _, p, _ in frames])
    level = np.interp(np.arange(n) / SR, fr, [l for _, _, l in frames])
    pos = np.cumsum(pitch) % len(loop)
    i0 = pos.astype(int)
    frac = pos - i0
    out = loop[i0] * (1 - frac) + loop[(i0 + 1) % len(loop)] * frac
    return out * level * 10 ** (-9.0 / 20)


def render_lands(sfx, lands, total):
    out = np.zeros(n_of(total))
    rng = np.random.default_rng(3)
    for f, s in lands:
        db = -3.0 + 1.0 + 3.0 * (s - 1.0)
        p = rng.uniform(0.95, 1.05)
        idx = np.arange(0, len(sfx) - 1, p)
        x = np.interp(idx, np.arange(len(sfx)), sfx)
        place(out, x * 10 ** (db / 20), f / 60.0, 1.0)
    return out


def cars_main(out, traces):
    """--cars: her arabanın motoru ve (varsa) o arabanın sürüş günlüğüyle izi. traces: model -> günlük"""
    for model, name, fn in CARS:
        ms.rng = np.random.default_rng(sum(map(ord, "car_" + name)))
        x = mono(fn())
        tag = name.lower().replace(" ", "_")
        sf.write(out / f"araba_{model}_{tag}.wav", np.clip(np.tile(x, 2), -1, 1), SR, subtype="PCM_16")
        if model in traces:
            frames, lands = [], []
            for line in open(traces[model]):
                m = re.match(r"AUD f=(\d+) pitch=([\d.]+) level=([\d.]+)", line)
                if m:
                    frames.append((int(m.group(1)), float(m.group(2)), float(m.group(3))))
                m = re.match(r"LAND f=(\d+) strength=([\d.]+)", line)
                if m:
                    lands.append((int(m.group(1)), float(m.group(2))))
            total = frames[-1][0] / 60.0
            land = mono(sf.read(str(Path(__file__).resolve().parent.parent / "audio/sfx_land.wav"))[0])
            sf.write(out / f"iz_araba_{model}.wav", np.clip(render_engine(x, frames, total) + render_lands(land, lands, total), -1, 1), SR, subtype="PCM_16")
        print("yazıldı", name)


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    if "--cars" in sys.argv:
        out.mkdir(parents=True, exist_ok=True)
        traces = {int(a.split("=")[0]): a.split("=")[1] for a in sys.argv[2:] if "=" in a}
        cars_main(out, traces)
        return
    out.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parent.parent
    frames, lands = [], []
    if len(sys.argv) > 2:
        for line in open(sys.argv[2]):
            m = re.match(r"AUD f=(\d+) pitch=([\d.]+) level=([\d.]+)", line)
            if m:
                frames.append((int(m.group(1)), float(m.group(2)), float(m.group(3))))
            m = re.match(r"LAND f=(\d+) strength=([\d.]+)", line)
            if m:
                lands.append((int(m.group(1)), float(m.group(2))))
    total = frames[-1][0] / 60.0 if frames else 0
    cur_engine = mono(sf.read(str(root / "audio/loop_engine.ogg"))[0])
    cur_land = mono(sf.read(str(root / "audio/sfx_land.wav"))[0])
    loops = {}
    for name, fn in ENGINES:
        ms.rng = np.random.default_rng(sum(map(ord, name)))
        x = cur_engine if fn is None else mono(fn())
        loops[name] = x
        sf.write(out / f"motor_{name}.wav", np.clip(np.tile(x, 2), -1, 1), SR, subtype="PCM_16")
    sfxs = {}
    for name, fn in LANDS:
        ms.rng = np.random.default_rng(sum(map(ord, name)))
        x = cur_land if fn is None else normalize(mono(fn()), 0.8)
        sfxs[name] = x
        sf.write(out / f"inis_{name}.wav", np.clip(x, -1, 1), SR, subtype="PCM_16")
    if frames:
        cur_l = render_lands(cur_land, lands, total)
        cur_e = render_engine(cur_engine, frames, total)
        for name, x in loops.items():
            sf.write(out / f"iz_{name}.wav", np.clip(render_engine(x, frames, total) + cur_l, -1, 1), SR, subtype="PCM_16")
        for name, x in sfxs.items():
            sf.write(out / f"iz_{name}.wav", np.clip(cur_e + render_lands(x, lands, total), -1, 1), SR, subtype="PCM_16")
    print("yazıldı", len(loops), "motor,", len(sfxs), "iniş")


if __name__ == "__main__":
    main()

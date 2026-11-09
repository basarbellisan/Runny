"""Arabanın motor sesi (döngü) ve zıplayıp yere inme sesi için tasarım denemeleri (oyuna girmez;
dinleyip seçmek için). Dijital / Tron havası ağırlıklı, bir kısmı gerçekçi.
Kullanım: python3 tools/engine_land_designs.py ÇIKIŞ_KLASÖRÜ [SES_GÜNLÜĞÜ]
          python3 tools/engine_land_designs.py ÇIKIŞ_KLASÖRÜ --cars [MODEL=GÜNLÜK ...]  (her arabanın motoru)
          python3 tools/engine_land_designs.py ÇIKIŞ_KLASÖRÜ --lands2 GÜNLÜK MOTOR.ogg KARE,KARE,..  (iniş, 2. tur; --lands3: 3. tur dijital lastik, +7 dB;
          --lands4: 4. tur gerçekçi lastik, +7 dB)
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


# --- İniş sesleri, ikinci tur (ilk 8'i beğenilmedi): daha dolgun, motorlarla uyumlu yönler ---

def _kick(f0, f1, d, drop=0.04):
    t = np.arange(n_of(d)) / SR
    f = f1 + (f0 - f1) * np.exp(-t / drop)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def n1_kaucuk():
    """Ağır kauçuk: alçak gövde darbesi + lastiğin ezilme sesi (aşağı süzülen orta bant) + 110 ms
    sonra küçük ikinci sekme; gerçekçi ama temiz"""
    d = 0.6
    x = np.zeros(n_of(d))
    place(x, _kick(90, 42, 0.35, 0.05) * env(0.35, 0.002, 0.11), 0.0, 0.9)
    sq = filt(noise(0.12), lo=250, hi=900) * env(0.12, 0.003, 0.04)
    place(x, sq, 0.0, 0.45)
    place(x, _kick(80, 45, 0.2, 0.04) * env(0.2, 0.002, 0.06), 0.11, 0.3)
    return fade(room(x, 0.05, 0.3), 0.0003, 0.05)


def n2_synthwave_tom():
    """Synthwave tom: 80'ler davulu gibi tok bir tom (140 Hz'den inen) + kapılı (gated) yankı"""
    d = 0.5
    x = np.zeros(n_of(d))
    tom = _kick(160, 85, 0.35, 0.06) * env(0.35, 0.001, 0.12) + 0.3 * filt(noise(0.35), lo=200, hi=2500) * env(0.35, 0.001, 0.03)
    place(x, tom, 0.0, 0.9)
    wet = room(x, 0.6, 0.8)
    wet = mono(wet)[:len(x)]
    gate = np.where(np.arange(len(x)) / SR < 0.22, 1.0, np.exp(-(np.arange(len(x)) / SR - 0.22) / 0.02))
    return fade(0.7 * x + 0.5 * wet * gate, 0.0003, 0.03)


def n3_sub_dusus():
    """Sub düşüş: çok derin, temiz bir alt bas 'bum' (55 Hz) + keskin kısa geçiş tıkı; sinematik"""
    d = 0.6
    x = np.zeros(n_of(d))
    place(x, _kick(70, 38, 0.5, 0.08) * env(0.5, 0.002, 0.18), 0.0, 1.0)
    place(x, filt(click(0.003), lo=1200, hi=6000), 0.0, 0.35)
    return fade(x, 0.0003, 0.06)


def n4_sasi():
    """Şasi gümlemesi: içi boş araç gövdesinin tınısı (180 / 265 / 410 Hz kısmileri sönerek) + darbe"""
    d = 0.6
    x = np.zeros(n_of(d))
    place(x, _kick(100, 50, 0.3, 0.05) * env(0.3, 0.002, 0.08), 0.0, 0.8)
    for f, g, dec in [(180, 0.35, 0.12), (265, 0.25, 0.09), (410, 0.15, 0.06)]:
        place(x, sine(f, 0.5) * env(0.5, 0.002, dec), 0.0, g)
    return fade(room(x, 0.06, 0.35), 0.0003, 0.05)


def n5_fm_gumleme():
    """FM gümleme: FM bas darbesi (oran 1.5, modülasyon hızla söner); FM motorlarla aynı dil"""
    d = 0.5
    t = np.arange(n_of(d)) / SR
    f = 45 + 50 * np.exp(-t / 0.05)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph + 3.0 * np.exp(-t / 0.04) * np.sin(ph * 1.5)) * env(d, 0.002, 0.13)
    return fade(room(x, 0.05, 0.3), 0.0003, 0.05)


def n6_hibrit_tok():
    """Hibrit tok: alçak darbe + yanmalı 'pof' (kısa boğuk patlama) + inen elektrik vızıltısı; hibrit motorlarla uyumlu"""
    d = 0.6
    x = np.zeros(n_of(d))
    place(x, _kick(95, 45, 0.3, 0.05) * env(0.3, 0.002, 0.09), 0.0, 0.85)
    place(x, filt(noise(0.08), lo=100, hi=600) * env(0.08, 0.001, 0.025), 0.0, 0.5)
    place(x, sine(glide(520, 260, 0.25, 0.6), 0.25) * env(0.25, 0.003, 0.08), 0.01, 0.12)
    return fade(room(x, 0.05, 0.3), 0.0003, 0.05)


def n7_cift_sekme():
    """Çift sekme: güçlü darbe, ardından iki küçük sekme (tekerlerin yaylanıp yerine oturması)"""
    d = 0.7
    x = np.zeros(n_of(d))
    for at, g in [(0.0, 0.9), (0.13, 0.35), (0.22, 0.15)]:
        place(x, _kick(95, 45, 0.25, 0.045) * env(0.25, 0.002, 0.07), at, g)
        place(x, filt(noise(0.05), lo=150, hi=900) * env(0.05, 0.001, 0.015), at, g * 0.4)
    return fade(room(x, 0.05, 0.3), 0.0003, 0.05)


def n8_kick_hava():
    """Kick + hava: temiz, vuruşlu bir kick (150'den 45 Hz'e) ve kısa havadar hışırtı; müzikal"""
    d = 0.5
    x = np.zeros(n_of(d))
    place(x, _kick(150, 45, 0.35, 0.035) * env(0.35, 0.001, 0.1), 0.0, 0.95)
    place(x, filt(click(0.003), lo=2000), 0.0, 0.3)
    place(x, filt(noise(0.2), lo=1500, hi=7000) * env(0.2, 0.004, 0.06), 0.005, 0.15)
    return fade(room(x, 0.05, 0.3), 0.0003, 0.05)


LANDS2 = [("j0_simdiki", None), ("j1_kaucuk", n1_kaucuk), ("j2_synthwave_tom", n2_synthwave_tom),
          ("j3_sub_dusus", n3_sub_dusus), ("j4_sasi", n4_sasi), ("j5_fm_gumleme", n5_fm_gumleme),
          ("j6_hibrit_tok", n6_hibrit_tok), ("j7_cift_sekme", n7_cift_sekme), ("j8_kick_hava", n8_kick_hava)]


# --- İniş sesleri, üçüncü tur: dijital lastik (orta-tiz ağırlıklı; motorun bas bölgesinin üstünde) ---

def _thump(d=0.15, f0=240, f1=150):
    """Hafif orta darbe (motor basını ezmez)"""
    return sine(glide(f0, f1, d, 0.5), d) * env(d, 0.001, d * 0.25)


def t1_lastik_cigligi():
    """Dijital lastik çığlığı: kısa, aşağı süzülen tiz 'cıyk' (titrek), bitli; altında hafif darbe"""
    d = 0.3
    t = np.arange(n_of(0.14)) / SR
    f = 1500 * (900 / 1500) ** (t / 0.14) * (1 + 0.03 * np.sin(2 * np.pi * 45 * t))
    chirp = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(0.14, 0.002, 0.045)
    x = np.zeros(n_of(d))
    place(x, crush(chirp, 5, 3), 0.0, 0.7)
    place(x, _thump(), 0.0, 0.5)
    return fade(room(x, 0.05, 0.25), 0.0003, 0.04)


def t2_lastik_tokadi():
    """Lastik tokadı: orta bantta sert, bitli bir 'şap' + 90 ms sonra küçük ikinci 'şap' (sekme)"""
    d = 0.35
    x = np.zeros(n_of(d))
    for at, g in [(0.0, 0.9), (0.09, 0.4)]:
        slap = crush(filt(noise(0.05), lo=700, hi=3200) * env(0.05, 0.0005, 0.012), 4, 4)
        place(x, slap, at, g)
        place(x, _thump(0.1), at, g * 0.5)
    return fade(room(x, 0.05, 0.25), 0.0003, 0.04)


def t3_kare_gicirti():
    """Kare dalga gıcırtı: 8 bit lastik gıcırtısı (1.6 kHz'den aşağı), kısa tık ile"""
    d = 0.25
    x = np.zeros(n_of(d))
    t = np.arange(n_of(0.09)) / SR
    f = 1600 * (700 / 1600) ** (t / 0.09)
    sq = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * env(0.09, 0.001, 0.03) * 0.5
    place(x, filt(sq, hi=6000), 0.0, 0.7)
    place(x, filt(click(0.003), lo=1500), 0.0, 0.5)
    place(x, _thump(0.12), 0.0, 0.4)
    return fade(room(x, 0.04, 0.25), 0.0003, 0.03)


def t4_dijital_surtunme():
    """Dijital sürtünme: lastiğin yolu sıyırması gibi kısa tanecikli gürültü, bitli, perdesi iner"""
    d = 0.3
    x = np.zeros(n_of(d))
    for k in range(10):
        g = filt(noise(0.015), lo=1800 - k * 110, hi=5000 - k * 300) * env(0.015, 0.0005, 0.005)
        place(x, crush(g, 4, 3), k * 0.016, 0.6 * (1 - k / 12))
    place(x, _thump(), 0.0, 0.5)
    return fade(room(x, 0.05, 0.25), 0.0003, 0.04)


def t5_lastik_fm():
    """Lastik FM: FM ile 'boyng' — kauçuğun esneyişi gibi kısa, metalik-dijital sekme (taşıyıcı 900 Hz)"""
    d = 0.3
    t = np.arange(n_of(d)) / SR
    f = 600 + 400 * np.exp(-t / 0.05)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph + 2.5 * np.exp(-t / 0.03) * np.sin(1.5 * ph)) * env(d, 0.001, 0.06)
    x = x + 0.5 * np.pad(_thump(), (0, len(x) - n_of(0.15)))
    return fade(room(x, 0.05, 0.25), 0.0003, 0.04)


def t6_piksel_ezilme():
    """Piksel ezilme: kauçuk sıkışıyormuş gibi tiz'den peşe kayan bantlı gürültü 'vıjj', bitli"""
    d = 0.3
    t = np.arange(n_of(0.15)) / SR
    nz = noise(0.15)
    lo = filt(nz, lo=500, hi=1200)
    hi = filt(nz, lo=1800, hi=4000)
    k = np.clip(t / 0.12, 0, 1)
    sw = (hi * (1 - k) + lo * k) * env(0.15, 0.002, 0.05)
    x = np.zeros(n_of(d))
    place(x, crush(sw, 4, 3), 0.0, 0.8)
    place(x, _thump(), 0.0, 0.5)
    return fade(room(x, 0.05, 0.25), 0.0003, 0.04)


def t7_ciglik_tok():
    """Çığlık + tok: kısa tiz lastik çığlığı (titreşimli bant gürültü) + orta tok darbe, bitli"""
    d = 0.3
    t = np.arange(n_of(0.12)) / SR
    scr = filt(noise(0.12), lo=2000, hi=4200) * (0.6 + 0.4 * np.sin(2 * np.pi * 70 * t)) * env(0.12, 0.002, 0.04)
    x = np.zeros(n_of(d))
    place(x, crush(scr, 5, 2), 0.0, 0.6)
    place(x, crush(_thump(0.14, 300, 170), 5, 3), 0.0, 0.7)
    return fade(room(x, 0.05, 0.25), 0.0003, 0.04)


def t8_bit_sekme():
    """Bit sekme: alçalan üç kısa, bitli 'şap' (lastik sekip yerine oturuyor), orta bantta"""
    d = 0.35
    x = np.zeros(n_of(d))
    for k, (at, g) in enumerate([(0.0, 0.9), (0.07, 0.5), (0.12, 0.25)]):
        s = crush(filt(noise(0.03), lo=900 - k * 150, hi=3500 - k * 600) * env(0.03, 0.0005, 0.008), 3, 4)
        place(x, s, at, g)
    place(x, _thump(), 0.0, 0.5)
    return fade(room(x, 0.05, 0.25), 0.0003, 0.04)


LANDS3 = [("k0_simdiki", None), ("k1_lastik_cigligi", t1_lastik_cigligi), ("k2_lastik_tokadi", t2_lastik_tokadi),
          ("k3_kare_gicirti", t3_kare_gicirti), ("k4_dijital_surtunme", t4_dijital_surtunme), ("k5_lastik_fm", t5_lastik_fm),
          ("k6_piksel_ezilme", t6_piksel_ezilme), ("k7_ciglik_tok", t7_ciglik_tok), ("k8_bit_sekme", t8_bit_sekme)]


# --- İniş: gerçekçi lastik sesi (dördüncü tur; dijitalleştirme sonra) ---

def _rubber_hit(d=0.18, lo=70, hi=380, dec=0.045):
    """Kauçuğun asfalta vuruşu: alçak-orta bantta, hızla sönen yoğun gürültü + gövde tınısı"""
    x = filt(noise(d), lo=lo, hi=hi, order=3) * env(d, 0.001, dec)
    x = normalize(x, 1.0)
    body = sine(glide(110, 70, d, 0.6), d) * env(d, 0.002, dec * 1.4)
    return 0.8 * x + 0.5 * body


def _slap(d=0.03):
    """Lastik sırtının yola şaplaması: çok kısa, geniş bantlı"""
    return filt(noise(d), lo=900, hi=4500) * env(d, 0.0005, 0.007)


def _chirp(d=0.14, f0=1500, f1=1150, gain_env=0.05):
    """Dönen tekerin yola değince cıyırdaması: dar bantlı, titrek, perdesi hafif inen ton + gürültü"""
    t = np.arange(n_of(d)) / SR
    jit = filt(r().uniform(-1, 1, len(t)), hi=60) * 40
    f = f0 * (f1 / f0) ** (t / d) + jit
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph)
    tone *= 0.7 + 0.3 * np.sin(2 * np.pi * 32 * t)
    nz = filt(noise(d), lo=f1 * 0.8, hi=f0 * 1.6)
    return (0.7 * tone + 0.6 * normalize(nz, 1.0)) * env(d, 0.004, gain_env)


def _creak(d=0.12):
    """Yay / süspansiyon gıcırtısı: kısa, sürtünmeli, alçalan"""
    t = np.arange(n_of(d)) / SR
    f = 420 * (300 / 420) ** (t / d)
    saw = 2 * ((np.cumsum(f) / SR) % 1.0) - 1
    return filt(saw * (0.6 + 0.4 * np.sin(2 * np.pi * 55 * t)), lo=300, hi=2500) * env(d, 0.01, 0.04)


def g1_tok_lastik():
    """Tok lastik: kauçuğun asfalta tok vuruşu + kısa şaplama; yalın"""
    x = np.zeros(n_of(0.45))
    place(x, _rubber_hit(), 0.0, 0.9)
    place(x, _slap(), 0.0, 0.45)
    return fade(room(x, 0.04, 0.3), 0.0003, 0.05)


def g2_lastik_cirpma():
    """Lastik + cıyırtı: tok vuruş, dönen tekerlerin yola değince kısa 'cıyk'ı"""
    x = np.zeros(n_of(0.5))
    place(x, _rubber_hit(), 0.0, 0.85)
    place(x, _slap(), 0.0, 0.4)
    place(x, _chirp(), 0.008, 0.4)
    return fade(room(x, 0.05, 0.3), 0.0003, 0.05)


def g3_dibe_vurma():
    """Süspansiyon dibe vurma: ağır 'küt' + metal 'tak' + kısa yay gıcırtısı"""
    x = np.zeros(n_of(0.55))
    place(x, _rubber_hit(0.22, 50, 300, 0.06), 0.0, 0.9)
    for f, g, dec in [(780, 0.18, 0.025), (1340, 0.1, 0.018)]:
        place(x, sine(f, 0.12) * env(0.12, 0.0005, dec), 0.004, g)
    place(x, _creak(), 0.05, 0.18)
    return fade(room(x, 0.05, 0.3), 0.0003, 0.05)


def g4_on_arka():
    """Önce ön, sonra arka tekerler: 70 ms arayla iki lastik vuruşu (ikincisi daha ağır)"""
    x = np.zeros(n_of(0.5))
    place(x, _rubber_hit(0.15, 90, 450, 0.035), 0.0, 0.6)
    place(x, _slap(), 0.0, 0.3)
    place(x, _rubber_hit(0.18, 70, 380, 0.045), 0.07, 0.9)
    place(x, _slap(), 0.07, 0.4)
    return fade(room(x, 0.04, 0.3), 0.0003, 0.05)


def g5_sekme():
    """Lastik sekmesi: vuruş, 140 ms sonra küçük bir sekme ve kısa kayma"""
    x = np.zeros(n_of(0.6))
    place(x, _rubber_hit(), 0.0, 0.9)
    place(x, _slap(), 0.0, 0.4)
    place(x, _rubber_hit(0.12, 90, 400, 0.03), 0.14, 0.35)
    place(x, _chirp(0.08, 1300, 1100, 0.025), 0.15, 0.2)
    return fade(room(x, 0.05, 0.3), 0.0003, 0.05)


def g6_kayma():
    """Kayarak iniş: vuruş + lastiğin yolda biraz kayması (300 ms sönen lastik çığlığı)"""
    x = np.zeros(n_of(0.6))
    place(x, _rubber_hit(), 0.0, 0.8)
    place(x, _slap(), 0.0, 0.35)
    place(x, _chirp(0.32, 1450, 1050, 0.11), 0.01, 0.4)
    return fade(room(x, 0.05, 0.3), 0.0003, 0.06)


def g7_yumusak():
    """Yumuşak iniş: boğuk, kauçuksu 'vuump' + çok hafif cıyırtı; tatlı, sert değil"""
    x = np.zeros(n_of(0.5))
    place(x, _rubber_hit(0.25, 60, 260, 0.07), 0.0, 0.9)
    place(x, _chirp(0.1, 1250, 1050, 0.035), 0.012, 0.18)
    return fade(room(x, 0.04, 0.3), 0.0003, 0.05)


def g8_agir_asfalt():
    """Ağır araba asfalta: derin vuruş + tekerlerin şaplaması + gövde tıkırtısı (vida, kapak)"""
    x = np.zeros(n_of(0.55))
    place(x, _rubber_hit(0.22, 45, 320, 0.06), 0.0, 0.95)
    place(x, _slap(0.04), 0.0, 0.5)
    for k in range(4):
        place(x, filt(click(0.003), lo=2000, hi=6000), 0.03 + k * r().uniform(0.015, 0.035), r().uniform(0.1, 0.25))
    return fade(room(x, 0.05, 0.3), 0.0003, 0.05)


LANDS4 = [("g0_simdiki", None), ("g1_tok_lastik", g1_tok_lastik), ("g2_lastik_cirpma", g2_lastik_cirpma),
          ("g3_dibe_vurma", g3_dibe_vurma), ("g4_on_arka", g4_on_arka), ("g5_sekme", g5_sekme),
          ("g6_kayma", g6_kayma), ("g7_yumusak", g7_yumusak), ("g8_agir_asfalt", g8_agir_asfalt)]


def lands2_main(out, trace, engine_file, picks, designs=None, boost_db=0.0):
    """--lands2: yeni iniş sesleri; sürüş günlüğü verilirse seçili inişler (picks: kare listesi) için
    her birinin çevresi (0.7 sn önce, 1.3 sn sonra) art arda, motorla birlikte"""
    frames, lands = [], []
    for line in open(trace):
        m = re.match(r"AUD f=(\d+) pitch=([\d.]+) level=([\d.]+)", line)
        if m:
            frames.append((int(m.group(1)), float(m.group(2)), float(m.group(3))))
        m = re.match(r"LAND f=(\d+) strength=([\d.]+)", line)
        if m:
            lands.append((int(m.group(1)), float(m.group(2))))
    total = frames[-1][0] / 60.0
    eng = render_engine(mono(sf.read(engine_file)[0]), frames, total)
    root = Path(__file__).resolve().parent.parent
    for name, fn in (designs or LANDS2):
        ms.rng = np.random.default_rng(sum(map(ord, name)))
        x = mono(sf.read(str(root / "audio/sfx_land.wav"))[0]) if fn is None else normalize(mono(fn()), 0.8)
        sf.write(out / f"inis_{name}.wav", np.clip(x, -1, 1), SR, subtype="PCM_16")
        track = eng + render_lands(x * 10 ** (boost_db / 20), lands, total)
        parts = []
        for f in picks:
            a = n_of(f / 60.0 - 0.7)
            parts.append(track[a:a + n_of(2.0)])
        reel = np.concatenate(parts)
        # Tavana vurmasın (bozulmasın): tümü birlikte kısılır (motor / iniş dengesi korunur)
        reel = reel * min(1.0, 0.95 / max(np.abs(reel).max(), 1e-6))
        sf.write(out / f"kesit_{name}.wav", np.clip(reel, -1, 1), SR, subtype="PCM_16")
        print("yazıldı", name)


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    if "--lands4" in sys.argv:
        out.mkdir(parents=True, exist_ok=True)
        a = [x for x in sys.argv[2:] if not x.startswith("--lands")]
        lands2_main(out, a[0], a[1], [int(v) for v in a[2].split(",")], LANDS4, 7.0)
        return
    if "--lands2" in sys.argv or "--lands3" in sys.argv:
        out.mkdir(parents=True, exist_ok=True)
        a = [x for x in sys.argv[2:] if not x.startswith("--lands")]
        if "--lands3" in sys.argv:
            lands2_main(out, a[0], a[1], [int(v) for v in a[2].split(",")], LANDS3, 7.0)
        else:
            lands2_main(out, a[0], a[1], [int(v) for v in a[2].split(",")])
        return
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

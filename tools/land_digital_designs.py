"""Gerçekçi lastik iniş seslerini dijitalleştirme denemeleri (oyuna girmez; dinleyip seçmek için).
Lastik karakteri kalır, üstüne ince dijital katman eklenir. Temel: bir arabanın iniş sesi.
Kullanım: python3 tools/land_digital_designs.py ÇIKIŞ_KLASÖRÜ [GÜNLÜK MOTOR.ogg KARE,KARE,..]
Günlük verilirse her işlem seçili inişlerde, motorla birlikte, oyundaki ayarlarla kesit olarak da yazılır."""
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
import engine_land_designs as ed  # noqa: E402
from make_sounds import SR, n_of, filt, normalize, sine  # noqa: E402
from smash_sound_designs import crush  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


def _split(x, at=0.04):
    """Vuruş (ilk 40 ms) ve kuyruk (kayma) arası yumuşak geçişli ayırma maskeleri"""
    n = len(x)
    t = np.arange(n) / SR
    tail = np.clip((t - at) / 0.02, 0.0, 1.0)
    return 1.0 - tail, tail


def d1_hafif_bit(x):
    """Hafif bit: tüm sese hafif bit azaltma, %40 karışım (lastik aynı, kenarları dijital)"""
    return 0.6 * x + 0.4 * crush(x, 6, 2)


def d2_bitli_kayma(x):
    """Bitli kayma: vuruş temiz kalır, yalnız kayma kısmı bitli"""
    hit, tail = _split(x)
    return x * hit + crush(x, 5, 3) * tail


def d3_dijital_parilti(x):
    """Dijital parıltı: sesin üstüne çok hafif, yükselen iki-üç piksel bip"""
    y = x.copy()
    for k, m in enumerate([84, 88, 91]):
        b = crush(np.sign(sine(ed.ms.midi(m), 0.03)) * ed.env(0.03, 0.0005, 0.01) * 0.4, 4, 3)
        ed.place(y, filt(b, hi=7000), 0.03 + k * 0.035, 0.12 * (1 - k * 0.2))
    return y


def d4_dijital_supurme(x):
    """Dijital süpürme: kayma boyunca alçalan, kısık kare dalga süpürmesi"""
    y = x.copy()
    d = 0.25
    t = np.arange(n_of(d)) / SR
    f = 1400 * (500 / 1400) ** (t / d)
    sq = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * ed.env(d, 0.01, 0.08) * 0.3
    ed.place(y, filt(sq, hi=4000), 0.02, 0.25)
    return y


def d5_ornekleme(x):
    """Örnekleme düşürme: retro, hırçın doku (örnek tutma 6); biçim aynı"""
    return 0.45 * x + 0.55 * crush(x, 8, 6)


def d6_halka(x):
    """Hafif halka modülasyonu: kaymaya metalik, dijital bir parıltı (%30)"""
    hit, tail = _split(x)
    t = np.arange(len(x)) / SR
    rm = x * np.sin(2 * np.pi * 1200 * t)
    return x + 0.3 * rm * tail


def d7_kekeleme(x):
    """Kekeleme kuyruğu: vuruş temiz, kayma 30 Hz'de açılıp kapanarak (glitch) söner"""
    hit, tail = _split(x)
    t = np.arange(len(x)) / SR
    gate = np.where(np.floor(t * 30) % 2 == 0, 1.0, 0.25)
    return x * hit + x * tail * gate


def d8_tron_yanki(x):
    """Tron yankısı: iki kısa, bitli, iki yana açılan yankı (uzay hissi)"""
    y = np.zeros(len(x) + n_of(0.25))
    y[:len(x)] += x
    for k, (dt, g) in enumerate([(0.09, 0.35), (0.18, 0.18)]):
        ed.place(y, crush(x, 5, 3), dt, g)
    return y


DESIGNS = [("q0_dijitalsiz", lambda x: x), ("q1_hafif_bit", d1_hafif_bit), ("q2_bitli_kayma", d2_bitli_kayma),
           ("q3_dijital_parilti", d3_dijital_parilti), ("q4_dijital_supurme", d4_dijital_supurme),
           ("q5_ornekleme", d5_ornekleme), ("q6_halka", d6_halka), ("q7_kekeleme", d7_kekeleme),
           ("q8_tron_yanki", d8_tron_yanki)]


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)
    # Temel: LATTE'nin dijitalsiz lastik sesi (oyundaki dosya artık dijital olduğu için tariften)
    import make_sounds as ms
    base = ms._car_land("h1_yumusak_az_kayma")
    reel_args = sys.argv[2:5] if len(sys.argv) > 4 else None
    for name, fn in DESIGNS:
        ed.ms.rng = np.random.default_rng(sum(map(ord, name)))
        x = normalize(fn(base.copy()), 0.8)
        sf.write(out / f"dijital_{name}.wav", np.clip(x, -1, 1), SR, subtype="PCM_16")
    if reel_args:
        trace, engine, picks = reel_args
        designs = [(name, (lambda nm: (lambda: ed.mono(sf.read(str(out / f"dijital_{nm}.wav"))[0])))(name)) for name, _ in DESIGNS]
        ed.lands2_main(out, trace, engine, [int(v) for v in picks.split(",")], designs, 7.0)


if __name__ == "__main__":
    main()

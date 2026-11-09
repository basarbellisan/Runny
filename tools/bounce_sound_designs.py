"""Parçalanmada parçalar sektikçe çalan kısa ses için tasarım denemeleri (oyuna girmez; dinleyip
seçmek için). Tron havası, çarpma sesi 'dijital v2' ile aynı dil.
Kullanım: python3 tools/bounce_sound_designs.py ÇIKIŞ_KLASÖRÜ [SEKME_GÜNLÜĞÜ ÇARPMA_SESİ]
Sekme günlüğü verilirse (oyunun --trace SMASH_HIT satırları) her tasarım o sekmelerle, oyundaki
kurallarla (hıza göre ses, rastgele perde, seyreltme) bir dizi olarak da yazılır."""
import re
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_sounds as ms  # noqa: E402
from make_sounds import SR, n_of, sine, glide, env, noise, filt, place, room, fade, click, normalize  # noqa: E402
from smash_sound_designs import square, crush  # noqa: E402


def r():
    return ms.rng


def b1_piksel_blip():
    """Piksel blip: minicik, bitli kare dalga 'bip' (1.6 kHz)."""
    d = 0.05
    x = crush(filt(square(1600, d, 0.3), hi=7000) * env(d, 0.0005, 0.012), 4, 3)
    return fade(x, 0.0002, 0.01)


def b2_cam_tik():
    """Cam tık: parlak, temiz kısa çınlama (4.2 kHz), bas yok."""
    d = 0.08
    x = (sine(4200, d) + 0.3 * sine(6900, d)) * env(d, 0.0003, 0.018)
    return fade(x, 0.0002, 0.02)


def b3_veri_cit():
    """Veri çıtı: çok kısa filtreli tık + 8 bitlik gürültü kırıntısı."""
    d = 0.03
    x = np.zeros(n_of(d))
    place(x, filt(click(0.003), lo=2000), 0.0, 0.8)
    place(x, crush(filt(noise(0.015), lo=2500, hi=9000), 3, 6) * env(0.015, 0.0003, 0.005), 0.001, 0.5)
    return fade(x, 0.0002, 0.008)


def b4_dijital_tok():
    """Dijital tok: yumuşak, alçalan orta ton (420→250 Hz), bitli; sert değil."""
    d = 0.07
    x = crush(sine(glide(420, 250, d, 0.5), d) * env(d, 0.001, 0.025), 5, 4)
    return fade(x, 0.0003, 0.015)


def b5_fm_ping():
    """FM ping: metalik, kısa Tron 'tinn' (taşıyıcı 2.2 kHz, oran 1.41)."""
    d = 0.09
    t = np.arange(n_of(d)) / SR
    mod = np.sin(2 * np.pi * 2200 * 1.41 * t) * 3.0 * np.exp(-t / 0.02)
    x = np.sin(2 * np.pi * 2200 * t + mod) * env(d, 0.0005, 0.022)
    return fade(x, 0.0002, 0.02)


def b6_mini_lazer():
    """Mini lazer: minicik 'pyu' (2.4 kHz'den 700 Hz'e çok hızlı)."""
    d = 0.04
    x = sine(glide(2400, 700, d, 0.6), d) * env(d, 0.0005, 0.012)
    return fade(x, 0.0002, 0.01)


def b7_bit_tok():
    """8 bit tok: kare dalga kısa vuruş (180 Hz) + tık; eski oyun konsolu gibi."""
    d = 0.05
    x = filt(square(glide(220, 150, d, 0.5), d, 0.5), hi=3000) * env(d, 0.0005, 0.015) * 0.6
    place(x, click(0.002), 0.0, 0.5)
    return fade(x, 0.0002, 0.01)


def b8_bip_bop():
    """Bip-bop: iki hızlı nota (üst, alt), ızgara arpejinin minik hali."""
    d = 0.05
    x = np.zeros(n_of(d))
    for k, m in enumerate([86, 79]):
        f = ms.midi(m)
        place(x, filt(square(f, 0.022, 0.25), hi=6000) * env(0.022, 0.0005, 0.009) * 0.6, k * 0.022, 1.0)
    return fade(x, 0.0002, 0.01)


DESIGNS = [("b1_piksel_blip", b1_piksel_blip), ("b2_cam_tik", b2_cam_tik), ("b3_veri_cit", b3_veri_cit),
           ("b4_dijital_tok", b4_dijital_tok), ("b5_fm_ping", b5_fm_ping), ("b6_mini_lazer", b6_mini_lazer),
           ("b7_bit_tok", b7_bit_tok), ("b8_bip_bop", b8_bip_bop)]


def mono(x):
    return x if x.ndim == 1 else x.mean(axis=1)


def sequence(tick, hits, smash, crash_at, total):
    """Oyundaki kurallarla: hız < 2 sessiz, en az 45 ms arayla, ses = -20 + hız*0.5 dB (-20..-6),
    perde 0.7..1.15 rastgele. Çarpma sesi crash_at'ta."""
    out = np.zeros(n_of(total))
    place(out, mono(smash) * 10 ** (0.0 / 20), crash_at, 1.0)
    rng = np.random.default_rng(5)
    last = -1.0
    for t, v in hits:
        if v < 2.0 or t - last < 0.045:
            continue
        last = t
        db = min(max(-20.0 + v * 0.5, -20.0), -6.0)
        pitch = rng.uniform(0.7, 1.15)
        idx = np.arange(0, len(tick) - 1, pitch)
        tk = np.interp(idx, np.arange(len(tick)), tick)
        place(out, tk * 10 ** (db / 20), crash_at + t, 1.0)
    return out


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    out.mkdir(parents=True, exist_ok=True)
    hits = []
    if len(sys.argv) > 3:
        for line in open(sys.argv[2]):
            m = re.search(r"SMASH_HIT \S+ v=([\d.]+) t=([\d.]+)", line)
            if m:
                hits.append((float(m.group(2)), float(m.group(1))))
        smash, _ = sf.read(sys.argv[3])
    designs = [("b0_simdiki", lambda: mono(sf.read(str(Path(__file__).resolve().parent.parent / "audio/sfx_debris.wav"))[0]))] + DESIGNS
    for name, fn in designs:
        ms.rng = np.random.default_rng(sum(map(ord, name)))
        x = mono(fn())
        x = normalize(x, 0.8)
        sf.write(out / f"sekme_{name}.wav", np.clip(x, -1, 1), SR, subtype="PCM_16")
        if hits:
            seq = sequence(x, hits, smash, 0.8333, 5.2)
            sf.write(out / f"dizi_{name}.wav", np.clip(seq, -1, 1), SR, subtype="PCM_16")
        print("yazıldı", name)


if __name__ == "__main__":
    main()

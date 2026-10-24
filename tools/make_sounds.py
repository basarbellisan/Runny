#!/usr/bin/env python3
"""Oyunun tüm seslerini sıfırdan sentezler (yumuşak / tatlı tarz).

Kullanım:  python3 tools/make_sounds.py
Gerekenler: pip install numpy soundfile

Çıktılar audio/ klasörüne yazılır:
  sfx_*.wav     kısa efektler (mono, 16 bit)
  loop_*.ogg    döngü sesleri: motor, rüzgâr
  music_*.ogg   iki katmanın müziği (aynı tempo ve akorlar; oyun aralarında geçiş yapar)
"""
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "audio"
rng = np.random.default_rng(7)


# --------------------------------------------------------------------------
# Temel yapı taşları
# --------------------------------------------------------------------------

def midi(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=float) - 69.0) / 12.0)


def tone(freq, dur):
    """Frekansı zamanla değişebilen sinüs (freq sabit ya da dizi olabilir)."""
    n = int(dur * SR)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,)) if np.ndim(freq) == 0 else np.asarray(freq)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def glide(f0, f1, dur, curve=1.0):
    x = np.linspace(0, 1, int(dur * SR)) ** curve
    return f0 * (f1 / f0) ** x  # logaritmik kayma kulağa daha doğal gelir


def env(dur, attack=0.005, decay=0.3, sustain=0.0, release=0.0):
    """Atak + üstel sönüm; sustain>0 ise sönüm o seviyede durur."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    e = sustain + (1 - sustain) * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))
    a = int(attack * SR)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    r = int(release * SR)
    if r > 0:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x, cutoff):
    """Tek kutuplu alçak geçiren filtre (cutoff sabit ya da dizi)."""
    c = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    a = 1 - np.exp(-2 * np.pi * c / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def bell(freq, dur, decay=0.6, bright=1.0):
    """Yumuşak çan / kalimba tınısı: kısmi sesler farklı hızda söner."""
    partials = [(1.0, 1.0, 1.0), (2.0, 0.28 * bright, 0.5), (3.01, 0.12 * bright, 0.33), (4.2, 0.05 * bright, 0.22)]
    out = np.zeros(int(dur * SR))
    for ratio, amp, dk in partials:
        out += amp * tone(freq * ratio, dur) * env(dur, 0.003, decay * dk)
    return out


def pluck(freq, dur, decay=0.35):
    """Marimba benzeri yumuşak tını."""
    return (tone(freq, dur) + 0.25 * tone(freq * 4.0, dur) * env(dur, 0.002, 0.05)) * env(dur, 0.004, decay)


def place(buf, sig, start):
    i = int(start * SR)
    j = min(len(buf), i + len(sig))
    if j > i:
        buf[i:j] += sig[: j - i]


def normalize(x, peak=0.8):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def fade(x, fin=0.003, fout=0.02):
    x = x.copy()
    a, b = int(fin * SR), int(fout * SR)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def reverb_ir(seconds=2.2, stereo=True, damp=6000.0):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    chans = []
    for _ in range(2 if stereo else 1):
        ir = rng.normal(0, 1, n) * np.exp(-t * 3.2)
        ir = lowpass(ir, damp)
        ir[: int(0.01 * SR)] *= np.linspace(0, 1, int(0.01 * SR))
        chans.append(ir / np.sqrt(np.sum(ir ** 2)))
    return chans


def convolve(x, ir):
    n = len(x) + len(ir) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]


def add_reverb(x, wet=0.25, seconds=1.4):
    ir = reverb_ir(seconds, stereo=False)[0]
    y = convolve(x, ir)
    out = np.zeros(len(y))
    out[: len(x)] += x
    return out + wet * y


def seamless(x, cross=0.5):
    """Sonu başına çapraz geçişle bindirerek kesintisiz döngü yapar."""
    c = int(cross * SR)
    body = x[:-c].copy()
    w = np.linspace(0, 1, c)
    body[:c] = body[:c] * w + x[-c:] * (1 - w)
    return body


def write_wav(name, x):
    sf.write(OUT / name, np.clip(x, -1, 1), SR, subtype="PCM_16")


def write_ogg(name, x):
    sf.write(OUT / name, np.clip(x, -1, 1), SR, format="OGG", subtype="VORBIS")


# --------------------------------------------------------------------------
# Efektler
# --------------------------------------------------------------------------

def sfx_jump():
    d = 0.22
    s = tone(glide(380, 760, d, 0.6), d) * env(d, 0.006, 0.09)
    s += 0.15 * lowpass(noise(d), 2500) * env(d, 0.01, 0.06)
    return add_reverb(fade(s), 0.15, 0.6)


def sfx_land():
    d = 0.3
    s = tone(glide(150, 52, d, 0.5), d) * env(d, 0.002, 0.09)
    s += 0.35 * lowpass(noise(d), 700) * env(d, 0.001, 0.03)
    return fade(s, 0.001, 0.05)


def sfx_perfect():
    buf = np.zeros(int(1.2 * SR))
    place(buf, bell(midi(79), 1.0, 0.5), 0.0)
    place(buf, bell(midi(84), 1.1, 0.6), 0.09)
    place(buf, 0.5 * bell(midi(88), 1.0, 0.5), 0.18)
    return add_reverb(buf, 0.25)


def sfx_multiplier():
    buf = np.zeros(int(1.0 * SR))
    for k, m in enumerate([72, 76, 79, 84]):
        place(buf, pluck(midi(m), 0.6, 0.25), k * 0.07)
    return add_reverb(buf, 0.25)


def sfx_return():
    buf = np.zeros(int(1.4 * SR))
    for k, m in enumerate([72, 76, 79, 84, 88]):
        place(buf, bell(midi(m), 0.9, 0.45, 0.7), k * 0.075)
    return add_reverb(buf, 0.3)


def sfx_wings():
    d = 0.7
    sweep = glide(300, 2200, d, 0.7)
    n = noise(d)
    s = 0.6 * lowpass(lowpass(n, sweep) - lowpass(n, sweep * 0.4), 2500) * env(d, 0.08, 0.2)
    for k, m in enumerate([72, 74, 76, 79, 81, 84]):
        place(s, 0.35 * pluck(midi(m), 0.5, 0.2), 0.05 + k * 0.045)
    return add_reverb(fade(s, 0.01, 0.1), 0.3)


def sfx_crystal():
    s = bell(midi(84), 0.6, 0.35, 1.2)
    return add_reverb(s, 0.2, 0.8)


def sfx_portal():
    d = 1.3
    s = np.zeros(int(d * SR))
    for ratio, amp in [(1.0, 1.0), (1.5, 0.5), (2.0, 0.4), (2.997, 0.2)]:
        f = glide(220 * ratio, 880 * ratio, d, 0.8)
        trem = 0.75 + 0.25 * np.sin(2 * np.pi * np.linspace(6, 14, len(f)).cumsum() / SR)
        s += amp * tone(f, d) * trem
    s *= env(d, 0.25, 0.6)
    n = noise(d)
    s += 0.5 * lowpass(n, glide(400, 3000, d)) * env(d, 0.3, 0.4)
    place(s, 0.6 * bell(midi(91), 0.8, 0.5), 0.75)
    return add_reverb(fade(s, 0.01, 0.15), 0.35)


def sfx_fall():
    d = 0.7
    f = glide(760, 330, d, 1.2) * (1 + 0.012 * np.sin(2 * np.pi * 7 * np.arange(int(d * SR)) / SR))
    s = tone(f, d) * env(d, 0.03, 0.4)
    return add_reverb(fade(s, 0.01, 0.1), 0.25)


def sfx_crash():
    d = 0.8
    s = tone(glide(120, 40, d, 0.4), d) * env(d, 0.002, 0.15)
    s += 0.6 * lowpass(lowpass(noise(d), glide(1400, 220, d)), 1800) * env(d, 0.002, 0.12)
    s += 0.25 * tone(glide(420, 140, d, 0.8), d) * env(d, 0.01, 0.3)
    return add_reverb(fade(s, 0.001, 0.1), 0.2)


def sfx_energy_low():
    buf = np.zeros(int(0.5 * SR))
    for k in range(2):
        place(buf, tone(midi(81), 0.09) * env(0.09, 0.005, 0.05, 0.6, 0.02), k * 0.14)
    return add_reverb(buf, 0.15, 0.6)


def sfx_game_over():
    buf = np.zeros(int(2.2 * SR))
    for k, m in enumerate([79, 76, 72]):
        place(buf, pluck(midi(m), 0.9, 0.4), k * 0.2)
    place(buf, 0.6 * bell(midi(67), 1.5, 0.8, 0.5), 0.6)
    return add_reverb(buf, 0.35)


# --------------------------------------------------------------------------
# Döngüler
# --------------------------------------------------------------------------

def loop_engine():
    # Elektrikli araba gibi yumuşak bir uğultu. 2 sn içinde tam sayıda
    # periyot olsun ki döngü tıklamasın.
    d = 2.0
    t = np.arange(int(d * SR)) / SR
    trem = 1 + 0.08 * np.sin(2 * np.pi * 4 * t)
    s = (np.sin(2 * np.pi * 110 * t) + 0.35 * np.sin(2 * np.pi * 220 * t)
         + 0.12 * np.sin(2 * np.pi * 330 * t)) * trem
    hiss = lowpass(lowpass(lowpass(noise(d + 0.5), 350), 350), 350)
    s += 0.6 * normalize(seamless(hiss, 0.5), 1.0) * 0.25
    return normalize(s, 0.7)


def loop_wind():
    d = 6.0
    n = noise(d + 1.0)
    t = np.arange(len(n)) / SR
    cut = 500 + 350 * np.sin(2 * np.pi * t / 3.1) + 200 * np.sin(2 * np.pi * t / 1.7)
    s = lowpass(lowpass(n, cut), cut * 1.5)
    return normalize(seamless(s, 1.0), 0.7)


# --------------------------------------------------------------------------
# Müzik: iki katman aynı tempo ve akorları kullanır, oyun aralarında geçiş yapar
# --------------------------------------------------------------------------

BPM = 90
BEAT = 60 / BPM
BAR = 4 * BEAT
BARS = 16
LENGTH = BARS * BAR
#           Fmaj7             G6                Em7               Am7
CHORDS = [[53, 57, 60, 64], [55, 59, 62, 64], [52, 55, 59, 62], [57, 60, 64, 67]]
ROOTS = [41, 43, 40, 45]
PENTA = [72, 74, 76, 79, 81, 84, 86, 88]
RHYTHMS = [
    [1, 0, 1, 0, 1, 1, 0, 0],
    [1, 0, 0, 1, 0, 0, 1, 0],
    [1, 1, 0, 1, 0, 0, 0, 0],
    [0, 0, 1, 0, 1, 0, 1, 1],
    [1, 0, 0, 0, 1, 0, 0, 0],
]


def pad_voice(freq, dur, warm=1.0):
    t = np.arange(int(dur * SR)) / SR
    s = (np.sin(2 * np.pi * freq * t) + np.sin(2 * np.pi * freq * 1.003 * t + 1.0)
         + 0.3 * warm * np.sin(2 * np.pi * freq * 2 * t))
    a = env(dur, 0.6, 10.0, 1.0, 0.8)
    return s * a


def soft_kick():
    d = 0.35
    return tone(glide(95, 42, d, 0.4), d) * env(d, 0.002, 0.12)


def shaker():
    d = 0.08
    return highpass(noise(d), 5000) * env(d, 0.004, 0.025)


def melody(seed, density=1.0):
    r = np.random.default_rng(seed)
    notes = []  # (zaman, midi)
    idx = 3
    for bar in range(BARS):
        rhythm = RHYTHMS[r.integers(len(RHYTHMS))]
        chord = CHORDS[bar % 4]
        for slot, hit in enumerate(rhythm):
            if not hit or r.random() > density:
                continue
            idx = int(np.clip(idx + r.integers(-2, 3), 0, len(PENTA) - 1))
            m = PENTA[idx]
            # Vuruş başında akora uyan notayı tercih et
            if slot == 0 and (m % 12) not in [c % 12 for c in chord]:
                m = min(PENTA, key=lambda p: min(abs(p - c - 12 * k) for c in chord for k in (1, 2)))
            notes.append((bar * BAR + slot * BEAT / 2, m))
    return notes


def render_loop(parts, tail=3.0, wet=0.3):
    """Parçaları birleştir, yankı ekle, kuyruğu başa sararak kesintisiz döngü yap."""
    n = int(LENGTH * SR)
    total = n + int(tail * SR)
    l = np.zeros(total)
    r = np.zeros(total)
    for sig, start, pan in parts:
        gl, gr = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        place(l, sig * gl, start)
        place(r, sig * gr, start)
    irl, irr = reverb_ir(2.4)
    wl = l + wet * convolve(l, irl)[:total]
    wr = r + wet * convolve(r, irr)[:total]
    out = np.stack([wl, wr], axis=1)
    loop = out[:n].copy()
    loop[: total - n] += out[n:]
    return normalize(loop, 0.75)


def music_upper():
    parts = []
    for bar in range(BARS):
        start = bar * BAR
        chord = CHORDS[bar % 4]
        for k, m in enumerate(chord):
            parts.append((0.22 * pad_voice(midi(m), BAR + 0.8), start, -0.3 + 0.2 * k))
        root = midi(ROOTS[bar % 4])
        for beat in (0, 2):
            parts.append((0.5 * pluck(root, BEAT * 2, 0.5), start + beat * BEAT, 0.0))
        if bar >= 4:
            for beat in (0, 2):
                parts.append((0.45 * soft_kick(), start + beat * BEAT, 0.0))
            for e in range(8):
                if e % 2 == 1:
                    parts.append((0.08 * shaker(), start + e * BEAT / 2, 0.4))
        if 4 <= bar < 8:
            # Arpej: akor notaları bir oktav yukarıda
            for e in range(8):
                m = chord[[0, 1, 2, 3, 2, 1, 2, 3][e]] + 12
                parts.append((0.2 * pluck(midi(m), 0.4, 0.2), start + e * BEAT / 2, 0.35))
    for time, m in melody(11):
        if time >= 8 * BAR:
            parts.append((0.32 * pluck(midi(m), 0.7, 0.3), time, -0.25))
            parts.append((0.08 * bell(midi(m + 12), 0.6, 0.3), time, 0.3))
    return render_loop(parts, wet=0.28)


def music_lower():
    parts = []
    for bar in range(BARS):
        start = bar * BAR
        chord = CHORDS[bar % 4]
        for k, m in enumerate(chord):
            parts.append((0.26 * lowpass(pad_voice(midi(m), BAR + 1.2, 0.5), 1800), start, -0.4 + 0.27 * k))
        parts.append((0.35 * pad_voice(midi(ROOTS[bar % 4] - 12) * 2, BAR + 0.6, 0.2), start, 0.0))
    for time, m in melody(23, density=0.45):
        parts.append((0.18 * bell(midi(m), 1.6, 0.9, 0.6), time, 0.4 if m % 2 else -0.4))
    return render_loop(parts, tail=4.0, wet=0.5)


def main():
    OUT.mkdir(exist_ok=True)
    effects = {
        "sfx_jump.wav": sfx_jump, "sfx_land.wav": sfx_land, "sfx_perfect.wav": sfx_perfect,
        "sfx_multiplier.wav": sfx_multiplier, "sfx_return.wav": sfx_return,
        "sfx_wings.wav": sfx_wings, "sfx_crystal.wav": sfx_crystal, "sfx_portal.wav": sfx_portal,
        "sfx_fall.wav": sfx_fall, "sfx_crash.wav": sfx_crash,
        "sfx_energy_low.wav": sfx_energy_low, "sfx_game_over.wav": sfx_game_over,
    }
    for name, fn in effects.items():
        write_wav(name, normalize(fn(), 0.8))
        print("yazıldı", name)
    write_ogg("loop_engine.ogg", loop_engine())
    write_ogg("loop_wind.ogg", loop_wind())
    print("yazıldı döngüler")
    write_ogg("music_upper.ogg", music_upper())
    print("yazıldı music_upper.ogg")
    write_ogg("music_lower.ogg", music_lower())
    print("yazıldı music_lower.ogg")


if __name__ == "__main__":
    main()

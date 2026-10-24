#!/usr/bin/env python3
"""Oyunun tüm seslerini sıfırdan sentezler.

Tarz: minimal, teknolojik, İskandinav. Kuru ve net sesler, kısa yankı,
FM tınıları, minör tonalite, minimal elektronik müzik.

Kullanım:  python3 tools/make_sounds.py
Gerekenler: pip install numpy soundfile

Çıktılar audio/ klasörüne yazılır:
  sfx_*.wav     kısa efektler (mono, 16 bit)
  loop_*.ogg    döngüler: motor, yol (lastik), rüzgâr
  music_*.ogg   iki katmanın müziği (aynı tempo ve akorlar; oyun aralarında geçiş yapar)
"""
from pathlib import Path

import numpy as np
import soundfile as sf

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "audio"
rng = np.random.default_rng(3)


# --------------------------------------------------------------------------
# Yapı taşları (hepsi vektörel, hızlı)
# --------------------------------------------------------------------------

def midi(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=float) - 69.0) / 12.0)


def n_of(dur):
    return int(round(dur * SR))


def phase(freq, dur):
    n = n_of(dur)
    f = np.full(n, float(freq)) if np.ndim(freq) == 0 else np.asarray(freq, dtype=float)[:n]
    return 2 * np.pi * np.cumsum(f) / SR


def sine(freq, dur):
    return np.sin(phase(freq, dur))


def glide(f0, f1, dur, curve=1.0):
    x = np.linspace(0, 1, n_of(dur)) ** curve
    return f0 * (f1 / f0) ** x


def env(dur, attack=0.002, decay=0.1, sustain=0.0, release=0.0):
    n = n_of(dur)
    t = np.arange(n) / SR
    e = sustain + (1 - sustain) * np.exp(-np.maximum(t - attack, 0) / max(decay, 1e-4))
    a = n_of(attack)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    r = n_of(release)
    if r > 0:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def noise(dur):
    return rng.uniform(-1, 1, n_of(dur))


def filt(x, lo=None, hi=None, order=2, circular=False):
    """FFT ile Butterworth benzeri filtre. circular=True döngüleri kesintisiz tutar."""
    n = len(x)
    size = n if circular else 1 << (2 * n - 1).bit_length()
    spec = np.fft.rfft(x, size)
    f = np.fft.rfftfreq(size, 1 / SR)
    g = np.ones_like(f)
    if hi is not None:
        g /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo is not None:
        with np.errstate(divide="ignore"):
            g /= np.sqrt(1 + (lo / np.maximum(f, 1e-6)) ** (2 * order))
    return np.fft.irfft(spec * g, size)[:n]


def fm(freq, dur, ratio=2.0, index=1.5, index_decay=0.08, amp_decay=0.25, attack=0.002):
    """İki operatörlü FM: cam gibi, temiz tınılar."""
    n = n_of(dur)
    t = np.arange(n) / SR
    idx = index * np.exp(-t / max(index_decay, 1e-4))
    s = np.sin(2 * np.pi * freq * t + idx * np.sin(2 * np.pi * freq * ratio * t))
    return s * env(dur, attack, amp_decay)


def saw_pad(freq, dur, bright=6.0, harmonics=18, detune=0.004):
    """Toplamalı testere dalga (ses ötesi frekanslar olmadan), yumuşak açılan."""
    n = n_of(dur)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for voice, d in enumerate((1 - detune, 1 + detune)):
        f = freq * d
        for k in range(1, harmonics + 1):
            if f * k > SR / 2.2:
                break
            out += (np.exp(-k / bright) / k) * np.sin(2 * np.pi * f * k * t + voice * k)
    return out * env(dur, 0.35, 99.0, 1.0, 0.5)


def place(buf, sig, start, gain=1.0, pan=0.0):
    """Mono ya da stereo tampona sinyal ekler. pan: -1 sol, +1 sağ."""
    i = int(round(start * SR))
    j = min(len(buf), i + len(sig))
    if j <= i:
        return
    s = sig[: j - i] * gain
    if buf.ndim == 1:
        buf[i:j] += s
    else:
        buf[i:j, 0] += s * np.cos((pan + 1) * np.pi / 4)
        buf[i:j, 1] += s * np.sin((pan + 1) * np.pi / 4)


def room_ir(seconds=0.9, bright=5000.0, decay=4.5, stereo=False):
    n = n_of(seconds)
    t = np.arange(n) / SR
    chans = []
    for _ in range(2 if stereo else 1):
        ir = filt(rng.normal(0, 1, n), hi=bright) * np.exp(-t * decay)
        ir[: n_of(0.004)] *= np.linspace(0, 1, n_of(0.004))
        chans.append(ir / np.sqrt(np.sum(ir ** 2)))
    return chans


def convolve(x, ir):
    n = len(x) + len(ir) - 1
    size = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:n]


def room(x, wet=0.12, seconds=0.6):
    y = convolve(x, room_ir(seconds)[0])
    out = y * wet
    out[: len(x)] += x
    return out


def fade(x, fin=0.001, fout=0.01):
    x = x.copy()
    a, b = n_of(fin), n_of(fout)
    if a:
        x[:a] *= np.linspace(0, 1, a)
    if b:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def normalize(x, peak=0.8):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def click(dur=0.004):
    return filt(noise(dur), lo=2000) * env(dur, 0.0002, 0.0012)


def write_wav(name, x):
    sf.write(OUT / name, np.clip(x, -1, 1), SR, subtype="PCM_16")


def write_ogg(name, x):
    # libsndfile uzun Vorbis dosyalarını tek seferde yazarken çökebiliyor; parça parça yaz
    x = np.clip(x, -1, 1)
    channels = 1 if x.ndim == 1 else x.shape[1]
    with sf.SoundFile(OUT / name, "w", SR, channels, format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(x), SR):
            f.write(x[i:i + SR])


# --------------------------------------------------------------------------
# Araba sesleri
# --------------------------------------------------------------------------

def loop_engine():
    """4 silindirli motor: her ateşleme, rezonanslı kısa bir darbe.
    2 sn'de tam sayıda devir olduğu için döngü kesintisizdir. Devir,
    oyunda pitch_scale ile değiştirilir."""
    f0 = 90.0                       # ateşleme frekansı (Hz)
    period = int(SR / f0)           # 490 örnek
    cycles = int(2.0 * f0)
    t = np.arange(period) / SR
    out = []
    for k in range(cycles):
        # Silindirler birbirinden biraz farklı + küçük rastgelelik = canlı motor
        amp = (1.0, 0.82, 0.93, 0.78)[k % 4] * (1 + 0.08 * rng.standard_normal())
        res = 380 * (1 + 0.04 * rng.standard_normal())
        burst = (np.exp(-t * 55) * np.sin(2 * np.pi * res * t) + 0.6 * np.exp(-t * 25) * np.sin(2 * np.pi * 150 * t)
                 + 0.25 * np.exp(-t * 120) * np.sin(2 * np.pi * 2.4 * res * t))
        out.append(amp * burst)
    s = np.concatenate(out)
    tt = np.arange(len(s)) / SR
    s += 0.45 * np.sin(2 * np.pi * f0 * tt) + 0.2 * np.sin(2 * np.pi * f0 * 0.5 * tt)
    s += 0.18 * filt(rng.uniform(-1, 1, len(s)), lo=80, hi=700, circular=True)   # emme/egzoz hışırtısı
    s = filt(s, lo=35, hi=2200, circular=True)
    return normalize(s, 0.8)


def loop_road():
    """Lastiklerin yolda yuvarlanma uğultusu."""
    d = 2.0
    n = n_of(d)
    t = np.arange(n) / SR
    rumble = filt(rng.uniform(-1, 1, n), lo=40, hi=260, order=3, circular=True)
    hiss = filt(rng.uniform(-1, 1, n), lo=900, hi=2600, circular=True)
    tread = 1 + 0.15 * np.sin(2 * np.pi * 11 * t)  # diş dokusu (2 sn'de tam 22 devir)
    s = (normalize(rumble, 1.0) + 0.18 * normalize(hiss, 1.0)) * tread
    return normalize(s, 0.75)


def sfx_land():
    """Tekerlekler yere değince: tok darbe + lastik cıyaklaması."""
    d = 0.4
    body = sine(glide(115, 48, d, 0.5), d) * env(d, 0.001, 0.07)
    impact = filt(noise(d), hi=900) * env(d, 0.0005, 0.025)
    squeal_env = env(d, 0.004, 0.06)
    squeal = 0.5 * filt(noise(d), lo=1400, hi=3200, order=3) * squeal_env
    squeal += 0.12 * sine(glide(2100, 1700, d), d) * squeal_env
    s = body + 0.7 * impact + 0.45 * squeal
    return fade(room(s, 0.06, 0.4), 0.0005, 0.04)


# --------------------------------------------------------------------------
# Efektler: arayüz sesleri gibi kısa, temiz, hassas
# --------------------------------------------------------------------------

def blip(m, dur=0.07, harm=0.2):
    f = midi(m)
    return (sine(f, dur) + harm * sine(2 * f, dur)) * env(dur, 0.001, dur * 0.35)


def sfx_jump():
    d = 0.12
    s = sine(glide(520, 1040, d, 0.7), d) * env(d, 0.001, 0.035) + 0.5 * np.pad(click(), (0, n_of(d) - n_of(0.004)))
    return room(fade(s), 0.08, 0.4)


def sfx_perfect():
    buf = np.zeros(n_of(0.9))
    place(buf, fm(midi(81), 0.4, 3.5, 1.8, 0.05, 0.12), 0.0)
    place(buf, fm(midi(88), 0.5, 3.5, 1.8, 0.05, 0.16), 0.1)
    return room(buf, 0.15, 0.8)


def sfx_multiplier():
    buf = np.zeros(n_of(0.6))
    for k, m in enumerate([81, 84, 88]):
        place(buf, blip(m, 0.07), k * 0.05)
    return room(buf, 0.1, 0.5)


def sfx_return():
    buf = np.zeros(n_of(1.0))
    for k, m in enumerate([69, 76, 81, 84, 88]):
        place(buf, blip(m, 0.08), k * 0.045)
    for m in (69, 76, 84):
        place(buf, fm(midi(m), 0.6, 2.0, 1.0, 0.1, 0.25), 0.25, 0.35)
    return room(buf, 0.15, 0.8)


def sfx_wings():
    """Mekanik açılma: iki servo tıkı, filtreli hava, yükselen sinüs."""
    d = 0.6
    buf = np.zeros(n_of(d))
    for at in (0.0, 0.11, 0.2):
        place(buf, click(0.006), at, 0.9)
    n = noise(d)
    e = env(d, 0.05, 0.12)
    air = filt(n, lo=400, hi=1200) * np.linspace(1, 0, n_of(d)) + filt(n, lo=1500, hi=4000) * np.linspace(0, 1, n_of(d))
    buf += 0.35 * air * e
    buf += 0.35 * np.sin(phase(glide(300, 900, d, 0.6), d) + 0.8 * np.sin(phase(glide(600, 1800, d, 0.6), d))) * env(d, 0.02, 0.15)
    place(buf, blip(88, 0.08), 0.32, 0.6)
    return room(fade(buf, 0.001, 0.05), 0.1, 0.5)


def sfx_crystal():
    return room(fm(midi(88), 0.25, 3.0, 1.6, 0.03, 0.06), 0.12, 0.6)


def sfx_portal():
    """Yükselen tını + hava, sonunda 'kilitlenme' sesi."""
    d = 1.0
    n = n_of(d)
    ramp = np.linspace(0, 1, n)
    nz = noise(d)
    riser = filt(nz, lo=300, hi=1500) * (1 - ramp) + filt(nz, lo=1500, hi=6000) * ramp
    s = 0.35 * riser * ramp ** 1.5
    s += 0.45 * np.sin(phase(glide(160, 1280, d, 1.4), d)) * (0.2 + 0.8 * ramp) * (1 - ramp ** 8)
    s += 0.2 * np.sin(phase(glide(240, 1920, d, 1.4), d)) * ramp
    buf = np.zeros(n_of(1.5))
    place(buf, s, 0.0)
    place(buf, fm(midi(88), 0.4, 2.0, 2.0, 0.05, 0.12), 0.95)
    place(buf, sine(glide(90, 45, 0.3), 0.3) * env(0.3, 0.001, 0.08), 0.95, 0.8)
    return room(buf, 0.12, 0.7)


def sfx_fall():
    """Güç kesilmesi gibi alçalan ton."""
    d = 0.45
    f = glide(900, 220, d, 0.8)
    s = np.sin(phase(f, d) + 0.6 * np.sin(phase(f * 2, d))) * env(d, 0.002, 0.18)
    return room(fade(s, 0.001, 0.05), 0.1, 0.5)


def sfx_explosion():
    """Kısa, tok patlama: alt frekans darbesi + kapanan gürültü + çıtırtılar."""
    d = 1.2
    n = n_of(d)
    boom = sine(glide(75, 28, d, 0.5), d) * env(d, 0.002, 0.35)
    knock = sine(glide(260, 90, d, 0.4), d) * env(d, 0.001, 0.05)
    roar = filt(noise(d), hi=2500) * env(d, 0.003, 0.18)
    roar = filt(roar, hi=900) * 0.6 + roar * 0.4
    crackle = np.zeros(n)
    for _ in range(40):
        at = rng.uniform(0.02, 0.7)
        place(crackle, click(0.005), at, rng.uniform(0.2, 0.7) * (1 - at))
    held = np.repeat(noise(d)[::18], 18)[:n]               # dijital doku
    s = boom + 0.4 * knock + 0.7 * roar + 0.5 * crackle + 0.15 * filt(held, hi=4000) * env(d, 0.001, 0.08)
    return fade(room(s, 0.15, 0.9), 0.0005, 0.1)


def sfx_energy_low():
    buf = np.zeros(n_of(0.4))
    f = 880.0
    for k in range(2):
        b = (sine(f, 0.07) + 0.3 * sine(3 * f, 0.07) + 0.12 * sine(5 * f, 0.07)) * env(0.07, 0.002, 0.05, 0.5, 0.01)
        place(buf, b, k * 0.12)
    return room(buf, 0.06, 0.4)


def sfx_game_over():
    buf = np.zeros(n_of(1.6))
    for k, m in enumerate([81, 76, 69]):
        place(buf, fm(midi(m), 0.5, 2.0, 0.8, 0.1, 0.18), k * 0.16)
    place(buf, sine(glide(70, 40, 0.8), 0.8) * env(0.8, 0.002, 0.3), 0.48, 0.7)
    return room(buf, 0.15, 0.9)


def loop_wind():
    d = 6.0
    n = n_of(d)
    t = np.arange(n) / SR
    base = filt(rng.uniform(-1, 1, n), lo=150, hi=900, circular=True)
    high = filt(rng.uniform(-1, 1, n), lo=1200, hi=3500, circular=True)
    # Yavaş dalgalanma; periyotlar 6 sn'ye tam bölünür
    mod = 0.7 + 0.3 * np.sin(2 * np.pi * t / 3.0) * np.sin(2 * np.pi * t / 2.0)
    s = (normalize(base, 1.0) + 0.25 * normalize(high, 1.0)) * mod
    return normalize(s, 0.7)


# --------------------------------------------------------------------------
# Müzik: minimal elektronik, La minör, 122 BPM
# --------------------------------------------------------------------------

BPM = 122
BEAT = 60 / BPM
BAR = 4 * BEAT
BARS = 32
LENGTH = BARS * BAR
# Her akor 2 ölçü: Am(add9) - Fadd9 - Cmaj7 - Gadd9
CHORDS = [[57, 60, 64, 71], [53, 57, 60, 67], [55, 60, 64, 71], [55, 59, 62, 69]]
ROOTS = [33, 29, 36, 31]
ARP = [0, 2, 1, 3, 2, 0, 3, 1, 0, 2, 3, 1, 2, 3, 1, 2]
# Kısa, akılda kalan motif: (16'lık konum, nota)
MOTIF = [[(0, 76), (6, 74), (8, 72), (14, 71)],
         [(0, 72), (6, 71), (8, 69), (12, 67)],
         [(0, 71), (6, 72), (8, 76), (14, 74)],
         [(0, 74), (6, 71), (8, 69), (12, 71)]]


def chord_at(bar):
    return (bar // 2) % 4


def kick():
    d = 0.3
    body = sine(glide(160, 46, d, 0.35), d) * env(d, 0.001, 0.13)
    knock = sine(glide(420, 180, d, 0.5), d) * env(d, 0.001, 0.02)
    return body + 0.25 * knock + 0.3 * np.pad(click(), (0, n_of(d) - n_of(0.004)))


def hat(open_=False):
    d = 0.18 if open_ else 0.05
    return filt(noise(d), lo=7000) * env(d, 0.0005, 0.06 if open_ else 0.012)


def rim():
    d = 0.05
    return (0.6 * sine(1900, d) + filt(noise(d), lo=1500, hi=5000)) * env(d, 0.0005, 0.008)


def bass_note(m, dur=0.22):
    f = midi(m)
    # Üst harmonikler, basın telefon hoparlöründe de duyulmasını sağlar
    return (sine(f, dur) + 0.35 * sine(2 * f, dur) + 0.18 * sine(3 * f, dur) + 0.08 * sine(4 * f, dur)) \
        * env(dur, 0.003, 0.12, 0.0, 0.02)


def sidechain(kick_times, depth=0.6, release=0.12):
    n = n_of(LENGTH)
    t = np.arange(n) / SR
    duck = np.ones(n)
    for kt in kick_times:
        i = n_of(kt)
        j = min(n, i + n_of(release * 5))
        duck[i:j] = np.minimum(duck[i:j], 1 - depth * np.exp(-(t[i:j] - kt) / release))
    return duck


def ping_pong(x, delay=3 * BEAT / 4, fb=0.35, repeats=4):
    """Stereo yankı: tekrarlar sağ-sol gider."""
    d = n_of(delay)
    out = np.zeros((len(x) + d * repeats, 2))
    out[: len(x), 0] += x
    out[: len(x), 1] += x
    for r in range(1, repeats + 1):
        ch = r % 2
        out[d * r: d * r + len(x), ch] += x * fb ** r
    return out


def mixdown(stems, tail=3.0, reverb=(0.18, 1.3)):
    """Stem'leri topla, oda yankısı ekle, kuyruğu başa sararak kesintisiz döngü yap."""
    n = n_of(LENGTH)
    total = n + n_of(tail)
    mix = np.zeros((total, 2))
    for s in stems:
        m = min(total, len(s))
        mix[:m] += s[:m]
    wet, secs = reverb
    irs = room_ir(secs, 6000, 3.0, stereo=True)
    for ch in range(2):
        mix[:, ch] += wet * convolve(mix[:, ch], irs[ch])[:total]
    loop = mix[:n].copy()
    loop[: total - n] += mix[n:]
    loop = np.tanh(1.3 * loop / np.max(np.abs(loop))) / np.tanh(1.3)  # hafif doygunluk, toparlar
    return normalize(loop, 0.85)


def music_upper():
    total = n_of(LENGTH + 3.0)
    drums = np.zeros((total, 2))
    bass = np.zeros((total, 2))
    pad = np.zeros((total, 2))
    arp = np.zeros(total)
    keys = np.zeros((total, 2))
    kick_times = []

    for bar in range(BARS):
        b0 = bar * BAR
        c = chord_at(bar)
        breakdown = 24 <= bar < 28
        # Davul
        if not breakdown:
            for beat in range(4):
                place(drums, kick(), b0 + beat * BEAT, 0.95)
                kick_times.append(b0 + beat * BEAT)
                place(drums, hat(), b0 + (beat + 0.5) * BEAT, 0.32, 0.25)
                for s16 in (0.25, 0.75):
                    place(drums, hat(), b0 + (beat + s16) * BEAT, 0.09, -0.3)
            if bar >= 16:
                for beat in (1, 3):
                    place(drums, rim(), b0 + beat * BEAT, 0.28, -0.15)
                place(drums, hat(True), b0 + 3.5 * BEAT, 0.16, 0.3)
        elif bar == 27:
            # Dönüş öncesi kısa yükselen hava
            riser = filt(noise(BAR), lo=2000) * np.linspace(0, 1, n_of(BAR)) ** 2
            place(drums, riser, b0, 0.15)
        # Bas: her vuruşun arasında (offbeat) nabız
        if not breakdown:
            for beat in range(4):
                place(bass, bass_note(ROOTS[c]), b0 + (beat + 0.5) * BEAT, 0.55)
        # Pad: her akor değişiminde
        if bar % 2 == 0:
            bright = 3.0 if bar < 8 else (5.0 if bar < 16 else 7.0)
            for k, m in enumerate(CHORDS[c]):
                place(pad, saw_pad(midi(m), 2 * BAR + 0.4, bright), b0, 0.07, -0.5 + k / 3)
        # Arpej: 16'lıklar, akor notaları bir oktav yukarıda
        if bar >= 8:
            idx = 1.2 if bar < 16 else 2.2
            for s in range(16):
                m = CHORDS[c][ARP[s]] + 12
                place(arp, fm(midi(m), 0.2, 2.0, idx, 0.03, 0.07), b0 + s * BEAT / 4, 0.22 if s % 4 == 0 else 0.15)
        # Motif
        if bar >= 16 and bar % 2 == 0:
            for pos, m in MOTIF[c]:
                place(keys, fm(midi(m), 0.6, 1.0, 1.0, 0.15, 0.3) + 0.2 * fm(midi(m), 0.6, 14.0, 0.6, 0.01, 0.05),
                      b0 + pos * BEAT / 4, 0.32, 0.15)

    duck = sidechain(kick_times)
    duck = np.concatenate([duck, np.ones(total - len(duck))])[:, None]
    echoes = ping_pong(arp)[:total]
    stems = [drums, bass * duck, pad * duck, echoes * duck[: len(echoes)], keys]
    return mixdown(stems, reverb=(0.14, 1.1))


def music_lower():
    """Alt katman: aynı akorlar, davulsuz, daha karanlık ve derin."""
    total = n_of(LENGTH + 4.0)
    perc = np.zeros((total, 2))
    low = np.zeros((total, 2))
    pad = np.zeros((total, 2))
    arp = np.zeros(total)
    keys = np.zeros((total, 2))

    for bar in range(BARS):
        b0 = bar * BAR
        c = chord_at(bar)
        # Kalp atışı gibi derin vuruş (yarım tempo) ve saat tıkırtısı
        place(perc, sine(glide(70, 40, 0.5), 0.5) * env(0.5, 0.004, 0.18), b0, 0.6)
        for s in range(16):
            accent = 0.07 if s % 4 == 2 else 0.035
            place(perc, filt(noise(0.02), lo=5000, hi=10000) * env(0.02, 0.0003, 0.004), b0 + s * BEAT / 4, accent, 0.6 if s % 2 else -0.6)
        if bar % 2 == 0:
            for k, m in enumerate(CHORDS[c]):
                place(pad, saw_pad(midi(m - 12), 2 * BAR + 0.6, 2.2, 10), b0, 0.09, -0.6 + 0.4 * k)
            f = midi(ROOTS[c] + 12)
            sub = (sine(f, 2 * BAR) + 0.15 * sine(2 * f, 2 * BAR)) * env(2 * BAR, 0.3, 99, 1.0, 0.4)
            place(low, sub, b0, 0.45)
        # Yavaş, koyu arpej (8'likler)
        for s in range(8):
            m = CHORDS[c][ARP[s * 2]]
            place(arp, fm(midi(m), 0.4, 2.0, 0.6, 0.06, 0.16), b0 + s * BEAT / 2, 0.16)
        if bar % 4 == 0:
            place(keys, fm(midi(CHORDS[c][3] + 12), 1.2, 3.5, 1.2, 0.08, 0.5), b0 + 2 * BEAT, 0.12, 0.4)

    stems = [perc, low, pad, ping_pong(arp, BEAT * 0.75, 0.4, 5)[:total], keys]
    return mixdown(stems, tail=4.0, reverb=(0.22, 1.8))


# --------------------------------------------------------------------------
# Uçak sesleri (uçuş modu)
# --------------------------------------------------------------------------

def loop_plane():
    """Pervaneli küçük uçak: yumuşak harmonik uğultu + pervane vuruşu.
    2 sn'de tam sayıda periyot: döngü kesintisiz, perde pitch_scale ile değişir."""
    d = 2.0
    n = n_of(d)
    t = np.arange(n) / SR
    f0 = 75.0
    # Üst harmonikler ağır basar: telefon hoparlöründe de duyulsun
    drone = sum(a * np.sin(2 * np.pi * f0 * k * t + k) for k, a in
                [(1, 0.3), (2, 0.5), (3, 0.5), (4, 0.35), (5, 0.25), (6, 0.2), (8, 0.12)])
    # Pervane kanatlarının havayı dövmesi: 40 Hz'lik "pırr"
    chop = filt(rng.uniform(-1, 1, n), lo=180, hi=1300, circular=True)
    chop *= 0.45 + 0.55 * np.abs(np.sin(np.pi * 40.0 * t)) ** 3
    s = normalize(drone, 1.0) * 0.8 + normalize(chop, 1.0) * 0.4
    s = filt(s, lo=40, hi=1800, circular=True)
    return normalize(s, 0.8)


def loop_climb():
    """Yükselirken üstüne binen katman: türbin ıslığı ve hızlı hava akışı."""
    d = 2.0
    n = n_of(d)
    t = np.arange(n) / SR
    vib = 0.004 * np.sin(2 * np.pi * 5.0 * t)
    whine = np.sin(2 * np.pi * 1100.0 * t * (1 + vib)) + 0.3 * np.sin(2 * np.pi * 1650.0 * t)
    air = filt(rng.uniform(-1, 1, n), lo=1500, hi=5000, circular=True)
    s = normalize(whine, 1.0) * 0.35 + normalize(air, 1.0) * 0.5
    s += 0.4 * normalize(filt(rng.uniform(-1, 1, n), lo=300, hi=900, circular=True), 1.0)
    return normalize(s, 0.75)


def sfx_climb():
    """Yükselmeye başlarken: kısa, yükselen hava sesi."""
    d = 0.9
    n = n_of(d)
    ramp = np.linspace(0, 1, n)
    nz = noise(d)
    air = filt(nz, lo=300, hi=1200) * (1 - ramp) + filt(nz, lo=1200, hi=4500) * ramp
    tone = np.sin(phase(glide(260, 780, d, 0.8), d))
    s = (0.7 * air + 0.25 * tone) * env(d, 0.18, 0.3)
    return room(fade(s, 0.005, 0.15), 0.12, 0.6)


def main():
    OUT.mkdir(exist_ok=True)
    effects = {
        "sfx_jump.wav": sfx_jump, "sfx_land.wav": sfx_land, "sfx_perfect.wav": sfx_perfect,
        "sfx_multiplier.wav": sfx_multiplier, "sfx_return.wav": sfx_return,
        "sfx_wings.wav": sfx_wings, "sfx_crystal.wav": sfx_crystal, "sfx_portal.wav": sfx_portal,
        "sfx_fall.wav": sfx_fall, "sfx_explosion.wav": sfx_explosion,
        "sfx_energy_low.wav": sfx_energy_low, "sfx_game_over.wav": sfx_game_over,
    }
    for name, fn in effects.items():
        write_wav(name, normalize(fn(), 0.8))
    write_ogg("loop_engine.ogg", loop_engine())
    write_ogg("loop_road.ogg", loop_road())
    write_ogg("loop_wind.ogg", loop_wind())
    print("efektler ve döngüler yazıldı")
    write_ogg("music_upper.ogg", music_upper())
    write_ogg("music_lower.ogg", music_lower())
    print("müzik yazıldı")
    # Uçak sesleri en sonda üretilir ki önceki seslerin rastgeleliği değişmesin
    write_ogg("loop_plane.ogg", loop_plane())
    write_ogg("loop_climb.ogg", loop_climb())
    write_wav("sfx_climb.wav", normalize(sfx_climb(), 0.8))
    print("uçak sesleri yazıldı")


if __name__ == "__main__":
    main()

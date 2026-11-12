"""Uçuş modundaki uçak sesi (loop_plane) için dijital, yormayan tasarım denemeleri (oyuna girmez;
dinleyip seçmek için). Her biri 2 sn dikişsiz döngü (frekanslar 0.5 Hz'in katı); oyunda perde
pitch_scale ile 0.9..1.35 arası değişir.
Kullanım: python3 tools/plane_designs.py ÇIKIŞ_KLASÖRÜ"""
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_sounds as ms  # noqa: E402
from make_sounds import SR, filt, normalize  # noqa: E402

LOOP = 2.0


def _t():
    return np.arange(int(SR * LOOP)) / SR


def _lp(x, hi):
    return filt(x, hi=hi, circular=True)


def _saw(f, t):
    return 2.0 * ((f * t) % 1.0) - 1.0


def p1_fm_drone():
    """Yumuşak FM uğultu: tek taşıyıcı (110 Hz), oran 2, düşük modülasyon; yavaş nefes"""
    t = _t()
    mod = np.sin(2 * np.pi * 220 * t) * (0.9 + 0.3 * np.sin(2 * np.pi * 0.5 * t))
    x = np.sin(2 * np.pi * 110 * t + mod) + 0.35 * np.sin(2 * np.pi * 55 * t)
    x *= 0.85 + 0.15 * np.sin(2 * np.pi * 1.0 * t)
    return normalize(_lp(x, 1400), 0.8)


def p2_kare_yumusak():
    """Yumuşatılmış kare dalga (chiptune), alçak geçiren 800 Hz; sakin dijital vızıltı"""
    t = _t()
    sq = np.where(((82.5 * t) % 1.0) < 0.5, 1.0, -1.0) + 0.5 * np.where(((165.5 * t) % 1.0) < 0.3, 1.0, -1.0)
    x = _lp(sq, 800) + 0.4 * np.sin(2 * np.pi * 41.5 * t)
    return normalize(x, 0.8)


def p3_pad():
    """Synth pad: kök ve beşli, hafif akortsuz testereler, 1100 Hz alçak geçiren; havada süzülme"""
    t = _t()
    x = sum(_saw(f, t) for f in (98.0, 98.5, 147.0, 147.5)) / 4.0
    x = _lp(x, 1100) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * t))
    x += 0.3 * np.sin(2 * np.pi * 49.0 * t)
    return normalize(x, 0.8)


def p4_hover():
    """Süzülme: saf alçak sinüs (90 Hz) ve oktavı, yavaş titreşim; neredeyse sessiz akış"""
    t = _t()
    x = np.sin(2 * np.pi * 90 * t) * (0.85 + 0.15 * np.sin(2 * np.pi * 3.0 * t))
    x += 0.4 * np.sin(2 * np.pi * 180 * t) + 0.15 * np.sin(2 * np.pi * 270 * t)
    x += 0.08 * filt(ms.rng.uniform(-1, 1, len(t)), lo=200, hi=900, circular=True)
    return normalize(x, 0.8)


def p5_dijital_nabiz():
    """Dijital nabız: yumuşak FM ton, saniyede 4 hafif darbe (pervane yerine dijital ritim)"""
    t = _t()
    mod = np.sin(2 * np.pi * 240 * t) * 1.2
    tone = np.sin(2 * np.pi * 120 * t + mod) + 0.3 * np.sin(2 * np.pi * 60 * t)
    gate = 0.7 + 0.3 * (0.5 + 0.5 * np.cos(2 * np.pi * 4.0 * t)) ** 2
    return normalize(_lp(tone * gate, 1300), 0.8)


def p6_bit_drone():
    """Bit drone: alçak harmonik uğultu, 6 bitlik hafif dijital tane; filtreli, yumuşak"""
    t = _t()
    x = np.sin(2 * np.pi * 75 * t) + 0.5 * np.sin(2 * np.pi * 150 * t) + 0.25 * np.sin(2 * np.pi * 225 * t)
    x = normalize(x, 1.0)
    x = np.round(x * 31) / 31
    return normalize(_lp(x, 1200), 0.8)


ALTS = [p1_fm_drone, p2_kare_yumusak, p3_pad, p4_hover, p5_dijital_nabiz, p6_bit_drone]


def render(loop, secs=8.0):
    """Oyundaki gibi: perde 0.9 -> 1.35 -> 0.9 (uçuş, tırmanma, iniş), -10 dB"""
    n = int(SR * secs)
    tt = np.arange(n) / n
    pitch = 0.9 + 0.45 * np.sin(np.pi * tt) ** 2
    pos = np.cumsum(pitch) % len(loop)
    i0 = pos.astype(int)
    fr = pos - i0
    out = loop[i0] * (1 - fr) + loop[(i0 + 1) % len(loop)] * fr
    env = np.minimum(1.0, np.minimum(tt * secs / 0.4, (1 - tt) * secs / 0.4))
    return out * env * 10 ** (-10 / 20)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    cur = sf.read(str(Path(__file__).resolve().parent.parent / "audio/loop_plane.ogg"))[0]
    cur = cur if cur.ndim == 1 else cur.mean(axis=1)
    items = [("0 şimdiki", cur)]
    for i, fn in enumerate(ALTS, 1):
        ms.rng = np.random.default_rng(sum(map(ord, fn.__name__)))
        x = fn()
        sf.write(out / f"{fn.__name__}.wav", x, SR)
        items.append((f"{i} " + fn.__doc__.split(":")[0], x))
    reel, labels, tpos = [], [], 0.0
    gap = np.zeros(int(SR * 0.7))
    for name, x in items:
        reel += [render(x), gap]
        labels.append((tpos, name))
        tpos += 8.7
    r = np.concatenate(reel)
    sf.write(out / "reel.wav", r / np.abs(r).max() * 0.89, SR, subtype="PCM_16")
    (out / "labels.txt").write_text("\n".join(f"{int(t // 60)}:{int(t % 60):02d}  {n}" for t, n in labels))
    print((out / "labels.txt").read_text())


if __name__ == "__main__":
    main()

"""Hava akımı engelinin (düz dünyada eski çakılın yerinde) sesi için tasarım denemeleri. Seçilen
tools/make_sounds.py loop_gravel'e girer; diğerleri burada saklı. 2 sn dikişsiz döngü; oyunda
perde 0.85..1.15, seviye hızla.
Kullanım: python3 tools/airwave_designs.py ÇIKIŞ_KLASÖRÜ"""
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


def _noise():
    return ms.rng.uniform(-1, 1, int(SR * LOOP))


def a1_ugultulu_esinti():
    """Uğultulu esinti: alttan yükselen hava (bant gürültü), saniyede bir kabaran dalga, altta alçak uğultu"""
    t = _t()
    air = filt(_noise(), lo=250, hi=1600, circular=True)
    swell = 0.55 + 0.45 * (0.5 - 0.5 * np.cos(2 * np.pi * 1.0 * t)) ** 1.5
    hum = np.sin(2 * np.pi * 55 * t) + 0.4 * np.sin(2 * np.pi * 110 * t)
    return normalize(normalize(air, 1.0) * swell * 0.8 + normalize(hum, 1.0) * 0.35, 0.8)


def a2_dijital_akim():
    """Dijital akım: filtreli gürültünün üstünde yumuşak FM nabız (saniyede 2), yukarı süzülen ton"""
    t = _t()
    air = filt(_noise(), lo=400, hi=2200, circular=True)
    ph = 2 * np.pi * (220 * t + 30 * np.sin(2 * np.pi * 0.5 * t) / (2 * np.pi * 0.5))
    tone = np.sin(ph + 0.8 * np.sin(2 * ph))
    gate = 0.4 + 0.6 * (0.5 - 0.5 * np.cos(2 * np.pi * 2.0 * t)) ** 2
    return normalize(normalize(air, 1.0) * 0.55 + normalize(filt(tone, hi=1500, circular=True), 1.0) * gate * 0.4, 0.8)


def a3_derin_ruzgar():
    """Derin rüzgâr: alçak, kalın hava kükremesi (80-600 Hz), yavaş kabarma; ağır ve sakin"""
    t = _t()
    air = filt(_noise(), lo=80, hi=600, circular=True)
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t) ** 2
    hiss = filt(_noise(), lo=1500, hi=3500, circular=True)
    return normalize(normalize(air, 1.0) * swell + normalize(hiss, 1.0) * 0.12, 0.8)


ALTS = [a1_ugultulu_esinti, a2_dijital_akim, a3_derin_ruzgar]


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    reel, labels, tpos = [], [], 0.0
    gap = np.zeros(int(SR * 0.6))
    for i, fn in enumerate(ALTS, 1):
        ms.rng = np.random.default_rng(sum(map(ord, fn.__name__)))
        x = fn()
        sf.write(out / f"{fn.__name__}.wav", x, SR)
        seg = np.tile(x, 3)[: int(SR * 5)]
        fade = np.minimum(1.0, np.minimum(np.arange(len(seg)) / (SR * 0.3), (len(seg) - np.arange(len(seg))) / (SR * 0.3)))
        reel += [seg * fade * 10 ** (-8 / 20), gap]
        labels.append((tpos, f"{i} " + fn.__doc__.split(":")[0]))
        tpos += 5.6
    r = np.concatenate(reel)
    sf.write(out / "reel.wav", r / np.abs(r).max() * 0.89, SR, subtype="PCM_16")
    (out / "labels.txt").write_text("\n".join(f"{int(t // 60)}:{int(t % 60):02d}  {n}" for t, n in labels))
    print((out / "labels.txt").read_text())


if __name__ == "__main__":
    main()

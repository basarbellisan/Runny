#!/usr/bin/env python3
"""Bölüm Tasarımcısı tasarımını test eder: fizik kontrolleri + oyunda otomatik pilot koşuları.

Kullanım:
    python3 tools/level_test.py levels/kalip.json [--runs 6] [--models 1,2,3,4,6,7]

1) editor/physics.js ile kontroller (atlama, iniş bölgesi, rampa/tümsek uçuşu...).
2) Oyun başsız çalışır: tasarım başlangıç pistinden hemen sonra gelir, araba tasarımın
   hızıyla başlar; her koşu farklı tohum ve araba ile. Geçti / düştü (tasarımdaki metre).
"""
import argparse
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_NAMES = {1: "Kutu", 2: "Gezgin", 3: "Konsept", 4: "Roadster", 6: "Dragster", 7: "Dark Rose"}


def physics_check(path):
    js = (
        "const P=require(%r);const L=JSON.parse(require('fs').readFileSync(%r,'utf8'));"
        "const A=P.analyze(L);console.log(JSON.stringify({issues:A.issues,stats:A.stats}));"
        % (os.path.join(ROOT, "editor", "physics.js"), os.path.abspath(path))
    )
    out = subprocess.run(["node", "-e", js], capture_output=True, text=True)
    if out.returncode != 0:
        print("fizik kontrolü çalışmadı:", out.stderr.strip())
        return None
    return json.loads(out.stdout)


def run_game(path, seed, model, frames):
    cmd = ["godot", "--headless", "--path", ROOT, "--fixed-fps", "60", "--quit-after", str(frames), "--",
           "--autopilot", "--seed=%d" % seed, "--model=%d" % model, "--level=%s" % os.path.abspath(path)]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=600).stdout
    except subprocess.TimeoutExpired:
        return None
    m = re.search(r"LEVEL_(PASS|FAIL) reason=(.+?) x=(-?[\d.]+) z=(-?[\d.]+)", out)
    if not m:
        return None
    return {"ok": m.group(1) == "PASS", "reason": m.group(2), "x": float(m.group(3)), "z": float(m.group(4))}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("level")
    ap.add_argument("--runs", type=int, default=6)
    ap.add_argument("--models", default="1,2,3,4,6,7")
    a = ap.parse_args()
    level = json.load(open(a.level, encoding="utf-8"))
    print("Tasarım: %s (oyunda %s m'den sonra)" % (level.get("name"), level.get("at", 0)))

    chk = physics_check(a.level)
    if chk:
        st = chk["stats"]
        print("  %d m, ~%d sn, %d atlama, zorluk %d/5" % (st["length"], st["time"], st["jumps"], st["difficulty"]))
        for i in chk["issues"]:
            print("  [%s] %s" % ({"error": "HATA", "warn": "uyarı", "ok": "tamam"}[i["level"]], i["text"]))

    models = [int(m) for m in a.models.split(",")]
    length = max(p["z0"] + p["len"] for p in level["pieces"])
    frames = int((length + 400) / 25.0 * 60 * 1.4)
    ok = 0
    for i in range(a.runs):
        model = models[i % len(models)]
        r = run_game(a.level, i + 1, model, frames)
        name = MODEL_NAMES.get(model, str(model))
        if r is None:
            print("  koşu %d (%s): sonuç yok (zaman aşımı ya da tasarım kurulamadı)" % (i + 1, name))
            continue
        ok += r["ok"]
        where = "" if r["ok"] else " — %s, %.0f. metre (x %.1f)" % (r["reason"].rstrip("!").lower(), r["z"], r["x"])
        print("  koşu %d (%s): %s%s" % (i + 1, name, "geçti" if r["ok"] else "düştü", where))
    print("Sonuç: %d/%d geçti" % (ok, a.runs))
    sys.exit(0 if ok == a.runs else 1)


if __name__ == "__main__":
    main()

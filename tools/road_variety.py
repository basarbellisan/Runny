"""Yol çeşitliliği ölçümü: otomatik pilotun çıktısından kalıp sayılarını özetler.
Bir değişiklik yol ağını, yan yolları ya da çatalları seyreltti mi diye bakmak için.

Kullanım (4 dk oyun):
  godot --headless --path . --fixed-fps 60 --quit-after 14400 -- --autopilot --seed=1 | python3 tools/road_variety.py
Referans (aynı ölçüm, 4 dk): kalıp ~2.0-2.4/km, ağ 6-9, yan yol 4-8.
"""
import re
import sys

t = sys.stdin.read()
m = re.search(r'(ALIVE|GAME_OVER)[^\n]*distance=(\d+)', t)
dist = int(m.group(2)) if m else 0
pat = re.search(r'PATTERNS \{([^}]*)\}', t)
pc = dict((k, int(v)) for k, v in re.findall(r'"([^"]+)": (\d+)', pat.group(1))) if pat else {}


def stat(key):
    r = re.search(r'"?%s"?: (\d+)' % key, t)
    return int(r.group(1)) if r else 0


tot = sum(pc.values())
km = max(dist / 1000.0, 0.1)
print('%5.1f km | kalıp %2d (%.1f/km) | ağ %d  yan yol %d  çatal %d  çıkmaz %d  yatık %d  eğim %d  '
      'vadi %d  merdiven %d  rampa %d  düz %d | rampa nesnesi %d | %s' % (
          km, tot, tot / km, pc.get('ağ', 0), stat('side_roads'), pc.get('çatal', 0), pc.get('çıkmaz', 0),
          pc.get('yatık', 0), pc.get('eğim', 0), pc.get('vadi', 0), pc.get('merdiven', 0), pc.get('rampa', 0),
          pc.get('düz', 0), stat('ramps'), m.group(1) if m else '?'))

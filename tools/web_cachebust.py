"""Web dışa aktarımından sonra: oyunun verisi (index.pck) içeriğine göre değişen bir sürüm ekiyle
yüklensin (index.pck?v=<özet>). Tarayıcı / GitHub Pages önbelleği yeni yayından sonra eski sürümü
açmasın. Kullanım: python3 tools/web_cachebust.py build/web"""
import hashlib, json, os, re, sys

web = sys.argv[1] if len(sys.argv) > 1 else "build/web"
html_path = os.path.join(web, "index.html")
pck = open(os.path.join(web, "index.pck"), "rb").read()
tag = hashlib.sha1(pck).hexdigest()[:10]
html = open(html_path, encoding="utf-8").read()
m = re.search(r"const GODOT_CONFIG = (\{.*?\});", html)
cfg = json.loads(m.group(1))
cfg["mainPack"] = "index.pck?v=" + tag
sizes = cfg.get("fileSizes", {})
if "index.pck" in sizes:
    sizes["index.pck?v=" + tag] = sizes["index.pck"]
html = html[:m.start(1)] + json.dumps(cfg, separators=(",", ":")) + html[m.end(1):]
open(html_path, "w", encoding="utf-8").write(html)
print("mainPack =", cfg["mainPack"])

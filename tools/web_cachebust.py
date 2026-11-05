"""Web dışa aktarımından sonra: oyunun verisi (index.pck) içeriğine göre değişen bir sürüm ekiyle
yüklensin (index.pck?v=<özet>). Tarayıcı / GitHub Pages önbelleği yeni yayından sonra eski sürümü
açmasın.

GitHub Pages index.html'i de ~10 dk önbellekte tutturur: önbellekten gelen eski sayfa eski oyun
dosyasını açar. Bu yüzden her yayında version.json yazılır (en son oyun dosyasının adı) ve sayfa
açılırken bu dosyayı önbelleği atlayarak (cache: 'no-store') okuyup o oyun dosyasını yükler.
Okunamazsa sayfanın içindeki adla açılır. Kullanım: python3 tools/web_cachebust.py build/web"""
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

# Başlatırken en son oyun dosyasını version.json'dan öğren (sayfa önbellekten gelse bile)
START = "\t\tengine.startGame({\n"
END = "\t\t}).then(() => {\n\t\t\tsetStatusMode('hidden');"
if "version.json" not in html:
    assert html.count(START) == 1 and html.count(END) == 1, "index.html başlatma kodu beklenen biçimde değil"
    html = html.replace(START, "\t\t// En son oyun dosyası: sayfa önbellekten gelse de version.json önbelleksiz okunur\n"
        "\t\tfetch('version.json', { cache: 'no-store' }).then((r) => (r.ok ? r.json() : {})).catch(() => ({}))"
        ".then((v) => engine.startGame({\n"
        "\t\t\t...(v && v.mainPack ? { 'mainPack': v.mainPack } : {}),\n")
    html = html.replace(END, "\t\t})).then(() => {\n\t\t\tsetStatusMode('hidden');")
open(html_path, "w", encoding="utf-8").write(html)
json.dump({"mainPack": cfg["mainPack"]}, open(os.path.join(web, "version.json"), "w"))
print("mainPack =", cfg["mainPack"])

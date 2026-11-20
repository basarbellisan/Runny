"""Web dışa aktarımından sonra: açılış introsu (intro/ollo-intro-N.webm, Safari için .mp4; her açılışta rastgele biri) sayfanın kendisinde oynar.

Godot'nun web sürümü videoyu işlemcide (yazılımla) çözer; telefonda 1080x1920 / 60 fps video takılır.
Tarayıcı ise MP4'ü donanımla çözer: akıcı oynar. Üstelik intro oyun yüklenirken oynar (yükleme ekranındaki
Godot logosunun yerine). Video bitince ve oyun hazır olunca intro katmanı kâğıt rengine geçip kaybolur;
oyun hazır değilse son karede (logo) bekler. Dokunmak introyu atlar (oyun hazırsa hemen geçer).
Tarayıcılar sesli otomatik oynatmaya izin vermez: video sessiz başlar.
Bölüm tasarımcısından açılışta (?level=) intro yok. Oyun içindeki intro (scripts/splash.gd) web'de atlanır.

Kullanım: python3 tools/web_intro.py build/web/yeni   (web_cachebust.py'den sonra)"""
import os, shutil, sys

web = sys.argv[1] if len(sys.argv) > 1 else "build/web"
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
## Intro seçenekleri (intro/ollo-intro-N.*): her açılışta rastgele biri oynar (deneme: ?intro=N)
COUNT = 4
for n in range(1, COUNT + 1):
    for ext in ("mp4", "webm"):
        shutil.copy(os.path.join(root, "intro", "ollo-intro-%d.%s" % (n, ext)), os.path.join(web, "intro-%d.%s" % (n, ext)))
html_path = os.path.join(web, "index.html")
html = open(html_path, encoding="utf-8").read()
if 'id="intro"' in html:
    print("intro zaten var")
    sys.exit(0)

OVERLAY = """
		<div id="intro" style="position:fixed;top:0;left:0;width:100vw;height:100vh;height:100dvh;z-index:10;background:#0f0e11;transition:background-color .4s ease;touch-action:none">
			<video id="intro-video" muted playsinline webkit-playsinline autoplay preload="auto"
				style="position:absolute;top:0;left:0;width:100%;height:100%;object-fit:contain;opacity:0;transition:opacity .15s ease">
			</video>
			<div id="intro-bar" style="position:absolute;left:50%;bottom:18%;width:120px;height:3px;margin-left:-60px;border-radius:2px;background:rgba(255,255,255,.14);opacity:0;transition:opacity .4s ease">
				<div id="intro-fill" style="width:0;height:100%;border-radius:2px;background:rgba(255,255,255,.75);transition:width .25s linear"></div>
			</div>
		</div>
		<script>
		// Açılış introsu (tools/web_intro.py): video bitince ve oyun hazır olunca kâğıt rengine geçip kaybolur
		(function () {
			var box = document.getElementById('intro');
			var v = document.getElementById('intro-video');
			// Her açılışta rastgele bir intro (deneme: ?intro=N)
			var n = parseInt(new URLSearchParams(location.search).get('intro'), 10);
			if (!(n >= 1 && n <= __COUNT__)) n = 1 + Math.floor(Math.random() * __COUNT__);
			['webm', 'mp4'].forEach(function (ext) {
				var src = document.createElement('source');
				src.src = 'intro-' + n + '.' + ext;
				src.type = 'video/' + ext;
				v.appendChild(src);
			});
			var ended = false, ready = false, gone = false;
			if (new URLSearchParams(location.search).get('level')) {
				box.remove();
				gone = true;
			}
			function finish() {
				if (gone || !ended || !ready) return;
				gone = true;
				v.style.opacity = '0';
				bar.style.opacity = '0';
				box.style.backgroundColor = '#f2f0eb';
				setTimeout(function () {
					box.style.transition = 'opacity .35s ease';
					box.style.opacity = '0';
					setTimeout(function () { box.remove(); }, 400);
				}, 350);
			}
			// Intro bitti ama oyun yükleniyor: logonun altında ince yükleme çizgisi (Godot'nun ilerlemesi)
			var bar = document.getElementById('intro-bar'), fill = document.getElementById('intro-fill');
			var poll = setInterval(function () {
				if (gone) { clearInterval(poll); return; }
				var pr = document.getElementById('status-progress');
				if (ended && !ready) {
					bar.style.opacity = '1';
					if (pr && pr.max > 0 && pr.value > 0) fill.style.width = Math.min(100, 100 * pr.value / pr.max) + '%';
				}
			}, 200);
			function end() { ended = true; finish(); }
			// Video oynamaya başlayınca görünür (boyutu yerleşmeden küçük bir kutuda görünmesin)
			v.addEventListener('playing', function () { if (!gone) v.style.opacity = '1'; });
			v.addEventListener('ended', function () { setTimeout(end, 250); });
			v.addEventListener('error', end);
			var srcs = v.querySelectorAll('source');
			if (srcs.length) srcs[srcs.length - 1].addEventListener('error', end);  // hiçbiri oynatılamadı
			var p = v.play && v.play();
			if (p && p.catch) p.catch(end);  // oynatılamadıysa (ör. güç tasarrufu) beklemeden geç
			setTimeout(end, 5000);           // güvenlik: video takılırsa
			box.addEventListener('pointerdown', end);  // dokununca atla
			window.introGameReady = function () { ready = true; finish(); };
		})();
		</script>
"""
OVERLAY = OVERLAY.replace("__COUNT__", str(COUNT))
BODY = "\t<body>\n"
assert html.count(BODY) == 1
html = html.replace(BODY, BODY + OVERLAY, 1)
READY = "\t\t\tsetStatusMode('hidden');"
assert html.count(READY) == 1, "index.html başlatma kodu beklenen biçimde değil"
html = html.replace(READY, READY + "\n\t\t\tif (window.introGameReady) window.introGameReady();", 1)
open(html_path, "w", encoding="utf-8").write(html)
print("intro eklendi:", web)

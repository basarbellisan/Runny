# Sky Runner (prototip)

Havada duran, birbirinden bağımsız duvar-yollar üzerinde sonsuz koşu. Godot 4.7, mobil (dikey ekran).

## Açmak
Godot 4.7 ile `project.godot` dosyasını aç, F5 ile çalıştır.

## Garaj
Oyun garaj ekranıyla açılır: araba modelleri platformlarında döner, sağa/sola
kaydırarak (ya da oklarla) model seçilir, BAŞLA ile oyun başlar. Seçim
kaydedilir. Oyun sonunda GARAJ butonu garaja döndürür.

## Kontroller
- Mobil: ekranın sol yarısına dokun → sola, sağ yarısına → sağa
- İki parmakla (iki yarıya birden) bas → yolda gaz, uçarken yükselme. Bu sırada direksiyon çalışmaz.
- PC: A / D veya ← / → ile yön, W / ↑ / Boşluk ile gaz

Araba tekerlerinden hisseder: bir yanın tekerleri boşluğa çıkınca araba o
yana yatar, boşluğa doğru çekilir ve tutuşu azalır; ağırlık merkezi kenarı
geçerse yuvarlanarak düşer. İniş yardımı varsayılan olarak kapalı.

Her yolun sonunda gaz şart: gazsız kalkan araba bir sonraki yolun ön
yüzüne çakılıp patlar. Yanlış hizalanıp yolun yanından düşersen kanatlar
açılır ve alt katmana geçersin.

## Ayar paneli
Oyun sırasında sol üst köşeye arka arkaya üç kez dokun (PC'de F1): oyun durur,
hız, direksiyon, gaz, atlama, yollar, uçuş, puan, kamera ve ses ayarları açılır.
Değişiklikler hemen uygulanır ve cihazda saklanır. "Kopyala", yalnızca
varsayılandan farklı değerleri tek satırlık metin olarak verir
(`AYARLAR car.start_speed=24; ...`). Panelin listesi `scripts/tuning.gd` içinde.

## Oyun döngüsü
- Üst katman: yollarda git, üstte kaldıkça çarpan artar (x5'e kadar)
- Yoldan düşersen kanatlar açılır, alt katmanda uçarsın; çarpan x1'e döner
- Alt katmanda kanat enerjisi azalır; iki parmakla ~8 m yükselip kayaların üstünden geçilebilir ama
  enerji 2.5 kat hızlı biter. Bazı kayalar ve kristaller yukarıda. Kristaller enerji verir, kayalar öldürür
- Portala girersen yukarı fırlatılır, arabaya dönüşüp bir yola konarsın

## Yollar
Yollar kalıplar hâlinde üretilir, mesafe arttıkça yenileri açılır:
- 0–1 km: düz yollar
- 1 km+: hafif yokuşlar, vadiler (yokuş aşağı → alçak yol → rampayla yukarı)
- 2 km+: merdivenler, rampalar (kalkışta yukarı fırlatır), çıkmazlar
  (yanda alçak, geniş bir yol; devamı yoktur, uçuşa düşülür — ana yol hep yanında devam eder)

Rampanın açısı kalkıştaki dikey hıza eklenir. Her boşluk yine gazsız
ulaşılamaz, tam gazla ulaşılır. Renkler: her 1 km'de bir bölge tonu
(beyaz → adaçayı → buğulu mavi → kum → arduvaz), alçak yollar daha koyu,
yokuş yukarı rampaların kenar çizgileri turuncu.

## Yapı
- `scripts/menu.gd` — garaj (başlangıç ekranı)
- `scripts/car_model.gd` — araba görünümü (3 model: kutu, gezgin, konsept) ve tekerler
- `scripts/car_trail.gd` — hız izi (3 stil)
- `tools/showroom.gd` — araba modellerinin vitrin görüntülerini çeker
- `scripts/car.gd` — araba fiziği ve modları (yol / düşüş / uçuş / portal fırlatması), kanat animasyonu
- `scripts/road_generator.gd` — prosedürel yol üretimi (her yol ulaşılabilir olacak şekilde hesaplanır)
- `scripts/lower_layer.gd` — alt katman: kayalar, kristaller, portallar (portal, yukarıdaki bir yola indirecek şekilde yerleştirilir)
- `scripts/game.gd` — skor, çarpan, kanat enerjisi, katmanlar arası renk geçişi, oyun sonu
- `scripts/audio.gd` — ses yöneticisi (autoload `Audio`): müzik katmanlar arası geçiş yapar, motor/rüzgâr hıza göre değişir
- `scripts/autopilot.gd` — test için otomatik sürücü
- `tools/make_sounds.py` — tüm sesleri ve müziği sıfırdan sentezler (`pip install numpy soundfile`, sonra `python3 tools/make_sounds.py`)
- `scripts/follow_camera.gd`, `scripts/hud.gd`

## Web sürümü
https://basarbellisan.github.io/Runny/ — `gh-pages` dalından yayınlanır.
```
godot --headless --path . --export-release "Web" build/web/index.html
```

## Test argümanları
```
godot --path . -- --autopilot --seed=42              # otomatik pilot
godot --path . -- --autopilot --dive=10 --seed=42    # 10 sn'de bir bilerek düşer, portal arar
godot --path . -- --autopilot --noboost --seed=42    # hiç gaz vermez: ilk boşlukta çakılmalı
godot --path . -- --autopilot --deadend --seed=42    # çıkmazlara bilerek girer: çakılmadan uçuşa düşmeli
godot --path . -- --shots=120,600 --shot_dir=/tmp    # ekran görüntüsü
```

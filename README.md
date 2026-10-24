# Sky Runner (prototip)

Havada duran, birbirinden bağımsız duvar-yollar üzerinde sonsuz koşu. Godot 4.7, mobil (dikey ekran).

## Açmak
Godot 4.7 ile `project.godot` dosyasını aç, F5 ile çalıştır.

## Kontroller
- Mobil: ekranın sol yarısına dokun → sola, sağ yarısına → sağa
- İki parmakla (iki yarıya birden) bas → gaz. Gaz verirken direksiyon çalışmaz.
- PC: A / D veya ← / → ile yön, W / ↑ / Boşluk ile gaz

Her yolun sonunda gaz şart: gazsız kalkan araba bir sonraki yolun ön
yüzüne çakılıp patlar. Yanlış hizalanıp yolun yanından düşersen kanatlar
açılır ve alt katmana geçersin.

## Oyun döngüsü
- Üst katman: yollarda git, üstte kaldıkça çarpan artar (x5'e kadar)
- Yoldan düşersen kanatlar açılır, alt katmanda uçarsın; çarpan x1'e döner
- Alt katmanda kanat enerjisi azalır (gazla daha hızlı); kristaller enerji verir, kayalar öldürür
- Portala girersen yukarı fırlatılır, arabaya dönüşüp bir yola konarsın

## Yapı
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
godot --path . -- --shots=120,600 --shot_dir=/tmp    # ekran görüntüsü
```

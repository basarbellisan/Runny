# Sky Runner (prototip)

Havada duran, birbirinden bağımsız duvar-yollar üzerinde sonsuz koşu. Godot 4.7, mobil (dikey ekran).

## Açmak
Godot 4.7 ile `project.godot` dosyasını aç, F5 ile çalıştır.

## Kontroller
- Mobil: ekranın sol yarısına dokun → sola, sağ yarısına → sağa
- PC: A / D veya ← / → (fare tıklaması da dokunma gibi çalışır)

## Oyun döngüsü
- Üst katman: yollarda git, üstte kaldıkça çarpan artar (x5'e kadar)
- Yoldan düşersen kanatlar açılır, alt katmanda uçarsın; çarpan x1'e döner
- Alt katmanda kanat enerjisi azalır; kristaller enerji verir, kayalar öldürür
- Portala girersen yukarı fırlatılır, arabaya dönüşüp bir yola konarsın

## Yapı
- `scripts/car.gd` — araba fiziği ve modları (yol / düşüş / uçuş / portal fırlatması), kanat animasyonu
- `scripts/road_generator.gd` — prosedürel yol üretimi (her yol ulaşılabilir olacak şekilde hesaplanır)
- `scripts/lower_layer.gd` — alt katman: kayalar, kristaller, portallar (portal, yukarıdaki bir yola indirecek şekilde yerleştirilir)
- `scripts/game.gd` — skor, çarpan, kanat enerjisi, katmanlar arası renk geçişi, oyun sonu
- `scripts/autopilot.gd` — test için otomatik sürücü
- `scripts/follow_camera.gd`, `scripts/hud.gd`

## Test argümanları
```
godot --path . -- --autopilot --seed=42              # otomatik pilot
godot --path . -- --autopilot --dive=10 --seed=42    # 10 sn'de bir bilerek düşer, portal arar
godot --path . -- --shots=120,600 --shot_dir=/tmp    # ekran görüntüsü
```

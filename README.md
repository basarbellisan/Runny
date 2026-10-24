# Sky Runner (prototip)

Havada duran, birbirinden bağımsız duvar-yollar üzerinde sonsuz koşu. Godot 4.7, mobil (dikey ekran).

## Açmak
Godot 4.7 ile `project.godot` dosyasını aç, F5 ile çalıştır.

## Kontroller
- Mobil: ekranın sol yarısına dokun → sola, sağ yarısına → sağa
- PC: A / D veya ← / → (fare tıklaması da dokunma gibi çalışır)

## Yapı
- `scripts/car.gd` — araba fiziği (otomatik ileri, direksiyon, kenardan fırlama, iniş yardımı)
- `scripts/road_generator.gd` — prosedürel yol üretimi (her yol ulaşılabilir olacak şekilde hesaplanır)
- `scripts/game.gd` — skor, çarpan, oyun sonu
- `scripts/follow_camera.gd`, `scripts/hud.gd`

## Test argümanları
```
godot --path . -- --autopilot --seed=42              # otomatik pilot
godot --path . -- --shots=120,600 --shot_dir=/tmp    # ekran görüntüsü
```

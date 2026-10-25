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
geçerse (~50°) kenardan devrilip düşer. İniş yardımı varsayılan olarak kapalı.

Havada araba gerçek bir duruşla uçar: yandan düşerken dönmeye devam eder
(kendini düzeltmez), kanatlar açılınca düzelir. Havada direksiyon arabayı o
yana yatırır (bırakınca söner); kendiliğinden düzelme çok zayıf. İnişte
duruş yolla karşılaştırılır:
- ~12°'den az sapma: temiz iniş (PERFECT ancak temiz inişte)
- daha fazlası ya da çok yüksekten düşüş: SERT İNİŞ / SENDELEDİN — tutuş
  azalır, araba yana savrulur, gaz söner
- yan ya da ters iniş (~75°+): araba patlar (TAKLA ATTIN!)

Süspansiyon belirgin: inişte gövde çöker, yamuk inişte salınır; tekerler yerde
kalır. İnişte tekerlerden toz, sert inişte ve kenara sürtünürken kıvılcım çıkar,
kamera sarsılır.

Gaz bir roket: kısa, çok güçlü (hız 2.3 katına kadar çıkar; ateşlenince
arka çöker, burun kalkar, kamera açılır). Yakıtı ~1.35 sn yanar, yolda gaza
basmazken ~1.6 sn'de dolar (kadranın altındaki
çizgi: turuncu = dolu). Gaz havada sönmez ama yolda bırakınca 0.35 sn'de
söner; bu yüzden erken basan yolun sonuna yakıtsız ve yavaş varır. Doğru an
yolun son ~0.7 saniyesi: iki kenarda yolun sonuna doğru akan kırmızı pist
ışıkları ve uçtaki ışık sırası. Gazlarken direksiyon çalışmaz, o yüzden
ışıklardan önce hizalan.

Her yolun sonunda gaz şart: gazsız kalkan araba bir sonraki yolun ön
yüzüne çakılıp patlar. Yanlış hizalanıp yolun yanından düşersen kanatlar
açılır ve alt katmana geçersin. Çıkmaz yollarda pist ışığı yoktur.

Düz yollarda (350 m'den sonra) sağ-sol oynatan engeller:
- Beton blok (turuncu üst şeritli): sırayla sağda solda, aralarından geçilir;
  ön yüzüne çarpan patlar
- Çakıl şeridi (kum rengi, taşlı): üstünde hız ~%45 düşer, tutuş çok azalır, taşlar
  arabayı sağa sola savurur, çıktıktan sonra da ~0.6 sn sendeler;
  araba sarsılır, taş sesi ve toz. İlk üç seferde "ÇAKIL · YAVAŞLATIR" yazar
Yolun başı (iniş) ve sonu (pist ışıkları + hizalanma) her zaman boştur.

Yatık yollar (500 m'den sonra): yol düz başlar, yavaşça sağa ya da sola
yatar (~11–15°), bir süre öyle gider ve düzelir; bazıları S çizer (önce bir
yana, sonra öbür yana). Araba alçak tarafa doğru kayar, ters direksiyonla
yolda tutulur; gövde yolla birlikte yatar, kamera da biraz eşlik eder. İnişte
açı yolun yatıklığına göre ölçülür. Alçak kenarda kırmızı-beyaz bordür
vardır: yol hangi yana yatıyorsa o kenarda, yatık bölüm boyunca (S bükülmede
öbür kenara geçer). Yatık yolun sonu her zaman düzdür
(pist ışıkları + roket). Yüzey tek parça kıvrılan bir ağ; arabanın çarpışma
omurgası altı yuvarlak bir kapsül olduğu için yüzeyin kenarlarına takılmaz.

## Ayar paneli
Oyun sırasında sol üst köşeye arka arkaya üç kez dokun (PC'de F1): oyun durur,
hız, direksiyon, gaz, atlama, yollar, uçuş, puan, kamera ve ses ayarları açılır.
Listeyi sağ kenardaki turuncu tutamaklı şeritten kaydır (ayarlara yanlışlıkla
dokunmamak için). Değişiklikler hemen uygulanır ve cihazda saklanır. "Kopyala", yalnızca
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
- 0–300 m: düz yollar
- 300 m+: yokuşlar (10–15°), vadiler (yokuş aşağı → alçak yol → rampayla yukarı)
- 800 m+: merdivenler, rampalar (15–18°, kalkışta yukarı fırlatır), çıkmazlar
  (yanda alçak, geniş bir yol; devamı yoktur, uçuşa düşülür — ana yol hep yanında devam eder)
  ve çatallar: geniş bir yoldan iki kol ayrılır. Alçak kol geniş ve kolay; yüksek
  kol rampayla çıkılır, dar ve zor boşlukludur, turuncu çizgilidir. Yüksek kolda
  puan iki kat, bitirince +250 × çarpan. İki kol ileride geniş bir yolda birleşir.

Rampanın açısı kalkıştaki dikey hıza eklenir. Her boşluk yine gazsız
ulaşılamaz, tam gazla ulaşılır. Eğimli yollar inişten sonra hizalanıp gaz
verecek kadar uzundur (~1.4 sn) ve eğimden sonraki boşluk yarım gazla
hesaplanır. Renkler: her 1 km'de bir bölge tonu
(beyaz → adaçayı → buğulu mavi → kum → arduvaz), alçak yollar daha koyu.
Yokuş yukarı rampalar: turuncu kenar çizgileri, turuncu oklar (^) ve
turuncuya çalan duvarlar; yokuş aşağılar biraz daha koyu.

## Yapı
- `scripts/menu.gd` — garaj (başlangıç ekranı)
- `scripts/car_model.gd` — araba görünümü (3 model: kutu, gezgin, konsept) ve tekerler
- `scripts/car_trail.gd` — hız izi (3 stil)
- `scripts/car_fx.gd` — toz, kıvılcım, roket alevi ve çakıl tozu parçacıkları
- `shaders/runway_lights.gdshader` — yolun sonuna doğru akan pist ışıkları
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

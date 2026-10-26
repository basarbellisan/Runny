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
arka çöker, burun kalkar). Roket **enerji** yakar (yerde yanarken saniyede 45);
enerji kendiliğinden dolmaz, yalnız kristallerden gelir. Enerji bitince gaza
basmak işe yaramaz: gösterge sarsılır, boğuk bir ses çıkar, boşluk aşılamaz.
Bir basışta roket en çok ~1.35 sn yanar, bırakınca ~1.6 sn'de yeniden basılabilir. Gaz havada sönmez ama yolda bırakınca 0.35 sn'de
söner; bu yüzden erken basan yolun sonuna yakıtsız ve yavaş varır. Doğru an
yolun son ~1.1 saniyesi: iki kenarda yuvarlak kırmızı pist ışıkları (başta
seyrek, yolun ucuna doğru sıklaşır). Işıkların ~%30'unu kaplayan parlak bir bant
~0.7 sn'de yolun ucuna akar ve döngüyle tekrarlar; yanan ışık iki kat büyür. Gazlarken direksiyon çalışmaz, o yüzden
ışıklardan önce hizalan.

Her yolun sonunda gaz şart: gazsız kalkan araba bir sonraki yolun ön
yüzüne çakılıp patlar. Yanlış hizalanıp yolun yanından düşersen kanatlar
açılır ve alt katmana geçersin. Çıkmaz yollarda pist ışığı yoktur.

Engeller:
- Beton blok (turuncu üst şeritli): ön yüzüne çarpan patlar
- Çakıl (kum rengi, taşlı): üstünde hız ~%45 düşer, tutuş çok azalır, taşlar
  arabayı sağa sola savurur, çıktıktan sonra da ~0.6 sn sendeler;
  araba sarsılır, taş sesi ve toz. İlk üç seferde "ÇAKIL · YAVAŞLATIR" yazar
Yolun başı (iniş) ve sonu (pist ışıkları + hizalanma) engelsizdir; oralarda kristal olur.

## Enerji ve kristaller
Sağ altta enerji deposu (solda hız kadranı): beyaz disk, ortada sayı, çevresinde
turuncu halka (tepeden saat yönünde dolar). 20'nin altında kırmızı nabız ve
"KRİSTAL TOPLA!"; kristal alınca üstünde "+8" belirir, halkanın ucu parlar.
Tek enerji: roket ve kanatlar aynı depodan yer. Düşerken enerji 20'den azsa
kanatlar için 20 yedek verilir; alt katmandaki kristaller de bu depoyu doldurur.
Yola dönünce depo dolmaz (ne topladıysan o).

Yoldaki turuncu kristaller (+8) her yol için o yolun sonundaki boşluğa
gereken enerjinin katı kadar konur: başta 3 katı, 6 km'de 1.6 katı (yeterli
ama gittikçe zor). Başta çoğu kolay yerdedir (inişten sonra bir çizgi, pist
ışıklarında ortada bir çizgi), giderek zor yerlere kayar:
- bloğun kıl payı yanı, kapının geçidi, çakılın içindeki temiz şerit, çakıl tarlası
- dar parçanın ortası, kaymadan sonraki yeni hat, tümsek tepesinin üstü (havada)
- boşluğun üstünde, orta karar gazla atlayanın uçuş yayında
- rampadan kalkışın yayında (yana atan rampada yana da kayar)
- alçak ve yüksek yan yollarda bol; yatık yolda yüksek kenarda

Yatık yollar: yol düz başlar, yavaşça sağa ya da sola
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
- Alt katmanda enerji (roketle aynı depo) azalır; iki parmakla ~8 m yükselip kayaların üstünden geçilebilir ama
  enerji 2.5 kat hızlı biter. Bazı kayalar ve kristaller yukarıda. Kristaller enerji verir, kayalar öldürür
- Portala girersen yukarı fırlatılır, arabaya dönüşüp bir yola konarsın

## Yollar
Yollar kalıplar hâlinde, her oyunda rastgele üretilir. Başlangıç pistinden
(~155 m) hemen sonra kalıpların çoğu gelebilir, böylece her oyun farklı başlar;
ilk 1.5 km'de (ease_distance) açılar ve yatmalar daha yumuşaktır:
- baştan: düz yollar, yokuşlar (10–15°), vadiler (yokuş aşağı → alçak yol →
  rampayla yukarı), yatık yollar, yol ağı, engeller
- 150 m+: merdivenler, rampalar (15–18°, kalkışta yukarı fırlatır)
- 400 m+: çıkmazlar
  (yanda alçak, geniş bir yol; devamı yoktur, uçuşa düşülür — ana yol hep yanında devam eder)
  ve çatallar: geniş bir yoldan iki kol ayrılır. Alçak kol geniş ve kolay; yüksek
  kol rampayla çıkılır, dar ve zor boşlukludur, turuncu çizgilidir. Yüksek kolda
  puan iki kat, bitirince +250 × çarpan. İki kol ileride geniş bir yolda birleşir.
- yol ağı: kendi kalıbıdır (iniş + 3.5–5.5 sn + pist); az başlar, mesafeyle sıklaşır. Ödül yoktur, sadece yol seçimi. Üstüne 1-4 parça
  sırayla dizilir (aynı parça üst üste gelmez), parçaların arası blok ve çakılla dolar:
  - rampa: tam ya da yarım genişlik, boyu (6–10 m) ve yüksekliği değişir; yarım
    rampanın arkasına çakıl gelebilir (üstünden uç ya da çakıldan geç)
  - slalom: sırayla sağda solda 3-4 küçük yarım rampa
  - alçak yan yol (3–5.5 m aşağıda): ana yolun kenarından düşülür, bazen ağın en
    başından başlar; üstünde de engel olabilir; sonundaki eğik rampa ana yola atar
  - yüksek yan yol (1.8–3.4 m yukarıda): ana yolun bir yanındaki eğik rampayla
    çıkılır; sonundaki küçük rampa ana yola indirir

  Eğik rampalar (5–9°) yukarıyla birlikte yana da atar; oklar attığı yönü
  gösterir. Atış hedef yola yetecek kadardır, havada sağ-sol ile hizalanılır.
  Rampada roket yanmaz (rampa kendi atar). Kalkışta gövdenin burgu dönüşü
  söndürülür, araba havada takla atmaz. Rampaya yaklaşma, uçuş ve iniş yerleri
  hep boştur.

Kalıplar tekrar etmez: bir önceki kalıp hiç gelmez, son üç kalıbın şansı düşer.
Engelli düz yollar 330–470 m'dir (önceden en az 520 m).

### Yol içi: ritim ve olaylar
Düz yollar tek bir kutu değil: kendi içinde bitişik parçalara bölünür ve
üstüne rastgele olaylar dizilir. Her düz yolun bir ruh hâli var: **nefes**
(kısa, sadece atlama ve kristal), **orta** (2-3 olay), **yoğun** (3-6 olay, sık).
İki nefes üst üste gelmez; yoğun mesafeyle sıklaşır. Yolun uzunluğu
"iniş bölgesi + olaylar + pist bölgesi" kadardır (boş uzun yol yok).
Olaylar (son olay hemen tekrar gelmez, son beşin şansı düşer):
- tek blok (rastgele yerde), iki blok (düzensiz, arada karşıya geçecek vakit),
  kapı (bir sıra blok, tek geçit), zikzak (sağ-sol 2-4 sıra)
- çakıl şeridi (içinde tek temiz şerit), çakıl tarlası (tüm yol), yanda çakıl,
  blok + çakıl (ortada şerit)
- daralma, yarık (yolun yarısı yok), kayma (yol basamak gibi yana kayar),
  genişleme, tümsek (tepede hafif havalanırsın)
Daralan/kayan parçada boşta kalan kenardan düşülür; bitişik parçalar arasında
zıplama yok.

**Aksiyon çarpanı** (`action`, varsayılan 2, ayar panelinde): olay sayısı ve
sıklığı, yoğun yolların payı, kristal fırsatları bununla çarpılır; nefes yollar
seyrekleşir. Olaylar arası tepki süresi yine de en az ~0.45 sn kalır. Her yol
üretildikten sonra blok sıraları baştan sona denetlenir: bir sıranın geçidinden
sonrakinin geçidine o hızla yetişilemiyorsa o sıra kaldırılır (imkânsız dizilim yok).
İniş bölgesi engelsizdir ama seçim vardır: iki yana ayrılan iki kristal çizgisi
(uzaktaki yanda bir kristal fazla) ya da bir yanda kısa çakıl. Pist çizgisi bir
yandan başlayıp ortaya iner. Çatalın kolay kolu ve çıkmazın yanındaki ana yol da
olaylarla dolar; yol ağında parçalar alçak yolun yanındaki ana yola da dizilir. 10 km'lik ölçümde 2 sn'den uzun "hiçbir şey olmayan" aralıklar
yolun %45'inden ~%10'una indi (kristaller dahil; `--dump_roads` ile ölçülür).

Rampanın açısı kalkıştaki dikey hıza eklenir. Her boşluk yine gazsız
ulaşılamaz, tam gazla ulaşılır. Eğimli yollar inişten sonra hizalanıp gaz
verecek kadar uzundur (~1.4 sn) ve eğimden sonraki boşluk yarım gazla
hesaplanır. Renkler: her 1 km'de bir bölge tonu
(beyaz → adaçayı → buğulu mavi → kum → arduvaz), alçak yollar daha koyu.
Yokuş yukarı rampalar: turuncu kenar çizgileri, turuncu oklar (^) ve
turuncuya çalan duvarlar; yokuş aşağılar biraz daha koyu.

## Yapı
- `scripts/menu.gd` — garaj (başlangıç ekranı)
- `scripts/car_model.gd` — araba görünümü (4 model: kutu, gezgin, konsept, roadster) ve tekerler
- `scripts/car_trail.gd` — hız izi (3 stil)
- `scripts/car_fx.gd` — toz, kıvılcım, roket alevi ve çakıl tozu parçacıkları
- `shaders/runway_dots.gdshader`, `shaders/runway_halo.gdshader` — pist ışıkları ve parlamaları
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
godot --path . -- --autopilot --side --seed=42       # yan yollara girer (alçağa düşer, eğik rampaya girer), SIDE_TRIPS yazar
godot --path . -- --autopilot --nocrystal --seed=42  # hiç kristal almaz: ~1.5 km'de enerjisi bitip düşmeli
godot --path . -- --autopilot --seed=5 --dump_roads=/tmp/yol.json   # üretilen bütün yolları, engelleri ve kristalleri yazar
godot --path . -- --nohud --shots=600 --shot_dir=/tmp                 # göstergesiz ekran görüntüsü (tasarım taslakları için)
godot --path . -- --shots=120,600 --shot_dir=/tmp    # ekran görüntüsü
```

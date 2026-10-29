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
Bir basışta roket en çok ~1.35 sn yanar, bırakınca ~1.6 sn'de yeniden basılabilir. Roketin
alevi yok: gaz verince arka lambalardan çıkan (kristallerin yeşilindeki) ışık izi uzar ve genişler (boyunca eşit
kalınlıkta, uca doğru incelmez). Gaz havada sönmez ama yolda bırakınca 0.35 sn'de
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
limon yeşili halka (tepeden saat yönünde dolar). 20'nin altında kırmızı nabız ve
"KRİSTAL TOPLA!" (alt katmanda bu yazı yok: orada kristal yok); kristal alınca üstünde "+3" belirir (art arda toplananlar toplanır), halkanın ucu parlar.
İki kadran da yalnız oynarken görünür: oyun bitince kaybolur.
Tek enerji: roket ve kanatlar aynı depodan yer. **Aşağıda kristal yok**: düştüğün
andaki depo, aşağıdaki hayat süren olur (uçuş 6/s, yükselirken 15/s yakar). Depo
bitince kanat yedeği "çısss" diye açılır: düz uçuşta 10 sn yeter (yükselirken
2.5 kat hızlı yanar). Kanat uçlarından iki yeşil iz çıkar, yedek yandıkça
kısalır; bitince kanatlar kapanır, uçuruma düşülür. Her roket basışı bu
sigortadan yer. İlk portal 2–9 sn hedeflenir ama yukarıda uygun iniş yolu
aranınca çoğu zaman ileri kayar (ölçülen 7–14 sn): boş depoyla düşen yaklaşık
yarı yarıya yetişir.
Yola dönünce depo dolmaz.

Yoldaki limon yeşili kristaller (+3) hep tek
sıra: yol boyunca düz (çapraz değil), 6 m aralıkla; bir yolda aynı anda tek sıra
(çakışanlar elenir). Uçuş yaylarında da aynı aralık. Her yol için o yolun sonundaki boşluğa
gereken enerjinin katı kadar konur: başta 2 katı, 6 km'de 1.2 katı; bu, deponun
doluluğuyla çarpılır (dolu depoda ×0.3, boşta ×1.6; %30'un altında ayrıca ×1.4). Depo %45'in üstündeyse yol
üstündeki kristal dizilerinin bir kısmı hiç konmaz (doluyken ~%80'i). Yollar
~450 m önceden üretildiği için o anki depo seviyesi kullanılır. 12 tohum × 4 dk
ölçümde: dolu depoyla boşa toplanan kristal ~420 → ~45, deponun dolu kaldığı
süre %65 → %14. Başta çoğu kolay yerdedir (inişten sonra bir sıra, pist
ışıklarında ortada bir sıra), giderek zor yerlere kayar:
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
Yine de fizik motoru arabayı bir noktada tutarsa (yerdeyken ~0.12 sn ileri
gidemezse) araba hafifçe kaldırılıp ileri itilir.

## Hız
Temel hız 22 m/s'den (79 km/sa) başlar, her saniye 0.35 m/s artar ve ~94 sn'de
55 m/s'ye (198 km/sa) varır; sonra durmaz, saniyede 0.08 m/s ile 75 m/s'ye
(270 km/sa) kadar artmaya devam eder (ayar panelinde "Zamanla hızlanma", "En
yüksek hız"; sonraki artış `late_acceleration` / `top_speed`). Yollar tahmini
hıza göre üretilir.

## Ayar paneli
Oyun sırasında sol üst köşeye arka arkaya üç kez dokun (PC'de F1): oyun durur,
hız, direksiyon, gaz, atlama, yollar, uçuş, puan, kamera ve ses ayarları açılır.
Listeyi sağ kenardaki turuncu tutamaklı şeritten kaydır (ayarlara yanlışlıkla
dokunmamak için). Değişiklikler hemen uygulanır ve cihazda saklanır. "Kopyala", yalnızca
varsayılandan farklı değerleri tek satırlık metin olarak verir
(`AYARLAR car.start_speed=24; ...`). Panelin listesi `scripts/tuning.gd` içinde.

## Oyun döngüsü
- Üst katman: yollarda git, üstte kaldıkça çarpan artar (x5'e kadar)
- Yoldan düşersen kanatlar açılır, alt katmanda uçarsın; çarpan x1'e döner. Uçarken burun hep ileri
  bakar (en çok ~15° döner), dönüşü gövdenin yatması gösterir; düşerken kalan açı hemen düzelir
- Alt katmanda enerji (roketle aynı depo) azalır, kristal yok; iki parmakla ~8 m
  yükselip alçak kayaların üstünden geçilebilir ama enerji 2.5 kat hızlı biter
- Kayalar parça parça gelir (dağınık alan, eğri büğrü duvar, yığın), boyları ve
  yükseklikleri karışık: alçak (yükselerek geçilir), yüksek (yükselince çarpılır),
  ortada (yalnız direksiyonla geçilir). Her yerde kanat açıklığı kadar en az bir
  geçit kalır; aşağıda kaldıkça sıklaşır (100 m'de 7 → 13 kaya, 20 sn'de)
- Kuyruklu kayalar: 3–6 sn'de bir ~240 m ileride parlayarak belirir, turuncu
  kuyruğuyla senin hizana doğru gelir (30–45 m/s)
- Portal: halkadan girince araba kısa tünelin içinden kayar, tünel 55° yukarı
  kıvrılır, ucundan yukarıdaki bir yola fırlar. İlk portal 2–9 sn (şans), sonra
  6–10 sn arayla

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

  Yarım giriş: rampaya yalnız bir yanın tekerleriyle girersen o yan rampayla
  yükselir, araba yatar (öbür yan yolda kalır, gövde aradaki yükseklikte).
  Rampanın ucunda rampadaki yan fırlar: ağırlık merkezi tam kalkışın yarısıyla
  kalkar, araba öbür yana dönerek ve rampadan uzağa savrularak uçar. Havada
  dönüşün tersine direksiyon kırarak düzeltilir; düzeltmezsen sendeleyerek
  inersin. Rampanın ağzı ve yan duvarları artık çarpma sayılmaz (eskiden yarım
  girişte araba patlıyordu). Test: `tools/ramp_test.gd`.

- ada zinciri (150 m+, yolun ~%20'si): roketli bir boşluktan sonra 4–8 adım kısa
  adalar (her biri 0.7–1.4 sn). Adalar arası küçük boşluklar gazsız atlanır; her
  adımda 1–3 ada yan yana, farklı yükseklikte olabilir; her adadan sonrakilerden en
  az birine yetişilir. Son ada pist ışıklıdır, ardından yine roketli boşluk gelir.
  Her zincir dört çeşitten biridir (aynısı üst üste gelmez):
  - ada: 1–3 ada yan yana, blok adalarında blok ya da yarım çakıl
  - ada_rampa: rampa(up)/rampa(down) adalar ve sık tümsek (kama rampa)
  - ada_çoklu: hep 2–3 ada yan yana, farklı yüksekliklerde
  - ada_eğik: sağda solda uzak adalar, her birinin sonunda karşıya atan eğik rampa

  Yan yana adalar arası 5–5.8 m (adalar birbirine değmez); bir adadan yandakine
  adada kayıp havada hizalanarak geçilir. Adımların ~%40'ı "blok adası": biraz
  uzun (1.6–2 sn) ve geniş, inişten sonra 1–2 blok ya da yarım çakıl.

  Eğik rampadan atılınca yana hız havada korunur (direksiyon ekler ya da ters
  basınca keser); inişte lastikler tutar, yana kalan hızın çoğu söner.

Kalıplar tekrar etmez: bir önceki kalıp hiç gelmez, son üç kalıbın şansı düşer.
Engelli düz yollar 330–470 m'dir (önceden en az 520 m).

### Yol içi: ritim ve olaylar
Düz yollar tek bir kutu değil: kendi içinde bitişik parçalara bölünür ve
üstüne rastgele olaylar dizilir. Her düz yolun bir ruh hâli var: **nefes**
(kısa, tek olay), **orta** (2-3 olay), **yoğun** (3-6 olay, sık). Olay sayısı
dolsa da yolun kalanı ~1 sn'den uzunsa olay eklenmeye devam eder (bu fazladan
olaylar çakılsızdır: blok, kapı, zikzak...).
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
sıklığı, yoğun yolların payı, olaylı düz yolların sıklığı, kristal fırsatları
bununla çarpılır; nefes yollar seyrekleşir. Çarpan mesafeyle büyür (8 km'de iki
katı) ve olaylı kısım da onunla uzar: ilerledikçe yolda daha çok şey olur. Olaylar
arası tepki süresi yine de en az ~0.45 sn kalır; çakıldan sonra ~1.15 sn.
Olaylı yollar en az 6 m (yoğunda 6.6 m) geniştir, yoksa çoğu olay sığmaz.
Olaylı kısım en fazla 1.3 katına uzar ve başka bir kalıbın içindeki düz yol
(vadi dibi, merdiven basamağı) "yoğun" olmaz: yollar uzayıp büyük kalıpları
(ağ, yan yollar, çatal) seyreltmesin. Aç kalma kuralı: uzun süredir gelmeyen
kalıbın şansı artar (her kalıp düzenli görünür). Yol ağında alçak/yüksek yan yol
ağırlıkları rampadan yüksektir.
Kalıpların içindeki kısa düz yollar (rampa yolu, merdiven basamağı...) ve
çatalın geniş birleşme yolu da çakılsız olaylarla dolar; yol ağında parçalar
arasındaki her boş ana yol aralığı dolar. Pist bölgesi (son olaydan yol sonuna)
~1.1 sn: ~0.45 sn tepki + pist ışıklarının ilk yarısında hizalanıp gaz. Dar/geniş
bölümden ve kaymadan çıkınca sonraki sıraya en az ~0.7–0.8 sn. Çakıl tarlası
yalnız 6.5 m'den geniş yollarda (dar yolda arabayı kenardan atıyordu). Ada
zincirlerinde adaların ~%40'ının sonunda tümsek (kama rampa) var.
Çakıl boyları ve tümsekler saniye cinsinden: hızlanınca kısalmazlar. Eğimli
yollara da olay dizilir. Her yol üretildikten sonra blok sıraları baştan sona
denetlenir: bir sıranın *her* geçidinden sonrakinin bir geçidine o hızla
yetişilemiyorsa (tuzak) ya da sıra çakıldan hemen sonra geliyorsa o sıra
kaldırılır.

Tümsek: rampası hızla uzar, eğimi ~%9–15; tepeye varınca fırlarsın (eğimin
verdiği dikey hız ×1.4; o an zemine yapışma kısa süre kapanır, yoksa araba yüzeyde
kalırdı) ve gövde sarsılır (biraz yatma ve burun kalkması, yana itiş): inişi
toparlamak gerekir. Tümsekten sonraki uçuş mesafesi boyunca engel konmaz. Çakıl: arkayı savurur (burun sağa sola sallanır),
etkisi hızla artar (en yüksek hızda ~1.35 kat), çıkınca ~0.8 sn sendelersin.
İniş bölgesi engelsizdir ama seçim vardır: tek sıra kristal (ortada ya da bir
yanda) ya da bir yanda kısa çakıl (yatık yolda
çakıl yok: düz kutu yatık yüzeye oturmuyor, kenarda havada kalıyordu). Pist
sırası ortadadır. Çatalın kolay kolu ve çıkmazın yanındaki ana yol da
olaylarla dolar; yol ağında parçalar alçak yolun yanındaki ana yola da dizilir. 10 km'lik ölçümde 2 sn'den uzun "hiçbir şey olmayan" aralıklar
yolun %45'inden ~%10'una indi (kristaller dahil; `--dump_roads` ile ölçülür).
Kristaller hariç, yalnız blok/çakıl/rampa sayılınca (12 tohum × 4 dk): düz ana
yolda 2 sn'den uzun boşluk %35 → %23, 1.5 sn'den uzun %58 → %44; km başına blok
2.1 → 2.4, rampa/tümsek 0.8 → 1.2.

**Boşluk doldurucu** (kullanıcının kalıp çizimlerinden): her ana yol (bitişik
parçalarıyla) üretildikten sonra 1.2 sn'den (`max_empty_time`) uzun engelsiz
aralıklarına tek blok ya da yarım çakıl girer; yeri, yanı ve sayısı her seferinde
değişir. Başlangıç: inişten 1 sn sonra, ama tam gazla en uzak inişten sonra da
~0.25 sn pay. İniş bölgesine (geniş yolda) yalnız kısa çakıl girer. Yokuş, tümsek
(ve tümsekten sonraki ~1.4 sn uçuş), yatık parçalar, rampaya yaklaşma ve
çakıldan sonraki ~1 sn sayılmaz. Yol ağındaki dönüş inişleri de dolar: inen
araba havada yön verip yerini seçer. Ayrıca:
- adalar: inişte de olabilen çakıl yamaları (adanın tamamı ya da yarısı), kalkıştan
  ~0.7 sn önce biter; son ada doldurucudan geçer
- çatal: kolay kol doldurucudan geçer, zor kolun düz yollarında yarım çakıl,
  geniş birleşme yolunda büyük çakıl
- çıkmaz: ucunda tam genişlik blok (zamanında yandan atlamak gerek)
- eğim ve yatık yollara dokunulmaz
3000 m sonrası (12 tohum): 1.5 sn'den uzun boş düzlük %43 → %30; kalanın çoğu
pist ışıkları bölgesi ve tek parça kısa yollar.

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
- `scripts/lower_layer.gd` — alt katman: kaya alanı, kuyruklu kayalar, tünelli portallar (portal, yukarıdaki bir yola indirecek şekilde yerleştirilir)
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
godot --path . -- --autopilot --deadend --seed=42    # çıkmazlara bilerek girer, ucundaki bloktan önce yandan düşer
godot --path . -- --autopilot --side --seed=42       # yan yollara girer (alçağa düşer, eğik rampaya girer), SIDE_TRIPS yazar
godot --path . -- --autopilot --nocrystal --seed=42  # hiç kristal almaz: ~1.5 km'de enerjisi bitip düşmeli
godot --path . -- --autopilot --dive=8 --seed=5 --fly_energy=12  # az enerjiyle düşer: kanat yedeği (çısss) devreye girer
godot --path . -- --autopilot --seed=5 --dump_roads=/tmp/yol.json   # üretilen bütün yolları, engelleri ve kristalleri yazar
godot --path . -- --nohud --shots=600 --shot_dir=/tmp                 # göstergesiz ekran görüntüsü (tasarım taslakları için)
godot --headless --path . --fixed-fps 60 --quit-after 14400 -- --autopilot --seed=1 | python3 tools/road_variety.py   # 4 dk: kalıp çeşitliliği (ağ, yan yol, çatal...)
godot --path . -- --shots=120,600 --shot_dir=/tmp    # ekran görüntüsü
```

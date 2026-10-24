class_name Palette
extends RefCounted
## Oyunun renkleri. Minimal, İskandinav: kırık beyazlar, griler, kömür
## ve tek bir vurgu rengi (turuncu: araba, portal, kritik uyarılar).

const PAPER := Color("f2f0eb")      # üst katman gökyüzü ve sis
const SNOW := Color("fbfaf7")       # en açık duvar
const MIST := Color("e2dfd8")
const STONE := Color("c9c5bd")
const ASPHALT := Color("2a2c30")    # yol yüzeyi
const GRAPHITE := Color("1c1e22")   # alt katman gökyüzü
const SLATE := Color("7c8087")      # alt katman kayaları (koyu zeminde seçilsin)
const INK_DARK := Color("232529")   # açık zeminde yazı
const INK_LIGHT := Color("f2f0eb")  # koyu zeminde yazı
const ACCENT := Color("ff5a1f")

const WALLS: Array[Color] = [SNOW, MIST, STONE]

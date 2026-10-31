// Runny Bölüm Tasarımcısı: oyunun fiziği ve tasarım kontrolleri.
// Değerler oyundaki car.gd / road_generator.gd ile aynı; oyun değişirse burası da güncellenir.
// Hem tarayıcıda (window.RunnyPhysics) hem node'da (require) çalışır.
(function (root) {
  'use strict';

  const CAR = {
    startSpeed: 40, maxSpeed: 80, acceleration: 1.5, lateAcceleration: 0.15, topSpeed: 80,
    gravity: 28, launchVelocity: 8, boostBonus: 1.35, boostMaxExtra: 45,
    carLen: 3.9, halfWidth: 1.1, steerSpeed: 11, airControl: 0.8, bumpLaunch: 1.4,
    lightsTime: 1.1, maxSlopeDeg: 21, maxBankDeg: 17,
    // Garajın en yavaş (Gezgin) ve en hızlı (Falcon) arabasının hız katı (scripts/car_model.gd STATS);
    // en yavaş araba en uzun boşluklara tam gazla en az slowMargin payla konmalı (kıl payı)
    slowMul: 0.96, fastMul: 1.08, slowMargin: 1.0, slowName: 'Gezgin',
    // Garajın en geniş arabasının (Gezgin, tekerleriyle) yarı genişliği: blok geçitleri buna göre
    wideHalf: 1.27, wideName: 'Gezgin',
  };

  // Kat ön ayarları (yükseklik m, ana seviye 0)
  const TIERS = { low: -4, mid: 0, high: 3 };

  // Başlangıçtan d metre sonra arabanın hızı (oyundaki hızlanmayla)
  function speedAt(d) {
    const v0 = CAR.startSpeed, a = CAR.acceleration;
    let v = Math.sqrt(v0 * v0 + 2 * a * Math.max(d, 0));
    if (v > CAR.maxSpeed) {
      const dMax = (CAR.maxSpeed ** 2 - v0 * v0) / (2 * a);
      v = Math.sqrt(CAR.maxSpeed ** 2 + 2 * CAR.lateAcceleration * (d - dMax));
    }
    return Math.min(v, CAR.topSpeed);
  }
  // Roketle hız: hesapta %90 gaz (oyundaki gibi), tam roket ayrıca
  const vBoost = (v) => v + 0.9 * Math.min(v * CAR.boostBonus, CAR.boostMaxExtra);
  // Tam roket, garajın en hızlı arabasıyla (iniş en uzak: yol bunu taşımalı)
  const vFull = (v) => { const f = v * CAR.fastMul; return f + Math.min(f * CAR.boostBonus, CAR.boostMaxExtra); };
  // Kalkıştan (dikey hız vy) dh yüksekliğine inene kadar süre; çıkılamıyorsa NaN
  function flightTime(dh, vy) {
    const d = vy * vy - 2 * CAR.gravity * dh;
    if (d < 0) return NaN;
    return (vy + Math.sqrt(d)) / CAR.gravity;
  }
  const clearEnd = (v) => Math.min(Math.max(v * CAR.lightsTime * 0.6, 14), 45) + v * 0.45;
  const clearStart = (v, landFar) => Math.max(vBoost(v) * 0.6 + 10, landFar + vBoost(v) * 0.55 + 6);

  const num = (v, d) => (typeof v === 'number' && isFinite(v) ? v : d);
  const pEnd = (p) => p.z0 + p.len;
  const h0 = (p) => num(p.h0, 0);
  const h1 = (p) => num(p.h1, num(p.h0, 0));
  const hAt = (p, z) => h0(p) + (h1(p) - h0(p)) * Math.min(Math.max((z - p.z0) / Math.max(p.len, 0.01), 0), 1);

  // Engel bu parçanın üstünde mi (oyundaki _custom_on ile aynı)
  function isOn(o, p) {
    return o.z0 >= p.z0 - 0.5 && o.z0 <= pEnd(p) + 0.5 && Math.abs(o.x - p.x) <= p.w / 2 + 0.5;
  }
  function hostOf(level, o) {
    let best = null;
    for (const p of level.pieces) if (isOn(o, p) && !best) best = p;
    return best;
  }
  // Ucunda boşluksuz devam eden parça
  function successor(level, p) {
    for (const q of level.pieces) {
      if (q === p) continue;
      if (Math.abs(q.z0 - pEnd(p)) < 0.6 && Math.abs(h0(q) - h1(p)) < 0.3 &&
          Math.abs(q.x - p.x) < (q.w + p.w) / 2 - 1) return q;
    }
    return null;
  }
  // Yollar başlangıç sırasıyla (girişten çıkışa). "Yan yol" ayrımı yok: hepsi yol
  function mainPath(level) {
    return [...level.pieces].sort((a, b) => a.z0 - b.z0 || num(a.id, 0) - num(b.id, 0));
  }
  // Çıkış: en ileride biten yol (oyun sonraki yolları buradan bağlar)
  function exitOf(level) {
    let best = null;
    for (const p of mainPath(level)) if (!best || pEnd(p) > pEnd(best)) best = p;
    return best;
  }
  const hasDeadend = (level, p) => (level.obstacles || []).some((o) => o.kind === 'deadend' && hostOf(level, o) === p);

  // A'nın sonundan B'ye atlama: mesafeler A'nın ucundan (z) ölçülür
  function jump(level, A, B) {
    const at = num(level.at, 0);
    const v = speedAt(at + pEnd(A));
    const slope = (h1(A) - h0(A)) / Math.max(A.len, 0.01);
    const dh = h0(B) - h1(A);
    const gap = B.z0 - pEnd(A);
    const vb = vBoost(v), vf = vFull(v);
    const vy = CAR.launchVelocity + v * slope;
    const vyB = CAR.launchVelocity + vb * slope;
    const vyF = CAR.launchVelocity + vf * slope;
    const t0 = flightTime(dh, vy), tB = flightTime(dh, vyB), tF = flightTime(dh, vyF);
    const reach0 = CAR.carLen + v * t0;          // gazsız en uzak (ön uç)
    const reachB = CAR.carLen + vb * tB;         // roketle en uzak
    const reachF = CAR.carLen + vf * tF;         // tam roket (iniş en uzak)
    // En yavaş araba: aynı gazla, hızı katı kadar düşük (gazın ek hızı aynı)
    const dvS = v * (1 - CAR.slowMul);
    const reachS = CAR.carLen + (vb - dvS) * flightTime(dh, vyB - dvS * slope);
    const lateral = CAR.steerSpeed * CAR.airControl * (isNaN(tB) ? 0 : tB);
    const need = Math.max(0, Math.abs(B.x - A.x) - (A.w / 2 + B.w / 2) + 2 * CAR.halfWidth + 0.5);
    return { A, B, v, vb, gap, dh, t0, tB, reach0, reachB, reachF, reachS, lateral, need,
      landNear: Math.max(B.z0, pEnd(A) + Math.min(reach0, reachB)),
      landFar: pEnd(A) + (isNaN(reachF) ? reachB : reachF) };
  }

  // Yolun ucundan gidilebilen yollar: [{ q, free }]. Atlanabilir boşluk ya da boşluksuz aşağı
  // basamak; free: garajın en yavaş arabası (Gezgin) gazsız yetişir (en az slowMargin payla)
  function onward(level, A) {
    const out = [];
    const v = speedAt(num(level.at, 0) + pEnd(A));
    const vs = v * CAR.slowMul;
    const slope = (h1(A) - h0(A)) / Math.max(A.len, 0.01);
    for (const q of level.pieces) {
      if (q === A) continue;
      const gap = q.z0 - pEnd(A);
      if (gap < -0.6 || gap > 150) continue;
      const lat = Math.max(0, Math.abs(q.x - A.x) - (q.w + A.w) / 2);
      if (lat > 8) continue;
      const J = jump(level, A, q);
      const t0 = flightTime(J.dh, CAR.launchVelocity + vs * slope);
      const lat0 = CAR.steerSpeed * CAR.airControl * (isNaN(t0) ? 0 : t0);
      // Yana kayma payı atlama kontrolündeki gibi (%80): yana yetişilemeyen yol seçenek değil
      if (gap < 0.6) {
        if (h0(q) <= h1(A) + 0.3 && J.need <= lat0 * 0.8) out.push({ q, free: true });
        continue;
      }
      if (isNaN(J.reachB) || gap > J.reachB - 2.5 || J.need > J.lateral * 0.8) continue;
      out.push({ q, free: !isNaN(t0) && gap <= CAR.carLen + vs * t0 - CAR.slowMargin && J.need <= lat0 * 0.8 });
    }
    return out;
  }
  // Pist ışıkları (gaz bölgesi): yolun ucundan gaz isteyen bir atlama varsa, yanında gazsız
  // yetişilen yol olsa da. Bitişik devamı ya da çıkmazı olan yolda yok; çıkış yolunda hep var
  // (oyun sonraki yolu ardına atlamayla bağlar); gidilecek yol yoksa da var
  function needsLights(level, A) {
    if (successor(level, A) || hasDeadend(level, A)) return false;
    if (A === exitOf(level)) return true;
    const on = onward(level, A);
    return !on.length || on.some((o) => !o.free);
  }

  // Rampa/tümsek uçuşu: ileri mesafe, uçuş süresi, iniş z'si
  function rampFlight(level, o, host) {
    const at = num(level.at, 0);
    const v = speedAt(at + o.z0);
    const rise = num(o.rise, 1.6), len = Math.max(num(o.len, 8), 0.5);
    if (o.kind === 'bump') {
      const half = len / 2;
      const vy = v * rise / half * CAR.bumpLaunch + 1;
      const t = 2 * vy / CAR.gravity;
      return { v, t, vy0: vy, from: o.z0 + half, land: o.z0 + half + v * t, x: o.x, top: hAt(host, o.z0) + rise };
    }
    const vy = CAR.launchVelocity + v * rise / len;
    const top = hAt(host, o.z0) + rise;
    const t = flightTime(-rise, vy);
    let dist = CAR.carLen + v * t;
    let x = o.x;
    if (o.kind === 'kick') x = o.x + Math.sign(num(o.dir, 1)) * num(o.dx, 8);
    return { v, t, vy0: vy, from: o.z0 + len, land: o.z0 + len + dist, x, top, vy };
  }

  // Tasarımı kontrol eder: { issues:[{level:'error'|'warn'|'ok', text, ids:[...]}], jumps, flights, stats }
  function analyze(level) {
    const issues = [];
    const add = (lvl, text, ids, at) => issues.push({ level: lvl, text, ids: ids || [], at });
    const pieces = level.pieces || [];
    const obstacles = level.obstacles || [];
    const at = num(level.at, 0);
    const jumps = [], flights = [], zones = [];
    if (!pieces.length) {
      add('warn', 'Henüz yol yok. Soldan bir yolu tuvale sürükle.');
      return { issues, jumps, flights, zones, stats: { length: 0, time: 0, jumps: 0, crystals: 0, difficulty: 0 } };
    }
    const path = mainPath(level);
    const tanMax = Math.tan(CAR.maxSlopeDeg * Math.PI / 180);
    for (const p of pieces) {
      if (Math.abs(h1(p) - h0(p)) / Math.max(p.len, 0.01) > tanMax + 1e-6)
        add('error', `Çok dik yokuş: en fazla ${CAR.maxSlopeDeg}°. Yolu uzat ya da yüksekliği azalt.`, [p.id], p.z0);
      if (p.w < 3) add('warn', `Çok dar yol (${p.w.toFixed(1)} m): araba ~2.2 m geniş.`, [p.id], p.z0);
      if (Math.abs(num(p.bank, 0)) > CAR.maxBankDeg) add('warn', `Yatıklık en fazla ${CAR.maxBankDeg}°; oyun bu kadarla sınırlar.`, [p.id], p.z0);
    }
    // Üst üste binen yollar (farklı yükseklikte iç içe: araba geçemez)
    for (let i = 0; i < pieces.length; i++) for (let j = i + 1; j < pieces.length; j++) {
      const a = pieces[i], b = pieces[j];
      const oz = Math.min(pEnd(a), pEnd(b)) - Math.max(a.z0, b.z0);
      const ox = Math.min(a.x + a.w / 2, b.x + b.w / 2) - Math.max(a.x - a.w / 2, b.x - b.w / 2);
      if (oz > 1 && ox > 0.5) {
        const dz = Math.max(a.z0, b.z0);
        const dh = Math.abs(hAt(a, dz) - hAt(b, dz));
        if (dh < 4) add('error', 'Üst üste binen yollar: aralarında en az 4 m yükseklik farkı olmalı ya da yan yana dursunlar.', [a.id, b.id], dz);
      }
    }
    // Atlamanın inişi: tam roketle yolu aşmasın, iniş bölgesinde engel olmasın
    function landing(J, B) {
      const A = J.A;
      const landFar = J.landFar - B.z0;
      if (J.landFar > pEnd(B) - 2) {
        add('error', `Tam roketle yolun ötesine iniliyor: ${landFar.toFixed(0)} m'ye kadar, yol ${B.len.toFixed(0)} m. Yolu uzat ya da boşluğu büyüt.`, [B.id], B.z0);
      } else if (pEnd(B) - J.landFar < J.v * 1.2 && !successor(level, B)) {
        const left = pEnd(B) - J.landFar;
        add(left < J.v * 0.6 ? 'error' : 'warn', `İnişten sonra gaz için az yol kalıyor (${left.toFixed(0)} m): roket basmaya vakit yok, sonraki boşluğa düşülür.`, [B.id], B.z0);
      }
      if (J.need > J.lateral * 0.8) {
        J.bad = true;
        add('error', `Yana çok uzak: havada ancak ${J.lateral.toFixed(1)} m kayılır, ${J.need.toFixed(1)} m gerek.`, [A.id, B.id], pEnd(A));
      }
      // İniş bölgesinde engel olmasın (roket hâlâ yanar)
      const vB = speedAt(at + B.z0);
      const calm = B.z0 + clearStart(vB, landFar);
      zones.push({ id: B.id, kind: 'calm', z0: B.z0, z1: Math.min(calm, pEnd(B)) });
      // Tam roketli inişten ~0.3 sn sonrasına kadar: araba hâlâ roket hızında (hata);
      // oyunun kendi yollarındaki temkinli boş bölge (uyarı)
      const hot = J.landFar + J.vb * 0.3;
      for (const o of obstacles) {
        if (o.kind !== 'deadend' && hostOf(level, o) === B && o.z0 < calm) {
          const strong = (o.kind === 'bump' || o.kind === 'ramp' || o.kind === 'kick' || o.kind === 'block') && o.z0 < hot;
          add(strong ? 'error' : 'warn', strong
            ? `${KIND_NAMES[o.kind] || 'Engel'} iniş noktasının hemen ardında: roketle inen araba buna çarpar ya da fırlar. En az ${(hot - B.z0).toFixed(0)} m içeri al.`
            : `${KIND_NAMES[o.kind] || 'Engel'} inişe yakın: oyun kendi yollarında ilk ${(calm - B.z0).toFixed(0)} metreyi boş bırakır.`, [o.id], o.z0);
        }
      }
    }
    // Giriş: oyun kalıba önceki yoldan atlayarak girer (önerilen boşlukla, aynı hizada);
    // ilk yolun başı da iniş bölgesidir. Roket hâlâ yanarken gelinir: engel hata, çakıl uyarı.
    if (path.length) {
      const E = path[0];
      const pre = { id: 0, x: E.x, w: E.w, z0: E.z0 - 100, len: 100, h0: h0(E), h1: h0(E) };
      pre.z0 -= suggestGap(level, pre, 0);
      const J = jump(level, pre, E);
      if (!isNaN(J.reachB)) {
        const calm = E.z0 + clearStart(speedAt(at + E.z0), J.landFar - E.z0);
        zones.push({ id: E.id, kind: 'calm', z0: E.z0, z1: Math.min(calm, pEnd(E)) });
        for (const o of obstacles) {
          if (o.kind === 'deadend' || hostOf(level, o) !== E || o.z0 >= calm) continue;
          add(o.kind === 'gravel' ? 'warn' : 'error', `${KIND_NAMES[o.kind] || 'Engel'} girişin iniş bölgesinde: oyun bu kalıba önceki yoldan roketle atlayarak girer, ilk ${(calm - E.z0).toFixed(0)} metre boş kalmalı.`, [o.id], o.z0);
        }
      }
    }
    // Ana yol boyunca atlamalar
    let speedSum = 0;
    for (let i = 0; i + 1 < path.length; i++) {
      const A = path[i];
      if (successor(level, A)) continue;
      // Sonraki yol: ileride, en az kaymayla ulaşılan (yan yana ana yollar ayrı hatlar)
      let B = null, best = Infinity;
      for (const q of path) {
        if (q === A || q.z0 < pEnd(A) - 0.6 || q.z0 > pEnd(A) + 150) continue;
        const lat = Math.max(0, Math.abs(q.x - A.x) - (q.w + A.w) / 2);
        if (lat > 8) continue;  // yana bu kadar uzak yol ayrı bir hat
        const cost = (q.z0 - pEnd(A)) + lat * 12;
        if (cost < best) { best = cost; B = q; }
      }
      if (!B) {
        if (pEnd(A) < Math.max(...path.map(pEnd)) - 1 && !hasDeadend(level, A))
          add('warn', 'Bu yolun sonundan inilecek yol yok: araba uçuşa düşer (çıkmaz istiyorsan Çıkmaz koy).', [A.id], pEnd(A));
        continue;
      }
      if (B.z0 - pEnd(A) < 0.6) continue;
      const J = jump(level, A, B);
      jumps.push(J);
      const g = J.gap;
      if (isNaN(J.reachB)) {
        J.bad = true;
        add('error', `Çok yüksek basamak (${J.dh.toFixed(1)} m): düz yoldan çıkılamaz, önüne rampa koy.`, [A.id, B.id], pEnd(A));
      } else if (g > J.reachB - 2.5) {
        J.bad = true;
        add('error', `Atlanamaz: ${g.toFixed(0)} m boşluk, bu hızda en çok ${(J.reachB - 2.5).toFixed(0)} m (roketle). Yolları yaklaştır.`, [A.id, B.id], pEnd(A));
      } else if (!(g <= J.reachS - CAR.slowMargin)) {
        J.slow = true;
        add('warn', `En yavaş araba (${CAR.slowName}) yetişemez: ${g.toFixed(0)} m boşluk, tam gazla en çok ${(J.reachS - CAR.slowMargin).toFixed(0)} m. Bilerek yaptıysan yanına alternatif yol koy.`, [A.id, B.id], pEnd(A));
      } else if (g < J.reach0 - 1) {
        J.easy = true;
        add('ok', `${g.toFixed(0)} m boşluk gazsız da geçiliyor (kolay).`, [A.id, B.id], pEnd(A));
      }
      if (!J.bad) landing(J, B);
      speedSum += 1;
    }
    // Her ana yolun sonunda pist bölgesi: engel olmasın (hizalanıp gaz)
    for (const p of path) {
      if (!needsLights(level, p)) continue;
      const v = speedAt(at + pEnd(p));
      const runway = pEnd(p) - clearEnd(v);
      zones.push({ id: p.id, kind: 'runway', z0: Math.max(runway, p.z0), z1: pEnd(p) });
      for (const o of obstacles) {
        if (o.kind !== 'deadend' && hostOf(level, o) === p && o.z0 + num(o.len, 0) > runway)
          add('warn', `${KIND_NAMES[o.kind] || 'Engel'} pist bölgesinde: yolun son ${clearEnd(v).toFixed(0)} metresi gaz için boş kalmalı.`, [o.id], o.z0);
      }
    }
    // Rampa ve tümsek uçuşları
    for (const o of obstacles) {
      if (!['ramp', 'kick', 'bump'].includes(o.kind)) continue;
      const host = hostOf(level, o);
      if (!host) { add('error', `${KIND_NAMES[o.kind]} bir yolun üstünde değil.`, [o.id], o.z0); continue; }
      const F = rampFlight(level, o, host);
      F.o = o; F.host = host;
      flights.push(F);
      if (isNaN(F.t)) continue;
      // İnilen yol: uçuş yayının indiği ilk (en yüksek) yol; yay yukarı da çıkar,
      // daha yüksek bir yola da konulabilir
      let landOn = null;
      const cands = level.pieces.filter((p) => Math.abs(F.x - p.x) <= p.w / 2 + 0.3)
        .sort((a, b) => hAt(b, F.from) - hAt(a, F.from));
      for (const p of cands) {
        const t = flightTime(hAt(p, F.from + 10) - F.top, F.vy0);
        if (isNaN(t)) continue;
        const z = F.from + (o.kind === 'bump' ? 0 : CAR.carLen) + F.v * t;
        if (z >= p.z0 - 1 && z <= pEnd(p)) { landOn = p; F.land = z; break; }
      }
      F.landOn = landOn;
      if (!landOn) {
        add('error', `${KIND_NAMES[o.kind]} boşluğa atıyor: ~${(F.land - F.from).toFixed(0)} m uçuşun sonunda yol yok.`, [o.id], o.z0);
      } else if (!successor(level, landOn) && pEnd(landOn) - F.land < clearEnd(F.v)) {
        const left = Math.max(0, pEnd(landOn) - F.land);
        add(left < F.v * 0.6 ? 'error' : 'warn', `${KIND_NAMES[o.kind]} sonrası gaz için az yol: iniş yolun sonuna ${left.toFixed(0)} m kala.`, [o.id], o.z0);
      }
    }
    // Yan yola girişler (bir yolun ucundan, ana sıradaki atlamanın gitmediği yanındaki yola):
    // yalnız gösterim (iniş bölgesi ve bağlantı çizgisi; atlanamıyorsa kırmızı)
    for (const S of path) {
      // Bir yolun ucundan boşluksuz (aynı ya da aşağı) devam eden yol: atlama yok
      const touched = pieces.some((r) => r !== S && Math.abs(S.z0 - pEnd(r)) <= 0.6 &&
        Math.abs(S.x - r.x) < (S.w + r.w) / 2 && h0(S) <= h1(r) + 0.3);
      if (S === path[0] || touched || jumps.some((j) => j.B === S)) continue;
      let A = null, best = Infinity;
      for (const q of pieces) {
        if (q === S || successor(level, q)) continue;
        const gap = S.z0 - pEnd(q);
        if (gap < 0.6 || gap > 150) continue;
        const lat = Math.max(0, Math.abs(q.x - S.x) - (q.w + S.w) / 2);
        if (lat > 8) continue;
        if (gap + lat * 12 < best) { best = gap + lat * 12; A = q; }
      }
      if (!A) continue;
      const J = jump(level, A, S);
      J.side = true; J.view = true;
      J.bad = isNaN(J.reachB) || J.gap > J.reachB - 2.5;
      jumps.push(J);
    }
    // Akış: girişten çıkışa giden bir yol var mı (bitişik devam, atlanabilen boşluk, rampa uçuşu)
    const exitP = exitOf(level);
    if (path.length > 1 && exitP) {
      const next = (A) => {
        const s = successor(level, A);
        const out = s ? [s] : onward(level, A).map((o) => o.q);
        for (const F of flights) if (F.host === A && F.landOn) out.push(F.landOn);
        return out;
      };
      const seen = new Set([path[0]]), todo = [path[0]];
      while (todo.length) for (const q of next(todo.pop())) if (!seen.has(q)) { seen.add(q); todo.push(q); }
      if (!seen.has(exitP))
        add('warn', 'Akış kopuk: girişten çıkışa giden bir yol yok. Yolları birbirine bağla (bitişik yol, atlanabilir boşluk ya da rampa).', pieces.filter((p) => !seen.has(p)).map((p) => p.id), exitP.z0);
    }
    // Bloklar yolu kapatmasın: her blok sırasında arabanın geçeceği bir geçit kalmalı
    const needLane = 2 * CAR.wideHalf + 1.0;
    for (const p of pieces) {
      const blocks = obstacles.filter((o) => o.kind === 'block' && hostOf(level, o) === p).sort((a, b) => a.z0 - b.z0);
      const seen = new Set();
      for (const o of blocks) {
        if (seen.has(o)) continue;
        const row = blocks.filter((b) => Math.abs(b.z0 - o.z0) < CAR.carLen + 2);
        row.forEach((b) => seen.add(b));
        const ivs = row.map((b) => [b.x - b.w / 2, b.x + b.w / 2]).sort((a, b) => a[0] - b[0]);
        let left = p.x - p.w / 2, best = 0;
        for (const [a, b] of ivs) { best = Math.max(best, a - left); left = Math.max(left, b); }
        best = Math.max(best, p.x + p.w / 2 - left);
        if (best < needLane - 1e-6) add('error', `Bloklar yolu kapatıyor: en geniş araba (${CAR.wideName}) için en az ${needLane.toFixed(1)} m geçit gerek, ${Math.max(best, 0).toFixed(1)} m var.`, row.map((b) => b.id), o.z0);
      }
    }
    // Çıkış yolu
    const exit = exitOf(level);
    if (exit && obstacles.some((o) => hostOf(level, o) === exit && o.kind !== 'deadend' && o.z0 > pEnd(exit) - clearEnd(speedAt(at + pEnd(exit)))))
      add('warn', 'Çıkış yolunun sonu boş olmalı: oyun sonraki yolu buradan bağlar.', [exit.id], pEnd(exit));

    // Özet
    const zMin = Math.min(...pieces.map((p) => p.z0));
    const zMax = Math.max(...pieces.map(pEnd));
    const length = zMax - zMin;
    const vMid = speedAt(at + length / 2);
    const nObs = obstacles.length;
    const narrow = pieces.filter((p) => p.w < 5).length;
    const hard = jumps.filter((j) => !j.easy && !j.side).length;
    let diff = 1 + hard * 0.45 + nObs * 0.18 + narrow * 0.4 + (vMid > 45 ? 0.6 : 0) + flights.length * 0.2;
    diff = Math.max(1, Math.min(5, Math.round(diff)));
    const crystals = crystalPreview(level, analyzeLite(level, jumps)).length;
    if (!issues.some((i) => i.level !== 'ok')) add('ok', 'Kontrollerde sorun yok.');
    return { issues, jumps, flights, zones, stats: { length, time: length / vMid, jumps: jumps.filter((j) => !j.side).length, crystals, difficulty: diff, speed: vMid } };
  }
  const analyzeLite = (level, jumps) => ({ jumps });

  // Oyunun kristal algoritmasına yakın önizleme (yer ve sayı yaklaşık)
  function crystalPreview(level, A) {
    if (level.crystals === false) return [];
    const out = [];
    const at = num(level.at, 0);
    const sp = 6;
    for (const p of mainPath(level)) {
      const v = speedAt(at + p.z0);
      const landZ = p.z0 + v * 0.4;
      for (let i = 0; i < 4 && landZ + i * sp < pEnd(p) - 8; i++) out.push({ x: p.x, z: landZ + i * sp, on: p.id });
      if (!successor(level, p)) {
        const zEnd = pEnd(p) - 4;
        for (let i = 0; i < 3 && zEnd - i * sp > landZ + 4 * sp; i++) out.push({ x: p.x, z: zEnd - i * sp, on: p.id });
      }
    }
    for (const J of (A && A.jumps) || []) {
      if (J.bad || J.view || J.gap < 6) continue;
      for (let i = 1; i <= 3; i++) {
        const f = i / 4;
        out.push({ x: J.A.x + (J.B.x - J.A.x) * f, z: pEnd(J.A) + J.gap * f, air: true });
      }
    }
    return out;
  }

  // Bir yolun ardına önerilen boşluk (oyunun seçtiği gibi: pencerenin ~%35'i)
  function suggestGap(level, A, dh) {
    const at = num(level.at, 0);
    const v = speedAt(at + pEnd(A));
    const slope = (h1(A) - h0(A)) / Math.max(A.len, 0.01);
    const vy = CAR.launchVelocity + v * slope;
    const vb = vBoost(v);
    const vyB = CAR.launchVelocity + vb * slope;
    const lo = CAR.carLen + v * flightTime(dh, vy) + 1.5;
    const hi = CAR.carLen + vb * flightTime(dh, vyB) - 2.5;
    if (isNaN(lo) || isNaN(hi)) return 25;
    return Math.round(lo + (Math.max(hi, lo) - lo) * 0.35);
  }
  // Yolun en az ne kadar uzun olması gerekir (iniş + gaz)
  function minRoadLength(level, z, gap, dh) {
    const v = speedAt(num(level.at, 0) + z);
    const t = flightTime(dh || 0, CAR.launchVelocity);
    const landFar = CAR.carLen + vFull(v) * t - (gap || 25);
    return Math.ceil(Math.max(landFar, 0) + v * 1.2 + 4);
  }

  // ------------------------------------------------------------------ türevler
  // Kalıptan güvenli çeşitleme. Oyun da her gelişte aynı kurallarla gerçek zamanlı türetir
  // (scripts/level_check.gd); kurallar değişirse ikisi birlikte güncellenir.
  function rng32(seed) {
    let a = seed >>> 0;
    return () => {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const r1v = (v) => Math.round(v * 10) / 10;
  const VARY_OPS = ['gap', 'len', 'width', 'rows', 'swap', 'rise'];
  const VARY_TAGS = { gap: 'boşluklar', len: 'yollar uzun', width: 'genişlik', rows: 'engel düzeni', swap: 'çakıl ↔ blok', rise: 'rampa yüksekliği' };
  // Bir kez çeşitle: ops listesindeki işlemler (sırayla: yerel olanlar önce, z kaydıranlar sonra)
  function varyOnce(level, rnd, ops) {
    const L = JSON.parse(JSON.stringify(level));
    delete L.variants;
    const U = (a, b) => a + (b - a) * rnd();
    const changed = new Set(), tags = [];
    // Z'den sonra başlayan yolları ve üstlerindeki engelleri d kadar ileri al
    const shiftFrom = (Z, d) => {
      const H = new Map(L.obstacles.map((o) => [o, hostOf(L, o)]));
      const moved = new Set(L.pieces.filter((p) => p.z0 >= Z - 0.01));
      for (const p of moved) { p.z0 = r1v(p.z0 + d); changed.add(p.id); }
      for (const o of L.obstacles) {
        const h = H.get(o);
        if (h ? moved.has(h) : o.z0 >= Z - 0.01) { o.z0 = r1v(o.z0 + d); changed.add(o.id); }
      }
    };
    const has = (op) => ops.includes(op);
    if (has('rise')) {
      const n0 = changed.size;
      for (const o of L.obstacles) if (['ramp', 'kick', 'bump'].includes(o.kind)) {
        o.rise = Math.round(Math.min(Math.max(num(o.rise, 1.6) * U(0.85, 1.15), 0.3), 4) * 20) / 20; changed.add(o.id);
      }
      if (changed.size > n0) tags.push(VARY_TAGS.rise);
    }
    if (has('swap')) {
      const n0 = changed.size;
      for (const o of L.obstacles) {
        if (o.kind === 'block' && o.w <= 3 && rnd() < 0.4) { o.kind = 'gravel'; o.w = 3; o.z0 = r1v(o.z0 - 4); o.len = 10; changed.add(o.id); }
        else if (o.kind === 'gravel' && o.w <= 3.5 && rnd() < 0.4) { o.kind = 'block'; o.w = 2; o.z0 = r1v(o.z0 + num(o.len, 10) / 2); o.len = 1.2; changed.add(o.id); }
      }
      if (changed.size > n0) tags.push(VARY_TAGS.swap);
    }
    if (has('rows')) {
      const n0 = changed.size;
      for (const p of L.pieces) {
        const on = L.obstacles.filter((o) => o.kind !== 'kick' && o.kind !== 'deadend' && hostOf(L, o) === p).sort((a, b) => a.z0 - b.z0);
        const seen = new Set();
        for (const o of on) {
          if (seen.has(o)) continue;
          const row = on.filter((b) => Math.abs(b.z0 - o.z0) < 10);
          row.forEach((b) => seen.add(b));
          // Eğik rampanın sırası taşınmaz (yan yola atar)
          if (L.obstacles.some((k) => k.kind === 'kick' && hostOf(L, k) === p && Math.abs(k.z0 - o.z0) < 12)) continue;
          if (rnd() < 0.5) for (const b of row) { b.x = r1v(2 * p.x - b.x); changed.add(b.id); }
          if (rnd() < 0.5) {
            const lo = Math.max(...row.map((b) => p.z0 + 1 - b.z0)), hi = Math.min(...row.map((b) => pEnd(p) - 1 - num(b.len, 1) - b.z0));
            const dz = Math.round(Math.min(Math.max(U(-8, 8), lo), hi));
            if (dz) for (const b of row) { b.z0 = r1v(b.z0 + dz); changed.add(b.id); }
          }
        }
      }
      if (changed.size > n0) tags.push(VARY_TAGS.rows);
    }
    if (has('width')) {
      const n0 = changed.size;
      for (const p of L.pieces) {
        const nw = Math.max(4.5, Math.round(p.w * U(0.86, 1.14) * 2) / 2);
        if (nw === p.w) continue;
        for (const o of L.obstacles.filter((q) => hostOf(L, q) === p)) {
          o.x = r1v(p.x + (o.x - p.x) * nw / p.w);
          if (o.kind === 'bump' || o.kind === 'deadend') o.w = nw;
          changed.add(o.id);
        }
        p.w = nw; changed.add(p.id);
      }
      if (changed.size > n0) tags.push(VARY_TAGS.width);
    }
    const path = () => mainPath(L);
    if (has('len')) {
      const n0 = changed.size;
      const pp = path();
      for (const p of pp.slice(0, -1).reverse()) {
        if (successor(L, p)) continue;
        const ext = Math.round(p.len * U(0, 0.15));
        if (ext < 2) continue;
        shiftFrom(pEnd(p) + 0.01, ext);
        p.len += ext; changed.add(p.id);
      }
      if (changed.size > n0) tags.push(VARY_TAGS.len);
    }
    if (has('gap')) {
      const n0 = changed.size;
      const pp = path();
      for (let i = pp.length - 2; i >= 0; i--) {
        const A = pp[i], B = pp[i + 1];
        const g = B.z0 - pEnd(A);
        if (g < 0.6 || successor(L, A)) continue;
        const d = Math.round(g * (U(0.85, 1.15) - 1));
        if (d) shiftFrom(B.z0, d);
      }
      if (changed.size > n0) tags.push(VARY_TAGS.gap);
    }
    return { level: L, tags, changed: [...changed] };
  }
  const issueCount = (A, lvl) => A.issues.filter((i) => i.level === lvl).length;
  // Kalıbın imzası: aynı türev iki kez gelmesin
  const signature = (l) => JSON.stringify([l.pieces.map((p) => [p.x, p.w, p.z0, p.len, num(p.h0, 0), num(p.h1, 0)]),
    l.obstacles.map((o) => [o.kind, o.x, o.w, o.z0, o.len, num(o.rise, 0)])]);
  // Hatanın kimliği: türü ve ilgili parçalar (metindeki ölçüler hariç)
  const errorKeys = (A) => A.issues.filter((i) => i.level === 'error').map((i) => i.text.replace(/[\d.,]+/g, '#') + '|' + i.ids.join(','));
  // Geçerli bir türev: tasarımcının kalıbında olmayan yeni hata yok (kalıbın bilerek zor yerleri
  // türevde de olabilir), uyarı asıl kalıptan fazla değil, daha önce görülmemiş
  function vary(level, seed, avoid) {
    const base = analyze(level);
    const baseWarn = issueCount(base, 'warn');
    const baseErr = new Set(errorKeys(base));
    const seen = new Set(avoid || []);
    seen.add(signature(level));
    for (let t = 0; t < 40; t++) {
      const rnd = rng32((seed * 7919 + t * 104729) >>> 0);
      const ops = VARY_OPS.filter(() => rnd() < 0.45);
      if (!ops.length) ops.push(VARY_OPS[Math.floor(rnd() * VARY_OPS.length)]);
      const V = varyOnce(level, rnd, ops);
      const sig = signature(V.level);
      if (!V.tags.length || seen.has(sig)) continue;
      const A = analyze(V.level);
      if (errorKeys(A).every((k) => baseErr.has(k)) && issueCount(A, 'warn') <= baseWarn) return { ...V, sig };
    }
    return null;
  }

  const KIND_NAMES = { ramp: 'Rampa', kick: 'Eğik rampa', bump: 'Tümsek', gravel: 'Çakıl', block: 'Blok', deadend: 'Çıkmaz' };

  const api = { CAR, TIERS, speedAt, vBoost, vFull, flightTime, clearEnd, clearStart, jump, rampFlight,
    analyze, crystalPreview, suggestGap, minRoadLength, mainPath, exitOf, onward, needsLights, successor, hostOf, isOn, hAt, pEnd, KIND_NAMES,
    vary, varyOnce, signature, rng32 };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.RunnyPhysics = api;
})(typeof window !== 'undefined' ? window : this);

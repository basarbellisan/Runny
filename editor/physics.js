// Runny Bölüm Tasarımcısı: oyunun fiziği ve tasarım kontrolleri.
// Değerler oyundaki car.gd / road_generator.gd ile aynı; oyun değişirse burası da güncellenir.
// Hem tarayıcıda (window.RunnyPhysics) hem node'da (require) çalışır.
(function (root) {
  'use strict';

  const CAR = {
    startSpeed: 22, maxSpeed: 55, acceleration: 0.35, lateAcceleration: 0.08, topSpeed: 75,
    gravity: 28, launchVelocity: 8, boostBonus: 1.35, boostMaxExtra: 45,
    carLen: 3.9, halfWidth: 1.1, steerSpeed: 11, airControl: 0.6, bumpLaunch: 1.4,
    lightsTime: 1.1, maxSlopeDeg: 18, maxBankDeg: 15,
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
  const vFull = (v) => v + Math.min(v * CAR.boostBonus, CAR.boostMaxExtra);
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
    for (const p of level.pieces) if (isOn(o, p) && (!best || (best.side && !p.side))) best = p;
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
  // Ana yol sırası (girişten çıkışa)
  function mainPath(level) {
    return level.pieces.filter((p) => !p.side).sort((a, b) => a.z0 - b.z0);
  }

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
    const lateral = CAR.steerSpeed * CAR.airControl * (isNaN(tB) ? 0 : tB);
    const need = Math.max(0, Math.abs(B.x - A.x) - (A.w / 2 + B.w / 2) + 2 * CAR.halfWidth + 0.5);
    return { A, B, v, vb, gap, dh, t0, tB, reach0, reachB, reachF, lateral, need,
      landNear: Math.max(B.z0, pEnd(A) + Math.min(reach0, reachB)),
      landFar: pEnd(A) + (isNaN(reachF) ? reachB : reachF) };
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
    if (!path.length) add('error', 'Ana yol yok: tüm yollar "yan yol" işaretli.');
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
    // Ana yol boyunca atlamalar
    let speedSum = 0;
    for (let i = 0; i + 1 < path.length; i++) {
      const A = path[i];
      if (successor(level, A)) continue;
      const B = path.slice(i + 1).find((q) => q.z0 > pEnd(A) - 0.6);
      if (!B) continue;
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
      } else if (g < J.reach0 - 1) {
        J.easy = true;
        add('ok', `${g.toFixed(0)} m boşluk gazsız da geçiliyor (kolay).`, [A.id, B.id], pEnd(A));
      }
      if (!J.bad) {
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
      speedSum += 1;
    }
    // Her ana yolun sonunda pist bölgesi: engel olmasın (hizalanıp gaz)
    for (const p of path) {
      if (successor(level, p)) continue;
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
      flights.push({ o, host, ...F });
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
    // Yan yolların sonu: ileride inilecek ana yol var mı
    for (const p of pieces) {
      if (!p.side || successor(level, p)) continue;
      if (obstacles.some((o) => o.kind === 'deadend' && hostOf(level, o) === p)) continue;
      const v = speedAt(at + pEnd(p));
      const ok = path.some((q) => {
        if (q.z0 > pEnd(p) + 60 || pEnd(q) < pEnd(p) + 4) return false;
        const t = flightTime(hAt(q, pEnd(p)) - h1(p), CAR.launchVelocity + vBoost(v) * 0);
        const lat = CAR.steerSpeed * CAR.airControl * (isNaN(t) ? 0 : t);
        return Math.abs(q.x - p.x) - (q.w + p.w) / 2 + 2 * CAR.halfWidth < lat * 0.8;
      });
      if (!ok) add('warn', 'Yan yolun sonundan inilecek ana yol yok: çıkmaz yapmak istiyorsan Çıkmaz koy.', [p.id], pEnd(p));
    }
    // Çıkış yolu
    const exit = path[path.length - 1];
    if (exit && obstacles.some((o) => hostOf(level, o) === exit && o.kind !== 'deadend' && o.z0 > pEnd(exit) - clearEnd(speedAt(at + pEnd(exit)))))
      add('warn', 'Çıkış yolunun sonu boş olmalı: oyun sonraki yolu buradan bağlar.', [exit.id], pEnd(exit));

    // Özet
    const zMin = Math.min(...pieces.map((p) => p.z0));
    const zMax = Math.max(...pieces.map(pEnd));
    const length = zMax - zMin;
    const vMid = speedAt(at + length / 2);
    const nObs = obstacles.length;
    const narrow = pieces.filter((p) => p.w < 5).length;
    const hard = jumps.filter((j) => !j.easy).length;
    let diff = 1 + hard * 0.45 + nObs * 0.18 + narrow * 0.4 + (vMid > 45 ? 0.6 : 0) + flights.length * 0.2;
    diff = Math.max(1, Math.min(5, Math.round(diff)));
    const crystals = crystalPreview(level, analyzeLite(level, jumps)).length;
    if (!issues.some((i) => i.level !== 'ok')) add('ok', 'Kontrollerde sorun yok.');
    return { issues, jumps, flights, zones, stats: { length, time: length / vMid, jumps: jumps.length, crystals, difficulty: diff, speed: vMid } };
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
      if (J.bad || J.gap < 6) continue;
      for (let i = 1; i <= 3; i++) {
        const f = i / 4;
        out.push({ x: J.A.x + (J.B.x - J.A.x) * f, z: pEnd(J.A) + J.gap * f, air: true });
      }
    }
    for (const p of level.pieces.filter((q) => q.side)) {
      for (let z = p.z0 + 6; z < pEnd(p) - 6 && out.length < 400; z += sp) out.push({ x: p.x, z, on: p.id });
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

  const KIND_NAMES = { ramp: 'Rampa', kick: 'Eğik rampa', bump: 'Tümsek', gravel: 'Çakıl', block: 'Blok', deadend: 'Çıkmaz' };

  const api = { CAR, TIERS, speedAt, vBoost, vFull, flightTime, clearEnd, clearStart, jump, rampFlight,
    analyze, crystalPreview, suggestGap, minRoadLength, mainPath, successor, hostOf, isOn, hAt, pEnd, KIND_NAMES };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.RunnyPhysics = api;
})(typeof window !== 'undefined' ? window : this);

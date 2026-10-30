// Runny Bölüm Tasarımcısı: tuval, sürükle-bırak, ayarlar, kontroller, kayıt ve oyunla bağlantı.
// Tasarım biçimi (levels/*.json): metre; z girişten ileri (yukarı), x sağa, h yükseklik (0 = ana seviye).
(function () {
  'use strict';
  const P = window.RunnyPhysics;
  const KEY = { current: 'runny_editor_current', library: 'runny_editor_library',
    test: 'runny_level_test', result: 'runny_level_result' };
  const GAME_URL = '../index.html';
  const MODEL_NAMES = { 1: 'Kutu', 2: 'Gezgin', 3: 'Konsept', 4: 'Roadster', 6: 'Dragster', 7: 'Dark Rose', 8: 'Latte' };
  const $ = (id) => document.getElementById(id);
  const r1 = (v) => Math.round(v * 10) / 10;
  const clamp = (v, a, b) => Math.min(Math.max(v, a), b);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // ------------------------------------------------------------------ durum
  let level = loadJSON(KEY.current) || newLevel();
  let sel = null;                       // { type: 'piece'|'obstacle', id }
  const undoStack = [], redoStack = [];
  let analysis = null;
  const view = { sx: 9, sz: 2.2, cx: 0, zb: -40 };   // zb: tuvalin altındaki z
  let results = loadJSON(KEY.result) || [];
  let resultsFor = localStorage.getItem('runny_editor_result_for') || '';

  function newLevel() {
    return { format: 'runny-level', version: 1, name: 'Yeni kalıp', at: 800, crystals: true, pieces: [], obstacles: [] };
  }
  function loadJSON(k) { try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch (e) { return null; } }
  function saveJSON(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* hafıza dolu/kapalı */ } }
  function nextId() {
    let m = 0;
    for (const p of level.pieces) m = Math.max(m, p.id);
    for (const o of level.obstacles) m = Math.max(m, o.id);
    return m + 1;
  }
  const findPiece = (id) => level.pieces.find((p) => p.id === id);
  const findObs = (id) => level.obstacles.find((o) => o.id === id);
  const selected = () => (sel ? (sel.type === 'piece' ? findPiece(sel.id) : findObs(sel.id)) : null);

  // Her değişiklik geri alınabilir; tasarım tarayıcıda otomatik saklanır
  function snapshot() { return JSON.stringify(level); }
  function commit(fn, keepRedo) {
    if (viewing) { toast('Türev gösteriliyor: düzenlemek için asıl kalıba dön ya da ayrı kalıp olarak aç.'); return; }
    undoStack.push(snapshot());
    if (undoStack.length > 200) undoStack.shift();
    if (!keepRedo) redoStack.length = 0;
    fn();
    changed();
  }
  function changed() {
    saveJSON(KEY.current, viewing ? viewing.base : level);
    render();
  }
  function undo() {
    if (!undoStack.length) return;
    redoStack.push(snapshot());
    level = JSON.parse(undoStack.pop());
    if (sel && !selected()) sel = null;
    changed();
  }
  function redo() {
    if (!redoStack.length) return;
    undoStack.push(snapshot());
    level = JSON.parse(redoStack.pop());
    if (sel && !selected()) sel = null;
    changed();
  }

  // ------------------------------------------------------------------ parçalar
  const tierOf = (h) => (h <= -2 ? 'low' : h >= 1.5 ? 'high' : 'mid');
  const ROAD_COLOR = { low: '#3b3d42', mid: '#55585e', high: '#767a81' };
  const PALETTE = {
    roads: [
      { key: 'low', name: 'Alçak yol', make: () => ({ w: 8, len: 80, h0: -4, h1: -4 }) },
      { key: 'mid', name: 'Orta yol', make: () => ({ w: 8, len: 80, h0: 0, h1: 0 }) },
      { key: 'high', name: 'Yüksek yol', make: () => ({ w: 6, len: 70, h0: 3, h1: 3 }) },
      { key: 'slope', name: 'Yokuş', make: () => ({ w: 8, len: 60, h0: 0, h1: 5 }) },
      { key: 'bank', name: 'Yatık yol', make: () => ({ w: 9, len: 120, h0: 0, h1: 0, bank: 12 }) },
      { key: 'narrow', name: 'Dar yol', make: () => ({ w: 3.6, len: 70, h0: 0, h1: 0 }) },
    ],
    obstacles: [
      { key: 'ramp', name: 'Rampa', make: () => ({ kind: 'ramp', w: 4, len: 8, rise: 1.6 }) },
      { key: 'kick', name: 'Eğik rampa', make: () => ({ kind: 'kick', w: 3, len: 7, rise: 1.4, dir: 1, dx: 8 }) },
      { key: 'bump', name: 'Tümsek', make: () => ({ kind: 'bump', w: 8, len: 12, rise: 1 }) },
      { key: 'gravel', name: 'Çakıl', make: () => ({ kind: 'gravel', w: 3.5, len: 12 }) },
      { key: 'block', name: 'Blok', make: () => ({ kind: 'block', w: 2, len: 1.2 }) },
      { key: 'deadend', name: 'Çıkmaz', make: () => ({ kind: 'deadend', w: 8, len: 1.2 }) },
    ],
    patterns: [
      { key: 'stairs', name: 'Merdiven' }, { key: 'islands', name: 'Ada zinciri' },
      { key: 'slalom', name: 'Slalom' }, { key: 'fork', name: 'Çatal' },
    ],
  };
  const ICON = (() => {
    const road = (c) => `<rect x="4" y="9" width="56" height="12" rx="1.5" fill="${c}"/><line x1="8" y1="15" x2="56" y2="15" stroke="#fff" stroke-width="1" stroke-dasharray="4 3" opacity=".7"/>`;
    const base = `<rect x="4" y="9" width="56" height="12" fill="#55585e"/>`;
    const gr = [...Array(14)].map((_, i) => `<circle cx="${20 + (i * 7) % 25}" cy="${11.5 + (i * 3) % 8}" r=".9" fill="#7d6f5a"/>`).join('');
    return {
      low: road('#3b3d42'), mid: road('#55585e'), high: road('#767a81'),
      slope: `<polygon points="4,21 60,21 60,9 4,17" fill="#55585e"/><path d="M26 18 l6 -5 l6 5" stroke="#ff5a1f" fill="none" stroke-width="1.4"/>`,
      bank: `<polygon points="4,12 60,9 60,21 4,18" fill="#55585e"/><line x1="4" y1="12" x2="60" y2="9" stroke="#fff" stroke-width="1.2"/>`,
      narrow: `<rect x="4" y="12" width="56" height="6" rx="1" fill="#55585e"/>`,
      ramp: base + `<rect x="22" y="10" width="20" height="10" fill="#f4d9a8"/><path d="M28 18 l4 -6 l4 6" stroke="#ff5a1f" fill="none" stroke-width="1.6"/>`,
      kick: base + `<rect x="22" y="10" width="20" height="10" fill="#f4d9a8"/><path d="M27 18 l9 -6 m0 0 l-5 0 m5 0 l0 4" stroke="#ff5a1f" fill="none" stroke-width="1.6"/>`,
      bump: base + `<rect x="34" y="10" width="16" height="10" fill="#e9e3d6"/><line x1="42" y1="10" x2="42" y2="20" stroke="#c9c5bd"/>`,
      gravel: base + `<rect x="18" y="10" width="28" height="10" fill="#b9a98f"/>` + gr,
      block: base + `<rect x="28" y="11" width="8" height="8" fill="#232529"/><rect x="28" y="11" width="8" height="2" fill="#ff5a1f"/>`,
      deadend: `<rect x="4" y="9" width="40" height="12" fill="#55585e"/><rect x="44" y="9" width="4" height="12" fill="#232529"/><rect x="44" y="9" width="4" height="3" fill="#ff5a1f"/>`,
      stairs: `<rect x="4" y="8" width="18" height="6" fill="#767a81"/><rect x="23" y="13" width="18" height="6" fill="#55585e"/><rect x="42" y="18" width="18" height="6" fill="#3b3d42"/>`,
      islands: [6, 20, 34, 48].map((x, i) => `<rect x="${x}" y="${10 + (i % 2) * 4}" width="10" height="7" fill="#55585e"/>`).join(''),
      slalom: base + [12, 26, 40, 54].map((x, i) => `<rect x="${x - 4}" y="${i % 2 ? 15 : 10}" width="7" height="5" fill="#f4d9a8"/>`).join(''),
      fork: `<rect x="4" y="12" width="22" height="7" fill="#55585e"/><polygon points="26,12 60,5 60,11 26,17" fill="#767a81"/><polygon points="26,14 60,19 60,25 26,19" fill="#3b3d42"/>`,
    };
  })();

  function buildPalette() {
    for (const group of ['roads', 'obstacles', 'patterns']) {
      const el = document.querySelector(`.tiles[data-group="${group}"]`);
      for (const item of PALETTE[group]) {
        const t = document.createElement('div');
        t.className = 'tile';
        t.dataset.group = group;
        t.dataset.key = item.key;
        t.dataset.name = item.name.toLocaleLowerCase('tr');
        t.innerHTML = `<svg viewBox="0 0 64 30">${ICON[item.key]}</svg>${item.name}`;
        t.addEventListener('pointerdown', (e) => startPaletteDrag(e, group, item));
        el.appendChild(t);
      }
    }
    $('search').addEventListener('input', (e) => {
      const q = e.target.value.trim().toLocaleLowerCase('tr');
      document.querySelectorAll('.tile').forEach((t) => t.classList.toggle('hidden', q && !t.dataset.name.includes(q)));
    });
  }

  // ------------------------------------------------------------------ görünüm
  const svgTop = $('top'), svgSide = $('side'), wrap = $('canvasWrap');
  let W = 800, H = 600;
  const px = (x) => W / 2 + (x - view.cx) * view.sx;
  const pz = (z) => H - (z - view.zb) * view.sz;
  const toWorld = (cx, cy) => ({ x: (cx - W / 2) / view.sx + view.cx, z: (H - cy) / view.sz + view.zb });
  function clientToWorld(e) {
    const r = svgTop.getBoundingClientRect();
    return toWorld(e.clientX - r.left, e.clientY - r.top);
  }
  function fitView() {
    if (!level.pieces.length) { view.cx = 0; view.zb = -40; view.sx = 9; view.sz = 2.2; return; }
    const z0 = Math.min(...level.pieces.map((p) => p.z0)), z1 = Math.max(...level.pieces.map(P.pEnd));
    const x0 = Math.min(...level.pieces.map((p) => p.x - p.w / 2)), x1 = Math.max(...level.pieces.map((p) => p.x + p.w / 2));
    // Uzun tasarımda ilk ~350 m görünür (gerisi tekerlekle ya da yandan görünüşe tıklayarak)
    view.sz = clamp((H - 80) / Math.min(Math.max(z1 - z0, 50), 350), 0.6, 6);
    view.sx = clamp(Math.min((W - 160) / Math.max(x1 - x0 + 10, 20), view.sz * 5), 3, 24);
    view.cx = (x0 + x1) / 2;
    view.zb = z0 - 30 / view.sz;
  }
  function scrollToZ(z) { view.zb = z - (H * 0.45) / view.sz; render(); }

  // ------------------------------------------------------------------ çizim
  let ghostItem = null;   // paletten sürüklenen parçanın tuvaldeki önizlemesi
  let guide = null;       // mıknatıs çizgisi
  function render() {
    W = wrap.clientWidth; H = wrap.clientHeight;
    svgTop.setAttribute('viewBox', `0 0 ${W} ${H}`);
    analysis = P.analyze(level);
    $('empty').style.display = level.pieces.length || ghostItem ? 'none' : 'block';
    renderTop();
    renderSide();
    renderProps();
    renderVariants();
    renderLevelCard();
    renderChecks();
    renderResults();
    $('name').value = level.name || '';
    $('crystals').checked = level.crystals !== false;
    $('undoBtn').disabled = !undoStack.length;
    $('redoBtn').disabled = !redoStack.length;
  }

  function renderTop() {
    const s = [];
    const zTop = toWorld(0, 0).z, zBot = toWorld(0, H).z;
    // Izgara: 10 m'de bir çizgi, 50 m'de bir etiket
    const step = view.sz < 1 ? 50 : 10;
    for (let z = Math.floor(zBot / step) * step; z <= zTop; z += step) {
      const y = pz(z);
      s.push(`<line x1="52" y1="${y}" x2="${W}" y2="${y}" stroke="${z % 50 ? '#ebe8e1' : '#dcd8d0'}"/>`);
      if (z % (view.sz < 1 ? 100 : 50) === 0) s.push(`<text x="10" y="${y + 4}" font-size="11" fill="#7c8087">${z} m</text>`);
    }
    for (let x = Math.floor(toWorld(52, 0).x / 10) * 10; x <= toWorld(W, 0).x; x += 10)
      s.push(`<line x1="${px(x)}" y1="0" x2="${px(x)}" y2="${H}" stroke="#ebe8e1"/>`);
    if (level.pieces.length) s.push(`<text x="${px(level.pieces[0].x) - 18}" y="${pz(Math.min(...level.pieces.map((p) => p.z0))) + 18}" font-size="10.5" fill="#7c8087">giriş</text>`);

    const zones = analysis ? analysis.zones : [];
    // Yollar (alçaktan yükseğe: yüksek yol üstte görünsün)
    const order = [...level.pieces].sort((a, b) => Math.max(a.h0, a.h1 ?? a.h0) - Math.max(b.h0, b.h1 ?? b.h0));
    for (const p of order) s.push(pieceSVG(p));
    // İniş bölgeleri
    for (const J of analysis ? analysis.jumps : []) {
      if (J.bad) continue;
      const B = J.B;
      const z0 = Math.max(J.landNear, B.z0), z1 = Math.min(J.landFar, P.pEnd(B));
      if (z1 > z0) s.push(`<rect x="${px(B.x - B.w / 2)}" y="${pz(z1)}" width="${B.w * view.sx}" height="${(z1 - z0) * view.sz}" fill="rgba(58,166,91,.32)" pointer-events="none"/>`);
    }
    // Pist ışıkları (yolun sonunda gaz bölgesi)
    for (const zn of zones) {
      if (zn.kind !== 'runway') continue;
      const p = findPiece(zn.id);
      if (!p) continue;
      for (let z = zn.z1 - 0.8, k = 0; z > zn.z0 && k < 40; k++) {
        for (const sx of [-1, 1]) s.push(`<circle cx="${px(p.x + sx * (p.w / 2 - 0.4))}" cy="${pz(z)}" r="${Math.max(1.4, view.sx * 0.12)}" fill="#e23c30" opacity=".75" pointer-events="none"/>`);
        z -= 1 + 4 * ((zn.z1 - z) / Math.max(zn.z1 - zn.z0, 1));
      }
    }
    // Engeller
    for (const o of level.obstacles) s.push(obstacleSVG(o));
    // Kristaller (önizleme)
    for (const c of P.crystalPreview(level, analysis)) {
      const x = px(c.x), y = pz(c.z), r = clamp(view.sx * 0.45, 3, 6);
      s.push(`<path d="M${x} ${y - r} l${r * 0.75} ${r} l${-r * 0.75} ${r} l${-r * 0.75} ${-r} z" fill="#9fe02a" stroke="#6fa514" stroke-width=".8" opacity="${c.air ? 0.65 : 1}" pointer-events="none"/>`);
    }
    // Atlama ve uçuş çizgileri
    for (const J of analysis ? analysis.jumps : []) {
      const x0 = px(J.A.x), y0 = pz(P.pEnd(J.A)), x1 = px(J.B.x), y1 = pz(J.bad ? J.B.z0 : (J.landNear + J.landFar) / 2);
      s.push(`<line x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}" stroke="${J.bad ? '#e23b3b' : '#ff5a1f'}" stroke-width="2" stroke-dasharray="2 5" stroke-linecap="round" pointer-events="none"/>`);
      if (J.bad) {
        const mx = (x0 + x1) / 2, my = (y0 + pz(J.B.z0)) / 2;
        s.push(`<g transform="translate(${mx},${my})" pointer-events="none"><circle r="10" fill="#e23b3b"/><path d="M-4 -4 L4 4 M4 -4 L-4 4" stroke="#fff" stroke-width="2.3"/></g>`);
        s.push(`<g transform="translate(${mx + 16},${my - 12})" pointer-events="none"><rect width="${J.gap > (J.reachB || 0) ? 180 : 150}" height="24" rx="6" fill="#fff" stroke="#e23b3b"/><text x="9" y="16" font-size="11.5" font-weight="700" fill="#e23b3b">${isNaN(J.reachB) ? 'çok yüksek' : `${J.gap.toFixed(0)} m — en çok ${(J.reachB - 2.5).toFixed(0)} m`}</text></g>`);
      }
    }
    for (const F of analysis ? analysis.flights : []) {
      if (isNaN(F.t)) continue;
      const bad = !F.landOn;
      s.push(`<line x1="${px(F.o.x)}" y1="${pz(F.from)}" x2="${px(F.x)}" y2="${pz(F.land)}" stroke="${bad ? '#e23b3b' : '#ff5a1f'}" stroke-width="1.6" stroke-dasharray="3 4" pointer-events="none"/>`);
      s.push(`<circle cx="${px(F.x)}" cy="${pz(F.land)}" r="4" fill="${bad ? '#e23b3b' : '#ff5a1f'}" pointer-events="none"/>`);
    }
    // Test sonuçları: düşülen/çakılan yerler
    if (resultsFor === resultsKey()) {
      for (const r of results) if (!r.ok) {
        s.push(`<g transform="translate(${px(r.x)},${pz(r.z)})" pointer-events="none"><circle r="8" fill="#e23b3b" opacity=".85"/><path d="M-3 -3 L3 3 M3 -3 L-3 3" stroke="#fff" stroke-width="2"/></g>`);
      }
    }
    // Seçim tutamakları
    const it = selected();
    if (it) s.push(handlesSVG(it, sel.type));
    if (guide) s.push(`<line x1="0" y1="${pz(guide.z)}" x2="${W}" y2="${pz(guide.z)}" stroke="#ff5a1f" stroke-dasharray="6 5" pointer-events="none"/><text x="${W - 230}" y="${pz(guide.z) - 6}" font-size="11" font-weight="600" fill="#ff5a1f">${esc(guide.text)}</text>`);
    if (ghostItem) s.push(ghostSVG(ghostItem));
    // Yön oku
    s.push(`<g transform="translate(${W - 36},34)" pointer-events="none"><path d="M0 16 L0 -12 M-6 -5 L0 -12 L6 -5" stroke="#7c8087" stroke-width="2" fill="none"/><text x="0" y="30" text-anchor="middle" font-size="10" fill="#7c8087">ileri</text></g>`);
    svgTop.innerHTML = s.join('');
  }

  function pieceSVG(p, ghost) {
    const x = px(p.x - p.w / 2), y = pz(P.pEnd(p)), w = p.w * view.sx, h = p.len * view.sz;
    const h0 = p.h0 || 0, h1 = p.h1 ?? h0;
    const c0 = ROAD_COLOR[tierOf(h0)], c1 = ROAD_COLOR[tierOf(h1)];
    const out = [];
    const id = `g${p.id}`;
    if (c0 !== c1) out.push(`<defs><linearGradient id="${id}" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="${c0}"/><stop offset="1" stop-color="${c1}"/></linearGradient></defs>`);
    const fill = c0 !== c1 ? `url(#${id})` : c0;
    out.push(`<g data-type="piece" data-id="${p.id}" style="cursor:move" opacity="${ghost ? 0.55 : 1}">`);
    out.push(`<rect x="${x + 3}" y="${y + 4}" width="${w}" height="${h}" fill="rgba(0,0,0,.10)" rx="2"/>`);
    out.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}" rx="2" ${p.side ? 'stroke="#ff5a1f" stroke-width="1" stroke-dasharray="6 4"' : ''}/>`);
    if (w > 10) for (const ex of [x + 3, x + w - 3])
      out.push(`<line x1="${ex}" y1="${y + 2}" x2="${ex}" y2="${y + h - 2}" stroke="#fff" stroke-width="1.3" stroke-dasharray="7 5" opacity=".85"/>`);
    if (p.bank) {
      // Yatık yol (oyundaki gibi): boydan boya yatık, başta ve uçta kısa geçiş. Alçak kenarda
      // kırmızı-beyaz bordür; yüzeyde alçak kenara doğru koyulaşan gölge. bank > 0: sağ kenar yukarı
      const low = p.bank > 0 ? -1 : 1;
      const ramp = Math.min(Math.max(p.len * 0.1, 8), 25, p.len * 0.3);
      const zA = p.z0 + ramp * 0.3, zB = P.pEnd(p) - ramp * 0.3;
      const gid = `b${p.id}`;
      out.push(`<defs><linearGradient id="${gid}" x1="${low < 0 ? 1 : 0}" y1="0" x2="${low < 0 ? 0 : 1}" y2="0"><stop offset="0" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="${Math.min(Math.abs(p.bank) / 15, 1) * 0.28}"/></linearGradient></defs>`);
      out.push(`<rect x="${x}" y="${pz(zB)}" width="${w}" height="${(zB - zA) * view.sz}" fill="url(#${gid})" pointer-events="none"/>`);
      const kw = Math.max(0.75 * view.sx, 3);
      const kx = low < 0 ? x + 1 : x + w - 1 - kw;
      const step = Math.max(1.6, 5 / view.sz);
      for (let z = zA, k = 0; z < zB; z += step, k++) {
        const z1 = Math.min(z + step, zB);
        out.push(`<rect x="${kx}" y="${pz(z1)}" width="${kw}" height="${(z1 - z) * view.sz}" fill="${k % 2 ? '#fff' : '#e23c30'}" pointer-events="none"/>`);
      }
    }
    if (Math.abs(h1 - h0) > 0.05) {
      const cx = x + w / 2, dir = h1 > h0 ? -1 : 1;
      for (let k = 0; k < 3; k++) {
        const cy = y + h * (0.3 + k * 0.2);
        out.push(`<path d="M${cx - 6} ${cy - dir * 4} l6 ${dir * 6} l6 ${-dir * 6}" stroke="#ff5a1f" stroke-width="2" fill="none" transform="rotate(180 ${cx} ${cy})"/>`);
      }
    }
    // Yükseklik etiketi
    const lab = Math.abs(h1 - h0) > 0.05 ? `${fmtH(h0)}→${fmtH(h1)}` : fmtH(h0);
    const lw = lab.length * 6.4 + 14;
    out.push(`<rect x="${x + w + 6}" y="${y + 4}" width="${lw}" height="17" rx="8.5" fill="#fff" stroke="#dcd8d0"/><text x="${x + w + 6 + lw / 2}" y="${y + 16}" text-anchor="middle" font-size="10.5" font-weight="700" fill="#232529">${lab}</text>`);
    if (p.side) out.push(`<text x="${x + w + 8}" y="${y + 34}" font-size="10" font-weight="600" fill="#ff5a1f">yan yol</text>`);
    out.push('</g>');
    return out.join('');
  }
  const fmtH = (h) => `${h > 0 ? '+' : ''}${r1(h)} m`;

  function obstacleSVG(o, ghost) {
    const x = px(o.x - o.w / 2), y = pz(o.z0 + o.len), w = Math.max(o.w * view.sx, 4), h = Math.max(o.len * view.sz, 3);
    const out = [`<g data-type="obstacle" data-id="${o.id}" style="cursor:move" opacity="${ghost ? 0.6 : 1}">`];
    if (o.kind === 'ramp' || o.kind === 'kick') {
      out.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="#f4d9a8"/>`);
      const cx = x + w / 2, cy = y + h / 2;
      if (o.kind === 'ramp') out.push(`<path d="M${cx - 6} ${cy + 4} l6 -8 l6 8" stroke="#ff5a1f" stroke-width="2" fill="none"/>`);
      else { const d = Math.sign(o.dir || 1); out.push(`<path d="M${cx - d * 8} ${cy + 5} l${d * 15} -9 m0 0 l${-d * 7} 0 m${d * 7} 0 l0 6" stroke="#ff5a1f" stroke-width="2" fill="none"/>`); }
    } else if (o.kind === 'gravel') {
      out.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="#b9a98f"/>`);
      const n = Math.min(Math.floor(w * h / 40), 60);
      for (let i = 0; i < n; i++) out.push(`<circle cx="${x + 2 + (i * 11.3) % Math.max(w - 4, 1)}" cy="${y + 2 + (i * 7.7) % Math.max(h - 4, 1)}" r="1.1" fill="#7d6f5a"/>`);
    } else if (o.kind === 'block') {
      out.push(`<rect x="${x}" y="${y - 3}" width="${w}" height="${h + 6}" fill="#232529"/><rect x="${x}" y="${y - 3}" width="${w}" height="3" fill="#ff5a1f"/>`);
    } else if (o.kind === 'bump') {
      out.push(`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="#e9e3d6" opacity=".95"/><line x1="${x}" y1="${y + h / 2}" x2="${x + w}" y2="${y + h / 2}" stroke="#c9c5bd" stroke-width="2"/>`);
    } else if (o.kind === 'deadend') {
      out.push(`<rect x="${x}" y="${y - 3}" width="${w}" height="${h + 6}" fill="#232529"/><rect x="${x}" y="${y - 3}" width="${w}" height="3" fill="#ff5a1f"/><text x="${x + w + 6}" y="${y + 8}" font-size="10" font-weight="700" fill="#232529">çıkmaz</text>`);
    }
    out.push('</g>');
    return out.join('');
  }

  function handlesSVG(it, type) {
    const x = px(it.x - it.w / 2) - 3, y = pz(it.z0 + it.len) - 3, w = it.w * view.sx + 6, h = Math.max(it.len * view.sz, 3) + 6;
    const out = [`<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="none" stroke="#ff5a1f" stroke-width="2" rx="3" pointer-events="none"/>`];
    const hs = [['n', x + w / 2, y], ['s', x + w / 2, y + h], ['e', x + w, y + h / 2], ['w', x, y + h / 2]];
    const cur = { n: 'ns-resize', s: 'ns-resize', e: 'ew-resize', w: 'ew-resize' };
    for (const [k, hx, hy] of hs) {
      if (type === 'obstacle' && (it.kind === 'block' || it.kind === 'deadend') && (k === 'n' || k === 's')) continue;
      out.push(`<rect data-handle="${k}" x="${hx - 5}" y="${hy - 5}" width="10" height="10" fill="#fff" stroke="#ff5a1f" stroke-width="1.8" style="cursor:${cur[k]}"/>`);
    }
    return out.join('');
  }

  function ghostSVG(g) {
    if (g.type === 'piece') return pieceSVG({ id: 'ghost', side: g.item.side, ...g.item }, true);
    if (g.type === 'obstacle') return obstacleSVG({ id: 'ghost', ...g.item }, true);
    return g.items.map((it) => (it.kind ? obstacleSVG({ id: 'ghost', ...it }, true) : pieceSVG({ id: 'ghost', ...it }, true))).join('');
  }

  // Yandan görünüş: tüm tasarım sığar; üst tuvalde görünen aralık çerçeveli
  function renderSide() {
    const w = svgSide.clientWidth || 800, h = svgSide.clientHeight || 168;
    svgSide.setAttribute('viewBox', `0 0 ${w} ${h}`);
    const s = [];
    if (!level.pieces.length) { svgSide.innerHTML = ''; return; }
    const z0 = Math.min(...level.pieces.map((p) => p.z0)) - 10, z1 = Math.max(...level.pieces.map(P.pEnd)) + 30;
    let hMin = Math.min(0, ...level.pieces.map((p) => Math.min(p.h0, p.h1 ?? p.h0))) - 2;
    let hMax = Math.max(4, ...level.pieces.map((p) => Math.max(p.h0, p.h1 ?? p.h0))) + 6;
    const sx = (w - 70) / (z1 - z0), sy = Math.min((h - 54) / (hMax - hMin), 10);
    const qx = (z) => 48 + (z - z0) * sx, qy = (hh) => h - 30 - (hh - hMin) * sy;
    const vis0 = toWorld(0, H).z, vis1 = toWorld(0, 0).z;
    s.push(`<rect x="${qx(Math.max(vis0, z0))}" y="22" width="${Math.max((Math.min(vis1, z1) - Math.max(vis0, z0)) * sx, 4)}" height="${h - 46}" fill="rgba(255,90,31,.06)" stroke="rgba(255,90,31,.35)" stroke-dasharray="4 4"/>`);
    s.push(`<line x1="40" y1="${h - 22}" x2="${w - 10}" y2="${h - 22}" stroke="#dcd8d0"/>`);
    const stepZ = (z1 - z0) > 600 ? 100 : 50;
    for (let z = Math.ceil(z0 / stepZ) * stepZ; z <= z1; z += stepZ) s.push(`<text x="${qx(z)}" y="${h - 6}" font-size="10.5" fill="#7c8087" text-anchor="middle">${z} m</text>`);
    s.push(`<line x1="44" y1="${qy(0)}" x2="${w - 10}" y2="${qy(0)}" stroke="#ebe8e1" stroke-dasharray="3 4"/><text x="8" y="${qy(0) + 4}" font-size="10" fill="#7c8087">0 m</text>`);
    for (const p of [...level.pieces].sort((a, b) => (a.side ? 1 : 0) - (b.side ? 1 : 0))) {
      const isSel = sel && sel.type === 'piece' && sel.id === p.id;
      const h0 = p.h0 || 0, h1 = p.h1 ?? h0;
      s.push(`<polygon points="${qx(p.z0)},${qy(h0)} ${qx(P.pEnd(p))},${qy(h1)} ${qx(P.pEnd(p))},${qy(h1) + 6} ${qx(p.z0)},${qy(h0) + 6}" fill="${ROAD_COLOR[tierOf((h0 + h1) / 2)]}" opacity="${p.side ? 0.55 : 1}" ${isSel ? 'stroke="#ff5a1f" stroke-width="2"' : ''}/>`);
    }
    for (const o of level.obstacles) {
      const host = P.hostOf(level, o);
      if (!host) continue;
      const hh = P.hAt(host, o.z0);
      if (o.kind === 'ramp' || o.kind === 'kick') s.push(`<polygon points="${qx(o.z0)},${qy(hh)} ${qx(o.z0 + o.len)},${qy(hh)} ${qx(o.z0 + o.len)},${qy(hh + o.rise)}" fill="#f4d9a8" stroke="#e0b878"/>`);
      if (o.kind === 'bump') s.push(`<polygon points="${qx(o.z0)},${qy(hh)} ${qx(o.z0 + o.len / 2)},${qy(hh + o.rise)} ${qx(o.z0 + o.len)},${qy(hh)}" fill="#e9e3d6" stroke="#c9c5bd"/>`);
      if (o.kind === 'block' || o.kind === 'deadend') s.push(`<rect x="${qx(o.z0) - 2}" y="${qy(hh + 0.9)}" width="4" height="${0.9 * sy}" fill="#232529"/>`);
    }
    // Atlama yayları: gazsız (gri) ve roketle (yeşil/kırmızı)
    for (const J of analysis ? analysis.jumps : []) {
      const zA = P.pEnd(J.A), hA = J.A.h1 ?? J.A.h0;
      const arc = (zEnd, hEnd, peak, col, dash) => `<path d="M${qx(zA)} ${qy(hA) - 3} Q ${qx((zA + zEnd) / 2)} ${qy(peak) - 3} ${qx(zEnd)} ${qy(hEnd) - 3}" fill="none" stroke="${col}" stroke-width="2" stroke-dasharray="${dash}"/>`;
      const peak = hA + (8 * 8) / (2 * P.CAR.gravity) * 1.8;
      if (J.bad) {
        s.push(arc(zA + Math.max(J.reachB || 10, 8), (J.B.h0 || 0) - 4, peak, '#e23b3b', '5 4'));
        s.push(`<g transform="translate(${qx(zA + Math.max(J.reachB || 10, 8))},${qy((J.B.h0 || 0) - 4)})"><circle r="7" fill="#e23b3b"/><path d="M-3 -3 L3 3 M3 -3 L-3 3" stroke="#fff" stroke-width="2"/></g>`);
      } else {
        if (!J.easy) s.push(arc(zA + J.reach0, (J.B.h0 || 0) - 3, peak, '#b8b4ab', '3 4'));
        s.push(arc((J.landNear + J.landFar) / 2, J.B.h0 || 0, peak + 1, '#3aa65b', '0'));
      }
    }
    for (const F of analysis ? analysis.flights : []) {
      if (isNaN(F.t)) continue;
      const hTop = F.top, peak = hTop + (F.vy0 * F.vy0) / (2 * P.CAR.gravity);
      const hl = F.landOn ? P.hAt(F.landOn, F.land) : hTop - 6;
      s.push(`<path d="M${qx(F.from)} ${qy(hTop) - 2} Q ${qx((F.from + F.land) / 2)} ${qy(peak * 2 - (hTop + hl) / 2)} ${qx(F.land)} ${qy(hl) - 2}" fill="none" stroke="${F.landOn ? '#ff5a1f' : '#e23b3b'}" stroke-width="1.6" stroke-dasharray="4 3"/>`);
    }
    svgSide.innerHTML = s.join('');
    svgSide.onclick = (e) => {
      const r = svgSide.getBoundingClientRect();
      scrollToZ(z0 + (e.clientX - r.left - 48) / sx);
    };
  }

  // ------------------------------------------------------------------ sağ panel
  function numRow(label, key, val, unit, step, min, max) {
    const lim = `${min !== undefined ? `min="${min}"` : ''} ${max !== undefined ? `max="${max}"` : ''}`;
    return `<div class="row"><label>${label}</label><div class="val"><div class="stepper">` +
      `<button type="button" data-step="-1" data-for="${key}" tabindex="-1" title="Azalt (Shift: 5 kat)">−</button>` +
      `<input type="number" data-key="${key}" value="${r1(val)}" step="${step || 0.5}" ${lim}>` +
      `<button type="button" data-step="1" data-for="${key}" tabindex="-1" title="Artır (Shift: 5 kat)">+</button>` +
      `</div><span class="unit">${unit || ''}</span></div></div>`;
  }
  function renderProps() {
    const it = selected();
    const el = $('props');
    if (!it) {
      el.innerHTML = `<div class="muted">Bir yola ya da engele tıkla. Taşımak için sürükle, uçlarındaki tutamaklarla uzat ya da genişlet.<br><br>
        <b>Çoğaltmak (aynı boyda):</b> Alt+sürükle (Mac'te Option), Ctrl+D ardına ekler, Ctrl+C / Ctrl+V imlecin olduğu yere yapıştırır.<br><br>
        <b>Kısayollar:</b> Sil (Delete), Geri al (Ctrl+Z), ok tuşlarıyla kaydır (Shift: 5 m). Tekerlek: kaydır, Ctrl+tekerlek: yakınlaştır.</div>`;
      return;
    }
    const out = [];
    if (sel.type === 'piece') {
      const h0 = it.h0 || 0, h1 = it.h1 ?? h0;
      const t = tierOf((h0 + h1) / 2);
      const slope = Math.atan2(h1 - h0, it.len) * 180 / Math.PI;
      out.push(`<div class="sel"><div class="dot" style="background:${ROAD_COLOR[t]}"></div>${it.side ? 'Yan yol' : 'Yol'} #${it.id}<button class="dup" data-act="dup" title="Aynı boyda kopyası ardına (Ctrl+D)">Çoğalt</button><button class="del" data-act="delete">Sil</button></div>`);
      out.push(`<div class="row"><label>Kat</label><div class="seg">${['low', 'mid', 'high'].map((k) => `<button data-tier="${k}" class="${t === k && Math.abs(h1 - h0) < 0.05 ? 'on' : ''}">${{ low: 'Alçak', mid: 'Orta', high: 'Yüksek' }[k]}</button>`).join('')}</div></div>`);
      out.push(numRow('Uzunluk', 'len', it.len, 'm', 1, 4));
      out.push(numRow('Genişlik', 'w', it.w, 'm', 0.5, 2.5, 16));
      out.push(numRow('Başta yükseklik', 'h0', h0, 'm', 0.5, -18, 12));
      out.push(numRow('Sonda yükseklik', 'h1', h1, 'm', 0.5, -18, 12));
      out.push(`<div class="row"><label>Eğim</label><b>${r1(slope)}°</b></div>`);
      out.push(numRow('Yatıklık', 'bank', it.bank || 0, '°', 1, -15, 15));
      out.push(numRow('Yan konum (x)', 'x', it.x, 'm', 0.5));
      out.push(numRow('Başlangıç (z)', 'z0', it.z0, 'm', 1));
      out.push(`<div class="row"><label class="chk"><input type="checkbox" data-key="side" ${it.side ? 'checked' : ''}> Yan yol</label><span class="muted">ana yolun dışı, isteğe bağlı</span></div>`);
      const on = level.obstacles.filter((o) => P.hostOf(level, o) === it).map((o) => P.KIND_NAMES[o.kind]);
      if (on.length) out.push(`<div class="row"><label>Üstünde</label><b>${on.join(', ')}</b></div>`);
    } else {
      const host = P.hostOf(level, it);
      out.push(`<div class="sel"><div class="dot" style="background:${it.kind === 'gravel' ? '#b9a98f' : it.kind === 'block' || it.kind === 'deadend' ? '#232529' : '#f4d9a8'}"></div>${P.KIND_NAMES[it.kind]} #${it.id}<button class="dup" data-act="dup" title="Aynı boyda kopyası ardına (Ctrl+D)">Çoğalt</button><button class="del" data-act="delete">Sil</button></div>`);
      if (it.kind !== 'deadend') {
        if (it.kind !== 'block') out.push(numRow('Uzunluk', 'len', it.len, 'm', 0.5, 1));
        if (it.kind !== 'bump') out.push(numRow('Genişlik', 'w', it.w, 'm', 0.5, 0.8));
        if (it.kind === 'ramp' || it.kind === 'kick' || it.kind === 'bump') out.push(numRow('Yükseklik', 'rise', it.rise, 'm', 0.1, 0.3, 4));
        if (it.kind === 'kick') {
          out.push(`<div class="row"><label>Attığı yön</label><div class="seg"><button data-dir="-1" class="${it.dir < 0 ? 'on' : ''}">← Sol</button><button data-dir="1" class="${it.dir > 0 ? 'on' : ''}">Sağ →</button></div></div>`);
          out.push(numRow('Yana atış', 'dx', it.dx, 'm', 0.5, 1, 30));
        }
        out.push(numRow('Yan konum (x)', 'x', it.x, 'm', 0.5));
      }
      out.push(numRow('Yer (z)', 'z0', it.z0, 'm', 0.5));
      if (host) out.push(`<div class="row"><label>Üstünde durduğu yol</label><b>#${host.id}</b></div>`);
      else out.push(`<div class="muted" style="color:var(--danger)">Bir yolun üstünde değil: oyunda yok sayılır.</div>`);
      const F = analysis && analysis.flights.find((f) => f.o === it);
      if (F && !isNaN(F.t)) out.push(`<div class="row"><label>Uçuş</label><b>${(F.land - F.from).toFixed(0)} m, ${F.t.toFixed(2)} sn</b></div>`);
    }
    out.push(`<div class="row dups"><label>Ardına çoğalt</label><div class="seg">${[1, 2, 3, 5].map((n) => `<button data-act="dup" data-n="${n}">${n}×</button>`).join('')}</div></div>`);
    out.push(`<div class="muted" style="margin-top:4px">Kopyayı taşıyıp yine çoğaltırsan aynı aralıkla devam eder. Alt+sürükle: kopyasını sürükle.</div>`);
    el.innerHTML = out.join('');
  }
  $('props').addEventListener('change', (e) => {
    const k = e.target.dataset.key;
    if (!selected() || !k) return;
    if (k === 'side') { const it = selected(); commit(() => { it.side = e.target.checked; }); return; }
    commit(() => setProp(k, parseFloat(e.target.value)));
  });
  // −/+ düğmeleri: tıkla bir adım, basılı tut sürekli (bir basış tek geri alma adımı)
  let stepHold = null;
  function stepOnce(k, dir, big) {
    const inp = $('props').querySelector(`input[data-key="${k}"]`);
    if (!inp || !selected()) return false;
    const st = parseFloat(inp.step) || 0.5;
    let v = r1((parseFloat(inp.value) || 0) + dir * st * (big ? 5 : 1));
    if (inp.min !== '') v = Math.max(v, parseFloat(inp.min));
    if (inp.max !== '') v = Math.min(v, parseFloat(inp.max));
    setProp(k, v);
    changed();
    return true;
  }
  $('props').addEventListener('pointerdown', (e) => {
    const b = e.target.closest('button[data-step]');
    if (!b || e.button !== 0) return;
    e.preventDefault();
    const k = b.dataset.for, dir = +b.dataset.step, big = e.shiftKey;
    undoStack.push(snapshot());
    redoStack.length = 0;
    stepOnce(k, dir, big);
    const stop = () => { if (stepHold) { clearTimeout(stepHold); stepHold = null; } };
    stop();
    const again = (delay) => { stepHold = setTimeout(() => { if (stepOnce(k, dir, big)) again(60); }, delay); };
    again(380);
    window.addEventListener('pointerup', stop, { once: true });
    window.addEventListener('pointercancel', stop, { once: true });
  });
  function setProp(k, v) {
    const it = selected();
    if (!it) return;
    if (!isFinite(v)) return;
    if (k === 'len') v = Math.max(v, sel.type === 'piece' ? 4 : 0.5);
    if (k === 'w') v = clamp(v, sel.type === 'piece' ? 2.5 : 0.6, 20);
    if (k === 'rise') v = clamp(v, 0.3, 4);
    if (k === 'bank') v = clamp(v, -15, 15);
    // Yolu taşırken üstündekiler de gelsin
    if (sel.type === 'piece' && (k === 'x' || k === 'z0')) {
      const d = v - it[k];
      for (const o of carried(it)) o[k] += d;
    }
    it[k] = r1(v);
  }
  $('props').addEventListener('click', (e) => {
    const it = selected();
    if (!it) return;
    const b = e.target.closest('button');
    if (!b) return;
    if (b.dataset.act === 'delete') return deleteSelected();
    if (b.dataset.act === 'dup') return duplicateSelected(+b.dataset.n || 1);
    if (b.dataset.tier) commit(() => { it.h0 = it.h1 = P.TIERS[b.dataset.tier]; });
    if (b.dataset.dir) commit(() => { it.dir = +b.dataset.dir; });
  });

  function renderLevelCard() {
    const st = analysis.stats;
    $('stats').innerHTML = [
      [`${st.length.toFixed(0)} m`, 'uzunluk'], [`~${st.time.toFixed(0)} sn`, 'sürüş süresi'],
      [st.jumps, 'atlama'], [level.crystals === false ? 'kapalı' : `~${st.crystals}`, 'kristal (otomatik)'],
    ].map(([b, s]) => `<div class="stat"><b>${b}</b><span>${s}</span></div>`).join('');
    $('at').value = level.at || 0;
    $('atLabel').textContent = `${(level.at || 0).toLocaleString('tr-TR')} m'den sonra`;
    $('speedLabel').textContent = `${P.speedAt(level.at || 0).toFixed(0)} m/sn`;
    $('diffLabel').textContent = level.pieces.length ? `${st.difficulty} / 5` : '–';
    $('diff').innerHTML = [1, 2, 3, 4, 5].map((i) => `<div class="${i <= st.difficulty ? 'on' : ''}"></div>`).join('');
  }
  let atDrag = false;
  $('at').addEventListener('input', (e) => {
    if (!atDrag) { undoStack.push(snapshot()); redoStack.length = 0; atDrag = true; }
    level.at = +e.target.value; saveJSON(KEY.current, level); render();
  });
  $('at').addEventListener('change', () => { atDrag = false; });

  function renderChecks() {
    const col = { error: 'var(--danger)', warn: 'var(--warn)', ok: 'var(--ok)' };
    const order = { error: 0, warn: 1, ok: 2 };
    const list = [...analysis.issues].sort((a, b) => order[a.level] - order[b.level]);
    $('checks').innerHTML = list.map((i, k) => `<div class="warn" data-k="${k}"><i style="background:${col[i.level]}"></i><div>${esc(i.text)}</div></div>`).join('');
    $('checks').querySelectorAll('.warn').forEach((el) => el.addEventListener('click', () => {
      const i = list[+el.dataset.k];
      if (i.ids.length) {
        const id = i.ids[0];
        sel = findPiece(id) ? { type: 'piece', id } : findObs(id) ? { type: 'obstacle', id } : null;
      }
      if (i.at !== undefined) scrollToZ(i.at); else render();
    }));
  }

  function renderResults() {
    const el = $('results');
    const mine = resultsFor === resultsKey() ? results : [];
    if (!mine.length) {
      el.innerHTML = `<div class="muted">"Test et" tasarımı oyunda otomatik pilotla 7 kez, her arabayla bir kez sürer. Düşülen yerler tuvalde ✕ ile işaretlenir.</div>`;
      return;
    }
    const ok = mine.filter((r) => r.ok).length;
    const auto = mine.filter((r) => r.auto);
    el.innerHTML = `<div class="res-top">${auto.length ? 'Otomatik pilot' : 'Senin sürüşün'}<div class="bar"><div style="width:${100 * ok / mine.length}%;background:var(--ok)"></div><div style="width:${100 * (mine.length - ok) / mine.length}%;background:var(--danger)"></div></div>${ok}/${mine.length}</div>
      <div class="res-list">${mine.map((r) => `${MODEL_NAMES[r.model] || 'Araba'}: ${r.ok ? '<b class="ok">geçti</b>' : `<b class="no">${esc(r.reason.toLowerCase().replace('!', ''))}</b> (${r.z.toFixed(0)}. metre)`}`).join('<br>')}</div>`;
  }

  // ------------------------------------------------------------------ etkileşim: tuval
  let drag = null;
  // Yolu taşırken üstündeki engeller de taşınır
  function carried(p) { return level.obstacles.filter((o) => P.hostOf(level, o) === p); }
  const snapX = (x) => Math.round(x * 2) / 2;
  const snapZ = (z) => Math.round(z);

  svgTop.addEventListener('pointerdown', (e) => {
    if (e.button !== 0) return;
    const w = clientToWorld(e);
    const hEl = viewing ? null : e.target.closest('[data-handle]');
    const gEl = viewing ? null : e.target.closest('[data-type]');
    if (hEl && sel) {
      const it = selected();
      drag = { mode: 'resize', handle: hEl.dataset.handle, start: w, orig: { ...it }, snap: snapshot(), moved: false };
    } else if (gEl) {
      const type = gEl.dataset.type, id = +gEl.dataset.id;
      sel = { type, id };
      let it = selected();
      const snap = snapshot();
      let carry = type === 'piece' ? carried(it) : [];
      let dup = null;
      if (e.altKey) {
        // Alt+sürükle: aynı boyda kopyasını sürükle (asıl yerinde kalır)
        const c = cloneItem(type, it, 0, 0);
        dup = id;
        it = c.copy;
        carry = c.kids;
        sel = { type, id: it.id };
      }
      drag = { mode: 'move', start: w, orig: { ...it }, snap, moved: false, dup,
        carry: carry.map((o) => ({ o, x: o.x, z0: o.z0 })) };
      render();
    } else {
      sel = null;
      drag = { mode: 'pan', sx: e.clientX, sy: e.clientY, cx: view.cx, zb: view.zb };
      wrap.classList.add('panning');
      render();
    }
    svgTop.setPointerCapture(e.pointerId);
  });
  svgTop.addEventListener('pointerleave', () => { hover = null; });
  svgTop.addEventListener('pointermove', (e) => {
    hover = clientToWorld(e);
    if (!drag) return;
    if (drag.mode === 'pan') {
      view.cx = drag.cx - (e.clientX - drag.sx) / view.sx;
      view.zb = drag.zb + (e.clientY - drag.sy) / view.sz;
      render();
      return;
    }
    const w = clientToWorld(e);
    const dx = w.x - drag.start.x, dz = w.z - drag.start.z;
    if (!drag.moved && Math.abs(dx) * view.sx < 3 && Math.abs(dz) * view.sz < 3) return;
    drag.moved = true;
    const it = selected();
    if (!it) return;
    guide = null;
    if (drag.mode === 'move') {
      it.x = snapX(drag.orig.x + dx);
      it.z0 = snapZ(drag.orig.z0 + dz);
      if (sel.type === 'piece') {
        const m = magnet(it);
        if (m) { it.z0 = m.z0; if (m.x !== undefined) it.x = m.x; guide = m.guide; }
        for (const c of drag.carry) { c.o.x = r1(c.x + (it.x - drag.orig.x)); c.o.z0 = r1(c.z0 + (it.z0 - drag.orig.z0)); }
      } else if (it.kind === 'bump' || it.kind === 'deadend') {
        const host = P.hostOf(level, it);
        if (host) { it.x = host.x; it.w = host.w; }
      }
    } else if (drag.mode === 'resize') {
      const o = drag.orig;
      const minL = sel.type === 'piece' ? 4 : 0.5, minW = sel.type === 'piece' ? 2.5 : 0.6;
      if (drag.handle === 'n') it.len = Math.max(minL, snapZ(o.len + dz));
      if (drag.handle === 's') { const nz = Math.min(snapZ(o.z0 + dz), o.z0 + o.len - minL); it.len = o.len - (nz - o.z0); it.z0 = nz; }
      if (drag.handle === 'e') { const right = Math.max(snapX(o.x + o.w / 2 + dx), o.x - o.w / 2 + minW); it.w = right - (o.x - o.w / 2); it.x = (o.x - o.w / 2) + it.w / 2; }
      if (drag.handle === 'w') { const left = Math.min(snapX(o.x - o.w / 2 + dx), o.x + o.w / 2 - minW); it.w = (o.x + o.w / 2) - left; it.x = left + it.w / 2; }
    }
    render();
  });
  svgTop.addEventListener('pointerup', () => {
    wrap.classList.remove('panning');
    if (drag && drag.dup && !drag.moved) {
      // Alt+tık (sürüklemeden): kopya üst üste kalmasın
      level = JSON.parse(drag.snap);
      sel = { type: sel.type, id: drag.dup };
    } else if (drag && drag.moved && drag.mode !== 'pan') {
      undoStack.push(drag.snap);
      redoStack.length = 0;
      changed();
    }
    guide = null;
    drag = null;
    render();
  });
  // Önceki ana yolun ucuna mıknatıs: o hızda önerilen boşlukla ve aynı hizada
  function magnet(p) {
    let best = null;
    for (const A of level.pieces) {
      if (A === p || A.side || p.side) continue;
      const end = P.pEnd(A);
      if (end > p.z0 + 5) continue;
      const dh = (p.h0 || 0) - (A.h1 ?? A.h0 ?? 0);
      const gap = P.suggestGap(level, A, dh);
      const target = end + gap;
      if (Math.abs(p.z0 - target) < 10 / Math.max(view.sz / 2.2, 0.4) && (!best || Math.abs(p.z0 - target) < best.d)) {
        best = { d: Math.abs(p.z0 - target), z0: target, x: Math.abs(p.x - A.x) < 2 ? A.x : undefined,
          guide: { z: target, text: `önerilen boşluk ${gap} m (${P.speedAt((level.at || 0) + end).toFixed(0)} m/sn)` } };
      }
    }
    return best;
  }

  wrap.addEventListener('wheel', (e) => {
    e.preventDefault();
    if (e.ctrlKey || e.metaKey) {
      const r = svgTop.getBoundingClientRect();
      const before = toWorld(e.clientX - r.left, e.clientY - r.top);
      const f = Math.exp(-e.deltaY * 0.0025);
      view.sx = clamp(view.sx * f, 2, 40); view.sz = clamp(view.sz * f, 0.4, 12);
      const after = toWorld(e.clientX - r.left, e.clientY - r.top);
      view.cx += before.x - after.x; view.zb += before.z - after.z;
    } else if (e.shiftKey) {
      view.cx += e.deltaY / view.sx * 0.5;
    } else {
      view.zb -= e.deltaY / view.sz * 0.6;
      view.cx += e.deltaX / view.sx * 0.5;
    }
    render();
  }, { passive: false });
  const zoom = (f) => { const c = toWorld(W / 2, H / 2); view.sx = clamp(view.sx * f, 2, 40); view.sz = clamp(view.sz * f, 0.4, 12); const a = toWorld(W / 2, H / 2); view.cx += c.x - a.x; view.zb += c.z - a.z; render(); };
  $('zoomIn').onclick = () => zoom(1.25);
  $('zoomOut').onclick = () => zoom(0.8);
  $('zoomFit').onclick = () => { fitView(); render(); };

  // ------------------------------------------------------------------ etkileşim: paletten sürükleme
  const ghost = $('ghost');
  function startPaletteDrag(e, group, item) {
    e.preventDefault();
    const tile = e.currentTarget;
    ghost.innerHTML = tile.outerHTML;
    ghost.style.display = 'block';
    ghost.firstChild.style.width = tile.offsetWidth + 'px';
    const move = (ev) => {
      ghost.style.left = ev.clientX - tile.offsetWidth / 2 + 'px';
      ghost.style.top = ev.clientY - 24 + 'px';
      const r = svgTop.getBoundingClientRect();
      const inside = ev.clientX > r.left && ev.clientX < r.right && ev.clientY > r.top && ev.clientY < r.bottom;
      ghost.style.opacity = inside ? 0.25 : 0.9;
      ghostItem = inside ? makeDrop(group, item, clientToWorld(ev)) : null;
      guide = ghostItem && ghostItem.guide ? ghostItem.guide : null;
      render();
    };
    const up = (ev) => {
      document.removeEventListener('pointermove', move);
      document.removeEventListener('pointerup', up);
      ghost.style.display = 'none';
      const drop = ghostItem;
      ghostItem = null; guide = null;
      if (!drop) { render(); return; }
      if (drop.error) { toast(drop.error); render(); return; }
      commit(() => placeDrop(drop));
    };
    document.addEventListener('pointermove', move);
    document.addEventListener('pointerup', up);
    move(e);
  }

  // Bırakılacak parçanın yerini hesaplar (mıknatısla); tuvalde önizlenir
  function makeDrop(group, item, w) {
    if (group === 'roads') {
      const p = { ...item.make(), x: snapX(w.x), z0: 0 };
      p.z0 = snapZ(w.z - p.len / 2);
      if (!level.pieces.length) { p.x = 0; p.z0 = 0; }
      // Ana yolla aynı aralıkta ve yanında duruyorsa yan yol olur
      p.side = level.pieces.some((q) => !q.side && Math.min(P.pEnd(q), P.pEnd(p)) - Math.max(q.z0, p.z0) > 5);
      const m = magnet(p);
      if (m) { p.z0 = m.z0; if (m.x !== undefined) p.x = m.x; }
      return { type: 'piece', item: p, guide: m && m.guide };
    }
    if (group === 'obstacles') {
      const o = { ...item.make(), x: snapX(w.x), z0: snapZ(w.z - (item.key === 'block' ? 0 : 4)) };
      const host = level.pieces.filter((p) => P.isOn(o, p)).sort((a, b) => (a.side ? 1 : 0) - (b.side ? 1 : 0))[0];
      if (!host) return { type: 'obstacle', item: o, error: 'Engeli bir yolun üstüne bırak.' };
      if (o.kind === 'bump') { o.x = host.x; o.w = host.w; }
      if (o.kind === 'deadend') { o.x = host.x; o.w = host.w; o.z0 = P.pEnd(host) - 1.5; }
      o.x = clamp(o.x, host.x - host.w / 2 + o.w / 2, host.x + host.w / 2 - o.w / 2);
      if (o.kind === 'kick') autoKick(o, host);
      return { type: 'obstacle', item: o, host };
    }
    return { type: 'pattern', items: makePattern(item.key, snapX(w.x), snapZ(w.z)) };
  }
  // Eğik rampa: attığı yöndeki en yakın yola göre yön ve yana atış
  function autoKick(o, host) {
    let best = null;
    for (const p of level.pieces) {
      if (p === host || P.pEnd(p) < o.z0 + 10 || p.z0 > o.z0 + 90) continue;
      const d = p.x - o.x;
      if (Math.abs(d) < 2) continue;
      if (!best || Math.abs(d) < Math.abs(best)) best = d;
    }
    if (best !== null) { o.dir = Math.sign(best); o.dx = r1(Math.abs(best)); }
  }
  function placeDrop(drop) {
    let id = nextId();
    if (drop.type === 'piece') {
      level.pieces.push({ id, ...drop.item });
      sel = { type: 'piece', id };
      if (drop.item.side) toast('Ana yolun yanına kondu: yan yol olarak işaretlendi.');
    } else if (drop.type === 'obstacle') {
      const o = { id, ...drop.item };
      delete o.host;
      level.obstacles.push(o);
      if (o.kind === 'deadend' && drop.host) { drop.host.side = true; toast('Çıkmaz: bu yol yan yol oldu, sonunda blok var.'); }
      sel = { type: 'obstacle', id };
    } else {
      for (const it of drop.items) {
        if (it.kind) level.obstacles.push({ id: id++, ...it });
        else level.pieces.push({ id: id++, ...it });
      }
      sel = null;
    }
  }

  // Hazır kalıplar: o hızda geçilebilir olacak şekilde hesaplanır
  function makePattern(key, x, z) {
    const tmp = { ...level, pieces: [], obstacles: [] };
    const out = [];
    const v = P.speedAt((level.at || 0) + z);
    const road = (o) => { out.push(o); return o; };
    if (key === 'stairs') {
      let zz = z, h = 0, prev = null;
      for (let i = 0; i < 3; i++) {
        const p = road({ x, w: 8, z0: zz, len: 0, h0: h, h1: h });
        if (prev) { p.z0 = P.pEnd(prev) + P.suggestGap(tmp, prev, -3); }
        p.len = P.minRoadLength(tmp, p.z0, 25, -3) + 6;
        prev = p; h -= 3; zz = p.z0;
      }
    } else if (key === 'islands') {
      const t = P.flightTime(0, P.CAR.launchVelocity);
      const hop = Math.round((P.CAR.carLen + v * t) * 0.62);
      let zz = z;
      for (let i = 0; i < 4; i++) {
        const isl = road({ x: x + (i % 2 ? 2 : -2), w: 6, z0: zz, len: i === 3 ? P.minRoadLength(tmp, zz, 25, 0) + 10 : Math.round(v * 0.75), h0: 0, h1: 0 });
        zz = P.pEnd(isl) + hop;
      }
    } else if (key === 'slalom') {
      const p = road({ x, w: 9, z0: z, len: 0, h0: 0, h1: 0 });
      const fl = P.CAR.carLen + v * P.flightTime(-0.8, P.CAR.launchVelocity + v * 0.16);
      const step = Math.round(5 + fl + v * 0.8);
      let zz = z + Math.round(P.vBoost(v) * 0.6 + 12);
      for (let i = 0; i < 4; i++) {
        out.push({ kind: 'ramp', x: x + (i % 2 ? 2.25 : -2.25), w: 4.5, z0: zz, len: 5, rise: 0.8 });
        zz += step;
      }
      p.len = Math.round(zz - z + P.clearEnd(v) + 6);
    } else if (key === 'fork') {
      const a = road({ x, w: 14, z0: z, len: 120, h0: 0, h1: 0 });
      out.push({ kind: 'kick', x: x + 4, w: 4.5, z0: z + 70, len: 8, rise: 1.8, dir: 1, dx: 6 });
      const gap = P.suggestGap(tmp, a, -2);
      road({ x: x - 4, w: 7, z0: P.pEnd(a) + gap, len: 110, h0: -2, h1: -2 });
      road({ x: x + 10, w: 4.5, z0: z + 100, len: 120, h0: 2, h1: 2, side: true });
    }
    return out;
  }

  // ------------------------------------------------------------------ türevler
  // Kalıptan türetilen versiyonlar (physics.js vary: oyunun kurallarıyla, kontrolden geçenler).
  // Oyun her gelişte kendisi de yeni türev üretir; burada işaretlenenler ayrıca oyuna girer.
  let viewing = null;                    // { base, v }: tuvalde gösterilen türev
  const baseLevel = () => (viewing ? viewing.base : level);
  const variantKey = (v) => `${baseLevel().name}#${v.id}`;
  const resultsKey = () => (viewing ? variantKey(viewing.v) : level.name);
  const baseSig = (l) => P.signature(l);
  function generateVariants() {
    if (viewing) exitView();
    if (!level.pieces.length) { toast('Önce bir kalıp çiz.'); return; }
    const sig = baseSig(level);
    // İşaretli ya da test edilmiş ve kalıbı değişmemiş türevler kalır, gerisi yenilenir
    const keep = (level.variants || []).filter((v) => v.base === sig && (v.on || (v.test && v.test.n)));
    const avoid = keep.map((v) => P.signature(v));
    let id = keep.reduce((m, v) => Math.max(m, v.id), 0) + 1;
    const fresh = [];
    for (let t = 0; t < 12 && keep.length + fresh.length < 4; t++) {
      const V = P.vary(level, (Math.random() * 1e9) >>> 0, avoid);
      if (!V) continue;
      avoid.push(V.sig);
      fresh.push({ id: id++, tags: V.tags, changed: V.changed, on: false, test: null, base: sig,
        pieces: V.level.pieces, obstacles: V.level.obstacles });
    }
    if (!fresh.length && !keep.length) { toast('Bu kalıptan güvenli türev bulunamadı: boşluklar ya da yollar sınırda olabilir.'); return; }
    commit(() => { level.variants = [...keep, ...fresh]; });
  }
  function viewVariant(v) {
    const base = baseLevel();
    viewing = { base, v };
    level = { ...base, pieces: JSON.parse(JSON.stringify(v.pieces)), obstacles: JSON.parse(JSON.stringify(v.obstacles)) };
    sel = null;
    render();
  }
  function exitView() {
    if (!viewing) return;
    level = viewing.base;
    viewing = null;
    render();
  }
  function openVariantAsLevel() {
    const { base, v } = viewing;
    exitView();
    saveToLibrary();
    useLevel({ ...base, name: `${base.name} — türev ${v.id}`, pieces: JSON.parse(JSON.stringify(v.pieces)),
      obstacles: JSON.parse(JSON.stringify(v.obstacles)), variants: [] });
    toast(`Türev ${v.id} ayrı kalıp olarak açıldı; asıl kalıp Kaydedilenler'de.`);
  }
  function thumbSVG(l, changed) {
    const ps = l.pieces;
    if (!ps.length) return '';
    const zMin = Math.min(...ps.map((p) => p.z0)), zMax = Math.max(...ps.map(P.pEnd));
    const xMin = Math.min(...ps.map((p) => p.x - p.w / 2)), xMax = Math.max(...ps.map((p) => p.x + p.w / 2));
    const TW = 112, TH = 150, sz = (TH - 8) / Math.max(zMax - zMin, 1), sx = Math.min((TW - 10) / Math.max(xMax - xMin, 1), 4);
    const X = (x) => TW / 2 + (x - (xMin + xMax) / 2) * sx, Y = (z) => TH - 4 - (z - zMin) * sz;
    const ch = new Set(changed || []);
    const hi = (id, w) => (ch.has(id) ? ` stroke="#ff5a1f" stroke-width="${w}"` : '');
    const out = [`<svg viewBox="0 0 ${TW} ${TH}" width="${TW}" height="${TH}">`];
    for (const p of ps) {
      const t = tierOf(Math.max(p.h0 || 0, p.h1 ?? p.h0 ?? 0));
      out.push(`<rect x="${X(p.x - p.w / 2)}" y="${Y(P.pEnd(p))}" width="${p.w * sx}" height="${p.len * sz}" fill="${ROAD_COLOR[t]}" rx="1"${hi(p.id, 1.6)}/>`);
    }
    for (const o of l.obstacles) {
      const c = o.kind === 'gravel' ? '#b9a98f' : o.kind === 'block' || o.kind === 'deadend' ? '#e23b3b' : '#f4d9a8';
      const len = Math.max(o.len || 1, 3 / sz);
      out.push(`<rect x="${X(o.x - o.w / 2)}" y="${Y(o.z0 + len)}" width="${Math.max(o.w * sx, 2)}" height="${len * sz}" fill="${c}"${hi(o.id, 1.1)}/>`);
    }
    return out.join('') + '</svg>';
  }
  function renderVariants() {
    const base = baseLevel();
    const vs = base.variants || [];
    const sig = baseSig(base);
    const ban = $('variantBanner');
    ban.style.display = viewing ? 'flex' : 'none';
    if (viewing) $('variantBannerText').textContent = `Türev ${viewing.v.id} · ${viewing.v.tags.join(', ')}`;
    const on = vs.filter((v) => v.on).length;
    const cards = vs.map((v) => {
      const t = v.test;
      const out = t && t.n && t.ok / t.n < 0.8;
      const stale = v.base !== sig;
      const res = !t ? `<span class="ok" title="Fizik kontrolünden geçti">✓ kontrol</span><button class="vtest" data-vtest="${v.id}" title="Oyunda otomatik pilotla 7 kez (her arabayla) sür">Test</button>`
        : t.running ? '<span class="muted">test ediliyor…</span>'
        : `<span class="${t.ok === t.n ? 'ok' : out ? 'no' : 'warn'}">${out ? '✕' : '✓'} ${t.ok}/${t.n}</span>`;
      const chk = out ? '<span class="no">elendi</span>'
        : `<label class="vchk"><input type="checkbox" data-von="${v.id}" ${v.on ? 'checked' : ''}>oyuna girsin</label>`;
      return `<div class="vcard ${viewing && viewing.v.id === v.id ? 'cur' : ''} ${out ? 'bad' : ''}" data-vid="${v.id}">
        ${thumbSVG(v, v.changed)}<b>Türev ${v.id}${stale ? ' <span class="stale" title="Asıl kalıp sonradan değişti">eski</span>' : ''}</b>
        <div class="vtags">${v.tags.map((x) => `<span>${esc(x)}</span>`).join('')}</div>
        <div class="vres">${res}</div><div class="vres">${chk}</div></div>`;
    }).join('');
    $('variants').innerHTML = `<div class="vhead"><span class="muted">${vs.length ? `${vs.length} türev, ${on} tanesi oyuna giriyor.` : 'Kalıbından oyunun kurallarıyla güvenli versiyonlar türet.'}</span>
      <button class="btn" id="varGen">⟳ ${vs.length ? 'Yeniden' : 'Türet'}</button></div>
      ${vs.length ? `<div class="vgrid">${cards}</div>` : ''}
      <div class="muted" style="margin-top:8px">Oyun bu kalıbı her getirişinde ayrıca yeni bir türev üretir ve yarı yarıya aynalar: aynısı iki kez gelmez. Turuncu çerçeve: değişen parçalar.</div>`;
  }
  $('variants').addEventListener('click', (e) => {
    if (e.target.closest('#varGen')) return generateVariants();
    const tb = e.target.closest('[data-vtest]');
    if (tb) {
      const v = (baseLevel().variants || []).find((x) => x.id === +tb.dataset.vtest);
      if (v) openGame(true, v);
      return;
    }
    if (e.target.closest('label, input')) return;
    const card = e.target.closest('[data-vid]');
    if (!card) return;
    const v = (baseLevel().variants || []).find((x) => x.id === +card.dataset.vid);
    if (!v) return;
    if (viewing && viewing.v === v) exitView(); else viewVariant(v);
  });
  $('variants').addEventListener('change', (e) => {
    const id = +e.target.dataset.von;
    if (!id) return;
    const v = (baseLevel().variants || []).find((x) => x.id === id);
    if (!v) return;
    v.on = e.target.checked;
    saveJSON(KEY.current, baseLevel());
    render();
  });
  $('vbBack').onclick = exitView;
  $('vbOpen').onclick = openVariantAsLevel;

  // ------------------------------------------------------------------ klavye ve menü
  function deleteSelected() {
    if (!sel) return;
    commit(() => {
      if (sel.type === 'piece') {
        const p = findPiece(sel.id);
        const gone = new Set(carried(p).map((o) => o.id));
        level.obstacles = level.obstacles.filter((o) => !gone.has(o.id));
        level.pieces = level.pieces.filter((q) => q.id !== sel.id);
      } else level.obstacles = level.obstacles.filter((o) => o.id !== sel.id);
      sel = null;
    });
  }
  // Kopya (aynı boyda): yolsa üstündeki engellerle birlikte, dx/dz kadar ötede
  function cloneItem(type, it, dx, dz) {
    let id = nextId();
    const copy = { ...it, id: id++, x: r1(it.x + dx), z0: r1(it.z0 + dz) };
    const kids = [];
    if (type === 'piece') {
      for (const o of carried(it)) kids.push({ ...o, id: id++, x: r1(o.x + dx), z0: r1(o.z0 + dz) });
      level.obstacles.push(...kids);
      level.pieces.push(copy);
    } else level.obstacles.push(copy);
    lastDup = { type, src: it.id, copy: copy.id };
    return { copy, kids };
  }
  // Çoğalt: kopya ardına gelir. Kopyayı taşıyıp yine çoğaltırsan aynı aralıkla sürer (Figma gibi)
  let lastDup = null;
  function dupOffset(type, it) {
    const src = lastDup && lastDup.type === type && lastDup.copy === it.id &&
      (type === 'piece' ? findPiece(lastDup.src) : findObs(lastDup.src));
    if (src && (src.x !== it.x || src.z0 !== it.z0)) return [it.x - src.x, it.z0 - src.z0];
    if (type === 'piece') return [0, it.len + P.suggestGap(level, it, 0)];
    return [0, Math.max(it.len, 2) + 6];
  }
  function duplicateSelected(times) {
    const it = selected();
    if (!it) return;
    commit(() => {
      let cur = it;
      for (let i = 0; i < (times || 1); i++) {
        const [dx, dz] = dupOffset(sel.type, cur);
        cur = cloneItem(sel.type, cur, dx, dz).copy;
      }
      sel = { type: sel.type, id: cur.id };
    });
  }
  // Kopyala / yapıştır (Ctrl+C / Ctrl+V): fare tuvaldeyse imlecin olduğu yere
  let clip = null, hover = null;
  function copySelected() {
    const it = selected();
    if (!it) return;
    clip = { type: sel.type, it: { ...it }, kids: sel.type === 'piece' ? carried(it).map((o) => ({ ...o })) : [] };
    toast(`${sel.type === 'piece' ? 'Yol' : P.KIND_NAMES[it.kind]} kopyalandı: Ctrl+V ile imlecin olduğu yere yapıştır.`);
  }
  function paste() {
    if (!clip) return;
    const it = clip.it;
    const at = hover || { x: it.x, z: it.z0 + (clip.type === 'piece' ? it.len + 10 : Math.max(it.len, 2) + 6) };
    commit(() => {
      const dx = snapX(at.x) - it.x, dz = snapZ(at.z) - it.z0;
      let id = nextId();
      const copy = { ...it, id: id++, x: r1(it.x + dx), z0: r1(it.z0 + dz) };
      for (const o of clip.kids) level.obstacles.push({ ...o, id: id++, x: r1(o.x + dx), z0: r1(o.z0 + dz) });
      if (clip.type === 'piece') level.pieces.push(copy);
      else {
        level.obstacles.push(copy);
        const host = P.hostOf(level, copy);
        if (host && (copy.kind === 'bump' || copy.kind === 'deadend')) { copy.x = host.x; copy.w = host.w; }
      }
      sel = { type: clip.type, id: copy.id };
    });
  }
  // Alt basılıyken imleç "kopya" olur: Alt+sürükle çoğaltır
  const altCursor = (e) => wrap.classList.toggle('alt', e.altKey);
  document.addEventListener('keyup', altCursor);
  window.addEventListener('blur', () => wrap.classList.remove('alt'));
  document.addEventListener('keydown', (e) => {
    altCursor(e);
    if (e.target.tagName === 'INPUT') return;
    const k = e.key.toLowerCase();
    const mod = e.ctrlKey || e.metaKey;
    if (mod && k === 'z') { e.preventDefault(); e.shiftKey ? redo() : undo(); }
    else if (mod && k === 'y') { e.preventDefault(); redo(); }
    else if (mod && k === 'd') { e.preventDefault(); duplicateSelected(); }
    else if (mod && k === 'c') { copySelected(); }
    else if (mod && k === 'v') { e.preventDefault(); paste(); }
    else if (mod && k === 's') { e.preventDefault(); saveToLibrary(); }
    else if (k === 'delete' || k === 'backspace') { e.preventDefault(); deleteSelected(); }
    else if (k === 'escape') { if (viewing) exitView(); else { sel = null; render(); } }
    else if (sel && k.startsWith('arrow')) {
      e.preventDefault();
      const st = e.shiftKey ? 5 : 0.5;
      const it = selected();
      commit(() => {
        const dx = k === 'arrowleft' ? -st : k === 'arrowright' ? st : 0;
        const dz = k === 'arrowup' ? st * 2 : k === 'arrowdown' ? -st * 2 : 0;
        it.x = r1(it.x + dx); it.z0 = r1(it.z0 + dz);
        if (sel.type === 'piece') for (const o of carried({ ...it, x: it.x - dx, z0: it.z0 - dz })) { o.x = r1(o.x + dx); o.z0 = r1(o.z0 + dz); }
      });
    }
  });
  $('undoBtn').onclick = undo;
  $('redoBtn').onclick = redo;
  $('name').addEventListener('change', (e) => commit(() => { level.name = e.target.value.trim() || 'isimsiz'; }));
  $('crystals').addEventListener('change', (e) => commit(() => { level.crystals = e.target.checked; }));

  const fileMenu = $('fileMenu');
  $('fileBtn').onclick = (e) => { e.stopPropagation(); fileMenu.classList.toggle('open'); };
  document.addEventListener('click', () => fileMenu.classList.remove('open'));
  fileMenu.addEventListener('click', (e) => {
    const act = e.target.dataset.act;
    fileMenu.classList.remove('open');
    if (act === 'new') { if (level.pieces.length && !confirm('Yeni kalıp: şimdiki tasarım kaydedilmediyse kaybolur. Devam?')) return; commit(() => { level = newLevel(); sel = null; }); fitView(); render(); }
    if (act === 'open') openLibrary();
    if (act === 'import') $('fileInput').click();
    if (act === 'export') download();
    if (act === 'mirror') commit(() => { for (const p of level.pieces) { p.x = -p.x; if (p.bank) p.bank = -p.bank; } for (const o of level.obstacles) { o.x = -o.x; if (o.dir) o.dir = -o.dir; } });
    if (act === 'sample') loadSample();
  });
  $('fileInput').addEventListener('change', async (e) => {
    const f = e.target.files[0];
    if (!f) return;
    try { useLevel(JSON.parse(await f.text())); toast(`"${level.name}" açıldı.`); }
    catch (err) { toast('Dosya okunamadı: geçerli bir tasarım değil.'); }
    e.target.value = '';
  });
  function useLevel(l) {
    if (!l || !Array.isArray(l.pieces)) throw new Error('bozuk');
    commit(() => { level = { ...newLevel(), ...l, obstacles: l.obstacles || [] }; sel = null; });
    fitView(); render();
  }
  async function loadSample() {
    try {
      const r = await fetch('../levels/ornek_ada_atlayisi.json').catch(() => null);
      if (r && r.ok) { useLevel(await r.json()); return; }
    } catch (e) { /* dosya yoksa gömülü örnek */ }
    useLevel(SAMPLE);
  }
  const SAMPLE = { format: 'runny-level', version: 1, name: 'Örnek: Ada Atlayışı', at: 800, crystals: true,
    pieces: [{ id: 1, x: 0, w: 9, z0: 0, len: 160, h0: 0, h1: 0 }, { id: 2, x: -2, w: 8, z0: 188, len: 120, h0: 0, h1: 0 },
      { id: 3, x: 8, w: 5, z0: 268, len: 70, h0: 3, h1: 3, side: true }, { id: 4, x: 1, w: 8, z0: 336, len: 220, h0: 0, h1: 0 },
      { id: 5, x: 0, w: 9, z0: 584, len: 70, h0: 0, h1: 0 }],
    obstacles: [{ id: 6, kind: 'ramp', x: 0, w: 4, z0: 64, len: 8, rise: 1.6 }, { id: 7, kind: 'kick', x: 0, w: 3, z0: 258, len: 7, rise: 1.4, dir: 1, dx: 8 },
      { id: 8, kind: 'gravel', x: -3.5, w: 3, z0: 250, len: 12 }, { id: 9, kind: 'block', x: -1, w: 2, z0: 440, len: 1.2 },
      { id: 10, kind: 'bump', x: 1, w: 8, z0: 456, len: 12, rise: 1 }] };

  // ------------------------------------------------------------------ kayıt
  function cleanLevel() {
    const r = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, typeof v === 'number' ? r1(v) : v]));
    const L = viewing ? viewing.base : level;
    const out = { format: 'runny-level', version: 1, name: L.name, at: L.at || 0, crystals: L.crystals !== false,
      pieces: L.pieces.map(r), obstacles: L.obstacles.map(r) };
    if ((L.variants || []).length) {
      out.variants = L.variants.map((v) => ({ id: v.id, tags: v.tags, on: !!v.on, test: v.test || null, base: v.base,
        changed: v.changed, pieces: v.pieces.map(r), obstacles: v.obstacles.map(r) }));
    }
    return out;
  }
  function saveToLibrary() {
    const lib = loadJSON(KEY.library) || {};
    lib[level.name] = { level: cleanLevel(), saved: Date.now() };
    saveJSON(KEY.library, lib);
    toast(`"${level.name}" kaydedildi.`);
  }
  function openLibrary() {
    const lib = loadJSON(KEY.library) || {};
    const names = Object.keys(lib).sort((a, b) => lib[b].saved - lib[a].saved);
    $('libList').innerHTML = names.length ? names.map((n) => `<div class="libitem"><b>${esc(n)}</b><small>${new Date(lib[n].saved).toLocaleString('tr-TR')}</small><button class="btn" data-open="${esc(n)}">Aç</button><button class="btn ghost" data-del="${esc(n)}">Sil</button></div>`).join('')
      : '<div class="muted" style="padding:12px">Henüz kaydedilen kalıp yok. "Kaydet" ile buraya eklenir.</div>';
    $('libModal').classList.add('open');
  }
  $('libList').addEventListener('click', (e) => {
    const lib = loadJSON(KEY.library) || {};
    const o = e.target.dataset.open, d = e.target.dataset.del;
    if (o && lib[o]) { useLevel(lib[o].level); $('libModal').classList.remove('open'); }
    if (d && confirm(`"${d}" silinsin mi?`)) { delete lib[d]; saveJSON(KEY.library, lib); openLibrary(); }
  });
  $('libClose').onclick = () => $('libModal').classList.remove('open');
  function download() {
    const blob = new Blob([JSON.stringify(cleanLevel(), null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = (level.name || 'kalip').toLocaleLowerCase('tr').replace(/[^a-z0-9ğüşıöç]+/g, '_') + '.json';
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }
  $('saveBtn').onclick = saveToLibrary;
  $('copyBtn').onclick = async () => {
    const text = JSON.stringify(cleanLevel());
    try { await navigator.clipboard.writeText(text); toast('Tasarım panoya kopyalandı: sohbete yapıştırabilirsin.'); }
    catch (e) {
      const ta = document.createElement('textarea'); ta.value = text; document.body.appendChild(ta); ta.select();
      document.execCommand('copy'); ta.remove(); toast('Tasarım panoya kopyalandı.');
    }
  };

  // ------------------------------------------------------------------ oyunla bağlantı
  let lastGame = null;
  // variant verilirse o türev denenir (sonucu türev kartına yazılır)
  function openGame(auto, variant) {
    if (!level.pieces.length) { toast('Önce bir yol koy.'); return; }
    if (!variant && !viewing) {
      const errs = analysis.issues.filter((i) => i.level === 'error').length;
      if (errs && !confirm(`${errs} hata var; oyunda düşebilirsin. Yine de açılsın mı?`)) return;
    }
    if (!variant && viewing) variant = viewing.v;
    lastGame = { auto, variant };
    const base = cleanLevel();
    delete base.variants;
    const key = variant ? variantKey(variant) : level.name;
    saveJSON(KEY.test, variant ? { ...base, pieces: variant.pieces, obstacles: variant.obstacles } : base);
    saveJSON(KEY.result, []);
    localStorage.setItem('runny_editor_result_for', key);
    results = []; resultsFor = key;
    if (variant) { variant.test = { running: true }; saveJSON(KEY.current, baseLevel()); }
    const runs = 7;
    $('gameTitle').textContent = auto ? 'Test: otomatik pilot' : 'Oyna';
    $('gameInfo').textContent = auto ? `0/${runs} koşu` : 'Tasarım başlangıç pistinden sonra gelir';
    $('gameFrame').src = `${GAME_URL}?level=test${auto ? `&autopilot=1&runs=${runs}` : ''}&t=${Date.now()}`;
    $('gameModal').classList.add('open');
    $('gameModal').dataset.runs = auto ? runs : 0;
    render();
  }
  $('playBtn').onclick = () => openGame(false);
  $('testBtn').onclick = () => openGame(true);
  $('gameClose').onclick = () => { $('gameFrame').src = 'about:blank'; $('gameModal').classList.remove('open'); };
  // Baştan: oyun sahnesi anında yeniden kurulur (motor yeniden yüklenmez); testte bütün koşular baştan
  function restartGame() {
    const auto = +$('gameModal').dataset.runs > 0;
    if (auto) return openGame(true, lastGame && lastGame.variant);
    const w = $('gameFrame').contentWindow;
    if (w && typeof w.runnyRestart === 'function') w.runnyRestart();
    else $('gameFrame').src = `${GAME_URL}?level=test&t=${Date.now()}`;
    $('gameFrame').focus();
  }
  $('gameRestart').onclick = restartGame;
  // R tuşu: odak oyundayken de çalışsın (aynı adres: oyunun penceresi dinlenebilir)
  const onRestartKey = (e) => {
    if ((e.key === 'r' || e.key === 'R') && !e.ctrlKey && !e.metaKey && $('gameModal').classList.contains('open')) {
      e.preventDefault(); e.stopPropagation(); restartGame();
    }
  };
  $('gameFrame').addEventListener('load', () => {
    try { $('gameFrame').contentWindow.addEventListener('keydown', onRestartKey, true); } catch (err) { /* başka adres */ }
  });
  document.addEventListener('keydown', onRestartKey);
  // Oyun (aynı adres) sonuçları tarayıcı hafızasına yazar: burada dinlenir
  function pollResults() {
    const r = loadJSON(KEY.result) || [];
    if (JSON.stringify(r) !== JSON.stringify(results)) {
      results = r;
      const runs = +$('gameModal').dataset.runs || 0;
      if (runs) $('gameInfo').textContent = `${r.length}/${runs} koşu, ${r.filter((x) => x.ok).length} geçti`;
      // Türev testi bitti: sonucu karta yaz
      const v = (baseLevel().variants || []).find((x) => variantKey(x) === resultsFor);
      if (v && runs && r.length >= runs) {
        v.test = { ok: r.filter((x) => x.ok).length, n: r.length };
        if (v.test.ok / v.test.n < 0.8) v.on = false;
        saveJSON(KEY.current, baseLevel());
      }
      render();
    }
  }
  window.addEventListener('storage', (e) => { if (e.key === KEY.result) pollResults(); });
  setInterval(pollResults, 1000);

  let toastTimer = 0;
  function toast(text) {
    const t = $('toast');
    t.textContent = text;
    t.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove('show'), 2600);
  }

  // ------------------------------------------------------------------ başlat
  buildPalette();
  new ResizeObserver(() => render()).observe(wrap);
  W = wrap.clientWidth; H = wrap.clientHeight;
  fitView();
  render();
  window.RunnyEditor = { get level() { return level; }, set level(l) { useLevel(l); }, analyze: () => analysis, render, view };
})();

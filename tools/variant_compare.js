// Oyunun (level_check.gd) ve editörün (physics.js) kontrolleri aynı kalıplara aynı sonucu veriyor mu.
//   godot --headless --path . -s tools/variant_dump.gd -- levels/kalip.json 50 /tmp/t.json
//   node tools/variant_compare.js /tmp/t.json
const P = require('../editor/physics.js');
const list = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
let same = 0, diff = 0;
for (const [i, e] of list.entries()) {
  const A = P.analyze(e.level);
  const js = { errors: A.issues.filter((x) => x.level === 'error').length, warns: A.issues.filter((x) => x.level === 'warn').length };
  if (js.errors === e.check.errors && js.warns === e.check.warns) { same++; continue; }
  diff++;
  if (diff <= 8) {
    console.log(`#${i} [${e.tags.join(', ')}] oyun ${e.check.errors}h/${e.check.warns}u  editör ${js.errors}h/${js.warns}u`);
    console.log('  oyun  :', e.check.issues.join(' | '));
    console.log('  editör:', A.issues.filter((x) => x.level !== 'ok').map((x) => x.level + ': ' + x.text.slice(0, 50)).join(' | '));
  }
}
const bad = list.filter((e) => e.check.errors > 0).length;
console.log(`aynı ${same}, farklı ${diff} / ${list.length}  (oyunun hatalı bulduğu: ${bad})`);
process.exit(diff ? 1 : 0);

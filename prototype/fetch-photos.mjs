/**
 * Fetch topic-accurate proof photos from Wikimedia Commons into prototype/img/.
 * Each seed maps to a Commons search term; the first suitable image is used.
 * Photos are cached locally so the prototype renders offline and identically.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const IMG = path.join(HERE, 'img');
fs.mkdirSync(IMG, { recursive: true });

const UA = 'ReceiptsPrototype/1.0 (offline design prototype; contact: dev@example.com)';

const TARGETS = {
  // current-week proofs
  sunrise:     ['silhouettes at sunrise', 'sunrise viewpoint people watching'],
  recipe:      ['rice and curry plate meal', 'dal lentil curry bowl'],
  handstand:   ['handstand pushup', 'handstand against wall exercise'],
  texty:       ['sms text message screen', 'smartphone screen chat messages'],
  detour:      ['country road autumn trees', 'winding road countryside'],
  hilltop:     ['view over hills landscape', 'hilltop panorama valley'],
  mumdaal:     ['dal lentils bowl home cooking', 'majadra haystack plate'],
  mywall:      ['brick wall texture', 'plaster wall surface'],
  badelong:    ['walking path forest trail', 'forest walking path'],
  // older-week feed history
  balcony:     ['city at night illuminated', 'medieval city by night'],
  kitchen:     ['kitchen sink with dishes', 'kitchen worktop counter'],
  stairs:      ['outdoor stone staircase', 'stone steps'],
  laundry:     ['folded towels stack', 'pile of folded clothes'],
  street:      ['street at night lit', 'walking in the city at night'],
  berlinbalcony: ['river spree berlin', 'berlin skyline'],
  driving:     ['car interior driving', 'driving position car'],
  gymset:      ['gym dumbbell workout', 'weight lifting gym'],
  // onboarding / camera
  proofstack:  ['polaroid instant photographs', 'instant camera photos'],
  kitchenproof:['boiling pot kitchen stove', 'cooking pot on stove'],
  votehand:    ['thumbs up hand gesture', 'thumbs up by wakalani'],
  camview:     ['mountain landscape panorama', 'alpine village landscape'],
  camvideo:    ['sea waves coast', 'long spit sea']
};

const api = async (params) => {
  const url = 'https://commons.wikimedia.org/w/api.php?' + new URLSearchParams({
    action: 'query', generator: 'search', gsrnamespace: '6',
    prop: 'imageinfo', iiprop: 'url|mime|size', iiurlwidth: '900',
    format: 'json', ...params
  });
  const r = await fetch(url, { headers: { 'User-Agent': UA } });
  return r.json();
};

const grab = async (name, terms) => {
  const out = path.join(IMG, name + '.jpg');
  if (fs.existsSync(out) && fs.statSync(out).size > 20000) { console.log('  cached', name); return true; }
  for (const term of terms) {
    try {
      const d = await api({ gsrsearch: term, gsrlimit: '12' });
      const pages = Object.values(d?.query?.pages || {});
      for (const p of pages) {
        const ii = p.imageinfo?.[0];
        if (!ii) continue;
        if (!/jpeg|png/.test(ii.mime || '')) continue;
        if (ii.width < 700 || ii.height < 700) continue;
        const src = ii.thumburl || ii.url;
        const res = await fetch(src, { headers: { 'User-Agent': UA } });
        if (!res.ok) continue;
        const buf = Buffer.from(await res.arrayBuffer());
        if (buf.length < 20000) continue;
        fs.writeFileSync(out, buf);
        console.log('  ✓', name, '←', p.title.replace('File:', '').slice(0, 70));
        return true;
      }
    } catch (e) { /* try next term */ }
  }
  console.log('  ✗', name, 'NO MATCH');
  return false;
};

let ok = 0;
for (const [name, terms] of Object.entries(TARGETS)) {
  if (await grab(name, terms)) ok++;
}
console.log(`\n${ok}/${Object.keys(TARGETS).length} photos fetched`);

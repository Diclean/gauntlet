/**
 * Prototype check — loads prototype/index.html in headless Chromium,
 * walks every "Jump to screen" entry, screenshots each one, and exercises
 * the interactive bits (vote drag, prove-it flow, dark mode).
 *
 *   node prototype/check.mjs            # light mode sweep
 *   node prototype/check.mjs --dark     # dark mode sweep too
 *
 * Screenshots land in prototype/shots/.
 */
import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FILE = 'file://' + path.join(HERE, 'index.html');
const SHOTS = path.join(HERE, 'shots');
const W = 1100, H = 950;
const DARK = process.argv.includes('--dark');

fs.mkdirSync(SHOTS, { recursive: true });

const errors = [];
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });

page.on('console', (m) => {
  if (m.type() === 'error') errors.push(`console.error: ${m.text()}`);
  if (m.type() === 'warning' && /deprecat|violation/i.test(m.text())) errors.push(`console.warn: ${m.text()}`);
});
page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
page.on('requestfailed', (r) => errors.push(`requestfailed: ${r.url()} ${r.failure()?.errorText || ''}`));

await page.goto(FILE, { waitUntil: 'load' });
await page.waitForTimeout(700);

/* ---------- helper: screenshot the phone only ---------- */
async function shoot(name) {
  const file = path.join(SHOTS, name + '.png');
  await page.screenshot({ path: file });
  return file;
}
async function shootPhone(name) {
  const file = path.join(SHOTS, name + '.png');
  await page.locator('.device').screenshot({ path: file });
  return file;
}

/* ---------- jump menu sweep ---------- */
const entries = await page.$$eval('#jump .jump__b', (els) =>
  els.map((e) => ({ key: e.dataset.jump, label: e.textContent.trim() }))
);

console.log(`jump entries: ${entries.length}`);

const shotList = [];
let n = 0;
for (const e of entries) {
  n++;
  const id = String(n).padStart(2, '0');
  const slug = e.key.replace(/:/g, '-');
  await page.click(`#jump .jump__b[data-jump="${e.key}"]`);
  await page.waitForTimeout(420);
  const name = `${id}-${slug}`;
  const f = await shoot(name);
  shotList.push({ name, label: e.label, file: f });
  console.log(`  ${name}  —  ${e.label}`);
}

/* ---------- reset to a known state ---------- */
await page.click('#resetBtn');
await page.waitForTimeout(300);

/* ---------- drag a vote card right (approve) ---------- */
async function dragCard(dir) {
  await page.click('#jump .jump__b[data-jump="vote"]');
  await page.waitForTimeout(450);
  const card = page.locator('.vcard[data-top]').first();
  const box = await card.boundingBox();
  if (!box) { errors.push('drag: no vote card found'); return; }
  const cx = box.x + box.width / 2, cy = box.y + box.height / 2;
  const dx = dir * 190;
  await page.mouse.move(cx, cy);
  await page.mouse.down();
  for (let i = 1; i <= 14; i++) {
    await page.mouse.move(cx + (dx * i) / 14, cy + (i % 3) * 1.5);
    await page.waitForTimeout(16);
  }
  await page.waitForTimeout(120);
  await page.mouse.up();
  await page.waitForTimeout(1500);
}

await dragCard(1);   // swipe right => approve
await shootPhone('20-vote-drag-right');
shotList.push({ name: '20-vote-drag-right', label: 'Vote card dragged right (approve)', file: path.join(SHOTS, '20-vote-drag-right.png') });

await page.click('#resetBtn');
await page.waitForTimeout(250);
await dragCard(-1);  // swipe left => reject
await shootPhone('21-vote-drag-left');
shotList.push({ name: '21-vote-drag-left', label: 'Vote card dragged left (reject)', file: path.join(SHOTS, '21-vote-drag-left.png') });

/* ---------- prove it flow -> pending stamp ---------- */
await page.click('#resetBtn');
await page.waitForTimeout(250);
await page.click('#jump .jump__b[data-jump="challenge"]');
await page.waitForTimeout(400);
// pick a challenge that still needs proof
await page.click('#jump .jump__b[data-jump="week"]');
await page.waitForTimeout(300);
const rows = await page.$$('#app .crow');
if (rows.length) {
  await rows[0].click();
  await page.waitForTimeout(400);
}
const proveBtn = page.locator('#app button[data-act="proveIt"]');
if (await proveBtn.count()) {
  await proveBtn.click();
  await page.waitForTimeout(500);
  await shootPhone('22-camera');
  shotList.push({ name: '22-camera', label: 'Camera cover', file: path.join(SHOTS, '22-camera.png') });
  const shutter = page.locator('#app button[data-act="shutter"]');
  if (await shutter.count()) { await shutter.click(); await page.waitForTimeout(700); }
  await shootPhone('23-preview');
  shotList.push({ name: '23-preview', label: 'Preview + caption', file: path.join(SHOTS, '23-preview.png') });
  const post = page.locator('#app button[data-act="postProof"]');
  if (await post.count()) {
    await post.click();
    await page.waitForTimeout(2600);   // upload completes -> pending stamp
    await shootPhone('24-upload-pending-stamp');
    shotList.push({ name: '24-upload-pending-stamp', label: 'Upload done — PENDING stamp', file: path.join(SHOTS, '24-upload-pending-stamp.png') });
  } else {
    errors.push('proveIt: no postProof button found');
  }
} else {
  errors.push('proveIt: no proveIt button found');
}

/* ---------- extra states ---------- */
async function shotDevice(name) {
  const file = path.join(SHOTS, name + '.png');
  await page.locator('.device').screenshot({ path: file });
  shotList.push({ name, label: name, file });
  console.log('  ' + name);
}

// hazard banner (deadline in the last 24h)
await page.click('#resetBtn');
await page.waitForTimeout(250);
await page.click('#hazardBtn');
await page.waitForTimeout(350);
await shotDevice('30-hazard-deadline');

// feed in list mode
await page.click('#resetBtn');
await page.waitForTimeout(250);
await page.click('#jump .jump__b[data-jump="feed"]');
await page.waitForTimeout(350);
await page.click('#app .seg button[data-m="list"]');
await page.waitForTimeout(350);
await shotDevice('31-feed-list');

// group picker sheet
await page.click('#resetBtn');
await page.waitForTimeout(250);
await page.click('#jump .jump__b[data-jump="week"]');
await page.waitForTimeout(350);
await page.click('#app .tb-group');
await page.waitForTimeout(450);
await shotDevice('32-group-picker-sheet');
await page.click('#overlay .scrim');
await page.waitForTimeout(300);

// leave-group confirmation dialog
await page.click('#jump .jump__b[data-jump="groupSettings"]');
await page.waitForTimeout(400);
const leave = page.locator('#app button[data-act="leaveGroup"]');
if (await leave.count()) {
  await leave.click();
  await page.waitForTimeout(450);
  await shotDevice('33-alert-leave-group');
  await page.click('#overlay button[data-act="alertCancel"]');
  await page.waitForTimeout(250);
}

// emoji picker sheet from profile
await page.click('#jump .jump__b[data-jump="profile"]');
await page.waitForTimeout(400);
const face = page.locator('#app button[data-act="changeEmoji"]');
if (await face.count()) {
  await face.click();
  await page.waitForTimeout(450);
  await shotDevice('34-emoji-sheet');
  await page.click('#overlay .scrim');
  await page.waitForTimeout(250);
}

// board — all time scope
await page.click('#jump .jump__b[data-jump="board"]');
await page.waitForTimeout(350);
await page.click('#app .seg button[data-s="all"]');
await page.waitForTimeout(400);
await shotDevice('35-board-all-time');

// challenge detail — accepted variant
await page.click('#resetBtn');
await page.waitForTimeout(250);
await page.click('#jump .jump__b[data-jump="week"]');
await page.waitForTimeout(350);
const rows2 = await page.$$('#app .crow');
if (rows2[3]) { await rows2[3].click(); await page.waitForTimeout(400); }
await shotDevice('36-challenge-accepted');

/* ---------- dark mode sweep of every screen ---------- */
if (DARK) {
  await page.click('#resetBtn');
  await page.waitForTimeout(250);
  await page.click('#themeBtn');
  await page.waitForTimeout(400);
  let m = 0;
  for (const e of entries) {
    m++;
    const id = String(m).padStart(2, '0');
    const slug = e.key.replace(/:/g, '-');
    await page.click(`#jump .jump__b[data-jump="${e.key}"]`);
    await page.waitForTimeout(400);
    const name = `d${id}-${slug}`;
    const f = await shoot(name);
    shotList.push({ name, label: `dark — ${e.label}`, file: f });
    console.log(`  ${name}  —  dark — ${e.label}`);
  }
}

/* ---------- report ---------- */
console.log('\n=== screenshots ===');
for (const s of shotList) console.log(`${s.name}.png  — ${s.label}`);

console.log('\n=== errors ===');
if (errors.length === 0) console.log('ZERO console/page errors.');
else { errors.forEach(e => console.log('  ' + e)); console.log(`${errors.length} error(s).`); }

await browser.close();
process.exit(errors.length ? 1 : 0);

/**
 * Interaction test — proves the live behaviours work, not just that the
 * screens render. Fails loudly (exit 1) if any assertion breaks.
 *
 *   node prototype/interact.mjs
 */
import { chromium } from 'playwright';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const FILE = 'file://' + path.join(HERE, 'index.html');
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

const errors = [];
const fails = [];
const ok = [];
const check = (name, cond, detail = '') => {
  (cond ? ok : fails).push(name + (detail ? ` — ${detail}` : ''));
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${detail ? '  (' + detail + ')' : ''}`);
};

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1100, height: 950 } });
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', (e) => errors.push(e.message));

await page.goto(FILE, { waitUntil: 'load' });
await page.waitForTimeout(700);

/* 1 — the jump menu is populated */
const jumpCount = await page.$$eval('#jump .jump__b', (e) => e.length);
check('jump menu is populated', jumpCount > 20, `${jumpCount} entries`);

/* 2 — the app booted to onboarding and renders */
check('onboarding renders', await page.locator('.onb__t').count() === 1);

/* 3 — app name lives in one constant */
const appName = await page.evaluate(() => APP_NAME);
const titleOk = await page.evaluate(() => document.title.startsWith(APP_NAME.toUpperCase()));
const signinName = await (async () => {
  await page.click('#jump .jump__b[data-jump="signin"]');
  await page.waitForTimeout(350);
  return page.locator('#app .h1').first().innerText();
})();
check('APP_NAME drives <title>', titleOk, appName);
check('APP_NAME drives the sign-in screen', signinName.trim() === appName.toUpperCase(), signinName.trim());

/* 4 — vote: drag right approves and awards points */
await page.click('#resetBtn');
await page.waitForTimeout(300);
await page.click('#jump .jump__b[data-jump="vote"]');
await page.waitForTimeout(450);
const before = await page.evaluate(() => {
  const s = pendingSubs()[0];
  return { id: s.id, ap: s.ap, re: s.re, pts: S.data.board[S.groupId].week[s.user] };
});
const box = await page.locator('.vcard[data-top]').boundingBox();
const cx = box.x + box.width / 2, cy = box.y + box.height / 2;
await page.mouse.move(cx, cy);
await page.mouse.down();
for (let i = 1; i <= 16; i++) { await page.mouse.move(cx + i * 13, cy); await page.waitForTimeout(14); }
await page.mouse.up();
await page.waitForTimeout(1600);
const after = await page.evaluate((id) => {
  const s = S.data.submissions.find(x => x.id === id);
  return { ap: s.ap, re: s.re, mv: s.mv, status: s.status, pts: S.data.board[S.groupId].week[s.user] };
}, before.id);
check('drag right registers an approval', after.mv === true && after.ap === before.ap + 1, `ap ${before.ap}→${after.ap}`);
check('points awarded on acceptance', after.pts > before.pts, `${before.pts}→${after.pts} pts`);
check('toast confirms the decision', (await page.locator('.toast__t').innerText()).startsWith('Accepted'));

/* 5 — undo reverses the vote */
await page.click('.toast__b');
await page.waitForTimeout(500);
const undone = await page.evaluate((id) => {
  const s = S.data.submissions.find(x => x.id === id);
  return { ap: s.ap, mv: s.mv, status: s.status, pts: S.data.board[S.groupId].week[s.user] };
}, before.id);
check('undo reverses the vote', undone.ap === before.ap && undone.mv === null, `ap back to ${undone.ap}`);
check('undo reverses the points', undone.pts === before.pts, `${undone.pts} pts`);

/* 6 — drag left rejects */
await page.click('#resetBtn');
await page.waitForTimeout(300);
await page.click('#jump .jump__b[data-jump="vote"]');
await page.waitForTimeout(450);
const box2 = await page.locator('.vcard[data-top]').boundingBox();
await page.mouse.move(box2.x + box2.width / 2, box2.y + box2.height / 2);
await page.mouse.down();
for (let i = 1; i <= 16; i++) { await page.mouse.move(box2.x + box2.width / 2 - i * 13, box2.y + box2.height / 2); await page.waitForTimeout(14); }
await page.mouse.up();
await page.waitForTimeout(1600);
const rejected = await page.evaluate(() => {
  const s = S.data.submissions.find(x => x.id === 's2');
  return { mv: s.mv, re: s.re };
});
check('drag left registers a rejection', rejected.mv === false && rejected.re === 3, `re=${rejected.re}`);

/* 7 — approve / reject buttons work too */
await page.click('#resetBtn');
await page.waitForTimeout(300);
await page.click('#jump .jump__b[data-jump="vote"]');
await page.waitForTimeout(450);
await page.click('#app button[data-act="vote"][data-v="1"]');
await page.waitForTimeout(1600);
const btnVote = await page.evaluate(() => {
  const s = S.data.submissions.find(x => x.id === 's1');
  return { mv: s.mv, ap: s.ap };
});
check('approve button works', btnVote.mv === true && btnVote.ap === 2, `ap=${btnVote.ap}`);

/* 8 — Prove it → camera → preview → post → pending stamp */
await page.click('#resetBtn');
await page.waitForTimeout(300);
await page.click('#jump .jump__b[data-jump="week"]');
await page.waitForTimeout(400);
await page.locator('#app .crow').first().click();
await page.waitForTimeout(400);
const challengeTitle = await page.locator('#app .h1').first().innerText();
await page.click('#app button[data-act="proveIt"]');
await page.waitForTimeout(500);
check('Prove it opens the camera', await page.locator('.cam').count() === 1);
await page.click('#app button[data-act="sampleShot"]');
await page.waitForTimeout(700);
check('camera → preview', await page.locator('#app .input#cap').count() === 1);
const previewTitle = await page.locator('#app .meta--ink').first().innerText();
check('preview names the right challenge', previewTitle.trim() === challengeTitle.trim().toUpperCase(), previewTitle.trim());
await page.fill('#cap', 'made it twice. edible.');
await page.click('#app button[data-act="postProof"]');
await page.waitForTimeout(2800);
check('upload completes to the PENDING stamp', (await page.locator('.stamp--pending').count()) >= 1);
check('pending stamp says Pending', (await page.locator('.stamp--pending').first().innerText()).trim() === 'Pending');
const posted = await page.evaluate(() => S.data.submissions.some(s => s.user === ME && s.week === 'cur' && s.status === 'pending' && s.cid === S.challengeId));
check('proof is queued as pending', posted);

/* 9 — dark mode toggles */
await page.click('#resetBtn');
await page.waitForTimeout(300);
await page.click('#themeBtn');
await page.waitForTimeout(400);
const theme = await page.evaluate(() => document.documentElement.dataset.theme);
const darkInk = await page.evaluate(() => getComputedStyle(document.querySelector('.device')).getPropertyValue('--ink').trim());
check('dark mode toggles', theme === 'dark', theme);
check('dark mode flips the ink token', darkInk.toUpperCase() === '#F5F5F2', darkInk);
await page.click('#themeBtn');
await page.waitForTimeout(300);

/* 10 — the feed lock blurs other people's proofs */
await page.click('#resetBtn');
await page.waitForTimeout(300);
await page.click('#jump .jump__b[data-jump="feed"]');
await page.waitForTimeout(400);
const unlocked = await page.locator('.fcell--locked').count();
await page.click('#feedLockBtn');
await page.waitForTimeout(400);
const locked = await page.locator('.fcell--locked').count();
check('feed lock blurs others\' proofs', unlocked === 0 && locked > 0, `${unlocked} → ${locked} locked cells`);

/* 11 — no browser-level errors anywhere */
check('zero console / page errors', errors.length === 0, errors.join(' | '));

console.log(`\n${ok.length} passed, ${fails.length} failed`);
if (fails.length) fails.forEach(f => console.log('  FAILED: ' + f));
await browser.close();
process.exit(fails.length ? 1 : 0);

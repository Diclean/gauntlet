/**
 * Build a contact sheet of every phone screenshot so the whole sweep can be
 * eyeballed at once. Output: shots/zz-all-screens.png
 */
import { chromium } from 'playwright';
import fs from 'node:fs';
import path from 'node:path';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const SHOTS = path.join(HERE, 'shots');
const files = fs.readdirSync(SHOTS)
  .filter(f => f.endsWith('.png') && !f.startsWith('zz-'))
  .sort((a, b) => {
    const pa = parseInt(a.slice(0, 2), 10), pb = parseInt(b.slice(0, 2), 10);
    return pa - pb || a.localeCompare(b);
  });

const html = `<body style="margin:0;background:#333;font:11px monospace;color:#eee">
<div style="display:flex;flex-wrap:wrap;gap:10px;padding:12px">
${files.map(f => `<div style="width:250px">
  <img src="${f}" style="width:250px;display:block;border:1px solid #666">
  <div style="padding:3px 0">${f.replace('.png', '')}</div>
</div>`).join('')}
</div></body>`;

fs.writeFileSync(path.join(SHOTS, '_all.html'), html);
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1320, height: 800 } });
await p.goto('file://' + path.join(SHOTS, '_all.html'));
await p.waitForTimeout(2000);
await p.screenshot({ path: path.join(SHOTS, 'zz-all-screens.png'), fullPage: true });
await b.close();
console.log('sheet built from', files.length, 'shots');

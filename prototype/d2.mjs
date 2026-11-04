import { chromium } from 'playwright';
const b = await chromium.launch();
const p = await b.newPage({ viewport:{width:1100,height:950} });
await p.goto('file://' + process.cwd() + '/index.html');
await p.waitForTimeout(700);
await p.click('#resetBtn'); await p.waitForTimeout(300);
await p.click('#jump .jump__b[data-jump="week"]'); await p.waitForTimeout(400);
await p.locator('#app .crow').first().click(); await p.waitForTimeout(400);
await p.click('#app button[data-act="proveIt"]'); await p.waitForTimeout(500);
await p.click('#app button[data-act="sampleShot"]'); await p.waitForTimeout(700);
await p.fill('#cap','made it twice. edible.');
await p.click('#app button[data-act="postProof"]');
for (const t of [1500, 2000, 2600, 3200, 4000]) {
  await p.waitForTimeout(t===1500?1500:600);
  const info = await p.evaluate(()=>{
    const els = Array.from(document.querySelectorAll('.stamp--pending'));
    return JSON.stringify(els.map(e=>({txt:e.innerText, textContent:e.textContent.trim(), op:getComputedStyle(e).opacity, anim:getComputedStyle(e).animationName, overlay:!!document.querySelector('#overlay .sheet')})));
  });
  console.log(t, info);
}
await b.close();

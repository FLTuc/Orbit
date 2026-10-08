// Test « chaos » de la version telephone : des centaines de gestes au hasard (boutons, champs,
// retour d'Android, temps qui passe, rechargements) comme un utilisateur presse ou distrait.
// Il ne doit jamais y avoir d'erreur JavaScript, et les donnees doivent rester valides.
// Lancement : node tests/pwa/monkey.cjs [nombre de gestes] [graine]
const { chromium, devices } = require('playwright');
const { start } = require('./server.cjs');

const STEPS = Number(process.argv[2]) || 600;
let seed = Number(process.argv[3]) || 20261008;
const rnd = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const WORDS = ['Appeler Paul', 'Payer la facture EDF !2', 'Réunion @14h', '<b>gras</b>', 'https://exemple.fr/a?b=1',
  '🚀🔥 emoji', 'x'.repeat(500), '', '   ', 'Répondre au mail de Julie', '"; alert(1); "', 'Ranger le bureau'];

let ok = 0, ko = 0;
function check(name, cond, detail = '') {
  if (cond) { ok++; console.log(`  OK    ${name}`); } else { ko++; console.log(`  ECHEC ${name} ${detail}`); }
}

(async () => {
  const srv = await start();
  const base = `http://localhost:${srv.address().port}/`;
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ ...devices['Pixel 7'], locale: 'fr-FR', acceptDownloads: true });
  await ctx.route((url) => !url.hostname.endsWith('localhost'), (r) => r.fulfill({ status: 200, contentType: 'text/html', body: 'ok' }));
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(`console: ${m.text()}`); });
  page.on('dialog', (d) => d.dismiss().catch(() => {}));
  await page.clock.install({ time: new Date(2026, 9, 5, 9, 0, 0) });
  await page.goto(base);
  await page.waitForSelector('#bigClock');
  console.log(`\n== ${STEPS} gestes au hasard (graine ${seed})`);

  const trace = [];
  for (let i = 0; i < STEPS; i++) {
    const r = rnd();
    try {
      if (r < 0.62) {
        // un bouton visible et actif, n'importe ou
        const buttons = await page.$$('button:visible:not([disabled]), [role=button]:visible, select:visible');
        const usable = [];
        for (const b of buttons) {
          const box = await b.boundingBox();
          if (box && box.width > 2 && box.height > 2) usable.push(b);
        }
        if (!usable.length) continue;
        const b = pick(usable);
        const label = ((await b.textContent()) || (await b.getAttribute('aria-label')) || '').trim().slice(0, 30);
        if (/Tout effacer|Exporter|Envoyer|Installer/.test(label)) continue;   // gestes testes ailleurs
        if ((await b.evaluate((e) => e.tagName)) === 'SELECT') {
          const vals = await b.$$eval('option', (o) => o.map((x) => x.value));
          if (vals.length) await b.selectOption(pick(vals));
          trace.push(`select ${label}`);
        } else {
          await b.click({ timeout: 800, force: true });
          trace.push(`clic ${label}`);
        }
      } else if (r < 0.77) {
        const fields = await page.$$('textarea:visible, input[type=text]:visible, input:not([type]):visible, input[type=search]:visible, input[inputmode=url]:visible');
        if (!fields.length) continue;
        const f = pick(fields);
        await f.fill(pick(WORDS), { timeout: 800 });
        if (rnd() < 0.5) await f.press('Enter', { timeout: 800 });
        trace.push('saisie');
      } else if (r < 0.85) {
        await page.goBack({ timeout: 1500 }).catch(() => {});
        if (!page.url().startsWith(base)) await page.goto(base);
        trace.push('retour');
      } else if (r < 0.95) {
        await page.clock.fastForward(pick(['00:05', '01:00', '05:00', '30:00', '55:00']));
        trace.push('temps');
      } else if (r < 0.98) {
        await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
        trace.push('retour dans l\'appli');
      } else {
        await page.reload();
        await page.waitForSelector('#bigClock', { timeout: 5000 });
        trace.push('rechargement');
      }
    } catch (e) {
      // un clic sur un element qui vient de disparaitre n'est pas un bug ; une erreur JS, si
      if (!/Timeout|detached|not attached|not visible|outside of the viewport|Target closed|intercepts pointer/i.test(e.message)) {
        errors.push(`geste ${i} (${trace[trace.length - 1] || '?'}): ${e.message.split('\n')[0]}`);
      }
    }
    if (errors.length) { console.log(`  apres le geste ${i} : ${trace.slice(-8).join(' > ')}`); break; }
  }
  const kinds = {};
  for (const t of trace) { const k = t.split(' ')[0]; kinds[k] = (kinds[k] || 0) + 1; }
  console.log(`  gestes faits : ${Object.entries(kinds).map(([k, n]) => `${k} ${n}`).join(', ')}`);
  const st0 = await page.evaluate(() => window.__orbit.state()).catch(() => null);
  if (st0) console.log(`  a la fin : ${st0.kanban.cards.length} carte(s), ${st0.notes.length} note(s), ${st0.reprises.length} reprise(s), ${st0.anchor.wins.length} victoire(s)`);
  await page.waitForTimeout(300);
  check(`aucune erreur JavaScript en ${trace.length} gestes`, errors.length === 0, errors.slice(0, 3).join(' | '));
  const st = await page.evaluate(() => (window.__orbit ? window.__orbit.state() : null)).catch(() => null);
  check('l\'appli repond encore et son etat est lisible', !!st && Array.isArray(st.kanban.cards) && Array.isArray(st.notes));
  const raw = await page.evaluate(() => localStorage.getItem('orbit.v1'));
  let parsed = null;
  try { parsed = JSON.parse(raw); } catch { /* verifie juste en dessous */ }
  check('donnees enregistrees valides (JSON relu)', !!parsed && parsed.version === 1);
  await page.reload();
  await page.waitForSelector('#bigClock');
  check('rechargement final sans erreur', errors.length === 0, errors.slice(0, 3).join(' | '));
  console.log(`\n${ok} verification(s) reussie(s), ${ko} echec(s)`);
  await browser.close();
  srv.close();
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });

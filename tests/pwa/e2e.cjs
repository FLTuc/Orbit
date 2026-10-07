// Test « en vrai » de la version telephone : Chromium au format telephone (Pixel 7), comme un
// utilisateur. Le temps est accelere (horloge simulee) pour les focus de 50 minutes.
// Lancement : node tests/pwa/e2e.cjs   (il faut le paquet « playwright » et Chromium)
const { chromium, devices } = require('playwright');
const fs = require('fs');
const path = require('path');
const os = require('os');
const zlib = require('zlib');
const { start, ROOT } = require('./server.cjs');

let ok = 0, ko = 0;
function check(name, cond, detail = '') {
  if (cond) { ok++; console.log(`  OK    ${name}`); } else { ko++; console.log(`  ECHEC ${name} ${detail}`); }
}
const section = (n) => console.log(`\n== ${n}`);

// zip comme Orbit PC (deflate, BOM)
function crc32(buf) { let c = ~0; for (const b of buf) { c ^= b; for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xEDB88320 : c >>> 1; } return ~c >>> 0; }
function pcZip(entries) {
  const parts = [], central = []; let off = 0;
  for (const [name, text] of Object.entries(entries)) {
    const raw = Buffer.from(text, 'utf8'), comp = zlib.deflateRawSync(raw), nb = Buffer.from(name);
    const lh = Buffer.alloc(30); lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE(8, 8);
    lh.writeUInt32LE(crc32(raw), 14); lh.writeUInt32LE(comp.length, 18); lh.writeUInt32LE(raw.length, 22); lh.writeUInt16LE(nb.length, 26);
    const ch = Buffer.alloc(46); ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6); ch.writeUInt16LE(8, 10);
    ch.writeUInt32LE(crc32(raw), 16); ch.writeUInt32LE(comp.length, 20); ch.writeUInt32LE(raw.length, 24); ch.writeUInt16LE(nb.length, 28); ch.writeUInt32LE(off, 42);
    parts.push(lh, nb, comp); central.push(ch, nb); off += 30 + nb.length + comp.length;
  }
  const cd = Buffer.concat(central), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(central.length / 2, 8); end.writeUInt16LE(central.length / 2, 10); end.writeUInt32LE(cd.length, 12); end.writeUInt32LE(off, 16);
  return Buffer.concat([...parts, cd, end]);
}

(async () => {
  const srv = await start();
  const base = `http://localhost:${srv.address().port}/`;
  const browser = await chromium.launch();
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'orbit-pwa-'));
  const errors = [];
  const ctx = await browser.newContext({ ...devices['Pixel 7'], locale: 'fr-FR', acceptDownloads: true });
  // les sites exterieurs (liens rouverts) sont simules : le test ne sort jamais sur internet
  await ctx.route((url) => !url.hostname.endsWith('localhost'), (r) => r.fulfill({ status: 200, contentType: 'text/html', body: '<title>page</title>ok' }));
  const page = await ctx.newPage();
  page.on('pageerror', (e) => errors.push(`pageerror: ${e.message}`));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(`console: ${m.text()}`); });
  const state = () => page.evaluate(() => window.__orbit.state());
  const visible = (sel) => page.locator(sel).isVisible();
  const tab = async (t) => { await page.click(`.tabbar [data-tab=${t}]`); await page.waitForTimeout(150); };
  try {
    await page.clock.install({ time: new Date(2026, 9, 5, 9, 0, 0) });   // un lundi matin
    await page.goto(base);
    await page.waitForSelector('#bigClock');

    section('Chargement et appli installable');
    const csp = await page.getAttribute('meta[http-equiv="Content-Security-Policy"]', 'content');
    check('politique de securite stricte (aucun script exterieur ni en ligne)', /script-src 'self'/.test(csp) && /object-src 'none'/.test(csp) && !/unsafe/.test(csp));
    check('aucun script dans la page elle-meme', (await page.locator('script:not([src])').count()) === 0);
    const man = await (await page.request.get(base + 'manifest.webmanifest')).json();
    check('manifeste : nom, plein ecran, partage, raccourci Brain Dump', man.display === 'standalone' && man.share_target && man.shortcuts.some((s) => /dump/.test(s.url)));
    let iconsOk = true;
    for (const ic of man.icons.filter((i) => i.type === 'image/png')) {
      const buf = await (await page.request.get(base + ic.src)).body();
      const w = buf.readUInt32BE(16), h = buf.readUInt32BE(20);
      if (`${w}x${h}` !== ic.sizes) iconsOk = false;
    }
    check('icones aux bonnes tailles (192, 512, maskable)', iconsOk);
    await page.waitForFunction(() => navigator.serviceWorker && navigator.serviceWorker.controller !== null || navigator.serviceWorker.ready, null, { timeout: 10000 });
    const sw = await page.evaluate(async () => !!(await navigator.serviceWorker.ready).active);
    check('service worker actif (hors ligne)', sw);
    await page.waitForFunction(() => /Bonjour/.test(document.getElementById('bubbleText').textContent), null, { timeout: 5000 }).catch(() => {});
    check('plan du matin propose a la 1re ouverture du jour', /Bonjour/.test(await page.textContent('#bubbleText')));
    await page.click('#bubbleButtons >> text=Plus tard');
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    check('rien ne deborde sur la largeur du telephone', overflow <= 1, `${overflow}px`);

    section('Tableaux');
    await tab('kanban');
    const firstInput = page.locator('.column').first().locator('input');
    await firstInput.fill('Rapport client !2');
    await firstInput.press('Enter');
    await firstInput.fill('<img src=x onerror="window.__pwned=1">');
    await firstInput.press('Enter');
    await page.waitForTimeout(200);
    let st = await state();
    check('cartes ajoutees (priorite 2 avec « !2 »)', st.kanban.cards.length === 2 && st.kanban.cards[0].prio === 2);
    check('texte piege affiche tel quel, jamais execute', (await page.locator('.card', { hasText: '<img src=x' }).count()) === 1 && !(await page.evaluate(() => window.__pwned)));
    await page.locator('.card', { hasText: 'Rapport client' }).click();
    await page.fill('#sheet input[placeholder^="＋ Sous-tâche"]', 'Vérifier les totaux');
    await page.press('#sheet input[placeholder^="＋ Sous-tâche"]', 'Enter');
    await page.fill('#sheet input[placeholder^="＋ Sous-tâche"]', 'Envoyer à Julie');
    await page.press('#sheet input[placeholder^="＋ Sous-tâche"]', 'Enter');
    await page.locator('#sheet .check-row input').first().check();
    await page.click('#sheet >> text=🎯 Lier au focus');
    st = await state();
    const rc = st.kanban.cards.find((c) => c.text === 'Rapport client');
    check('sous-taches et lien au focus', rc.checks.length === 2 && rc.checks[0].done && st.kanban.focus.includes(rc.id));

    section('Focus de 50 minutes (temps accelere)');
    await tab('home');
    await page.click('text=🚀 Lancer un focus');
    st = await state();
    check('focus lance, la carte passe « En cours »', st.timer.state === 'Focus' && st.kanban.cards.find((c) => c.id === rc.id).col === st.kanban.boards[0].columns[1].id);
    check('bouton ✋ visible pendant le focus', await visible('#ctxBadge'));
    await page.clock.fastForward('20:00');
    check('le chrono tourne', /^29:|^30:/.test(await page.textContent('#bigClock')), await page.textContent('#bigClock'));

    section("✋ Je m'interromps");
    await page.click('#ctxBadge');
    await page.fill('#sheet input[inputmode=url]', 'sharepoint.com/budget');
    const nextBox = page.locator('#sheet textarea').nth(1);
    check('prochaine etape proposee (sous-tache pas cochee)', (await nextBox.inputValue()) === 'Envoyer à Julie');
    await page.locator('#sheet textarea').first().fill('je relisais le budget');
    await page.click('#sheet >> text=✓ Enregistrer');
    st = await state();
    check('reprise enregistree, focus en pause', st.reprises.length === 1 && st.reprises[0].windows[0].url === 'https://sharepoint.com/budget' && st.timer.paused);
    await page.clock.fastForward('10:00');
    check('pendant l\'interruption, le temps ne compte pas', /^29:|^30:/.test(await page.textContent('#bigClock')));
    await page.locator('#orbitBot').click({ force: true });   // (Orbit flotte en permanence)
    check('au retour : « Où j\'en étais ? » avec la prochaine etape', /Prochaine étape : Envoyer à Julie/.test(await page.textContent('#bubbleText')));
    const [popup] = await Promise.all([ctx.waitForEvent('page'), page.click('#bubbleButtons >> text=▶ Reprendre')]);
    await popup.waitForLoadState().catch(() => {});
    check('reprendre : la page est rouverte', popup.url().startsWith('https://sharepoint.com/budget'), popup.url());
    await popup.close();
    st = await state();
    check('reprendre : le focus repart, reprise terminee, victoire', !st.timer.paused && st.reprises[0].status === 'done' && st.anchor.wins.some((w) => w.kind === 'reprise'));
    await page.clock.fastForward('31:00');
    await page.waitForTimeout(300);
    st = await state();
    check('fin du focus : question de pause, 🍅 sur la carte', st.timer.state === 'AwaitBreak' && st.kanban.cards.find((c) => c.id === rc.id).pomos === 1);
    check('la bulle propose la pause et « C\'est fait »', /pause/.test(await page.textContent('#bubbleButtons')) && /C'est fait/.test(await page.textContent('#bubbleButtons')));
    await page.click('#bubbleButtons >> text=☕ Je prends ma pause');
    st = await state();
    check('pause lancee', st.timer.state === 'Break');

    section('Partager une page vers Orbit (depuis Chrome)');
    await page.goto(base + '?share_title=Article%20utile&share_text=A%20lire&share_url=https%3A%2F%2Fexemple.fr%2Farticle');
    await page.waitForSelector('#sheet:not(.hidden)');
    check('le lien partage est prerempli', (await page.inputValue('#sheet input[inputmode=url]')) === 'https://exemple.fr/article');
    await page.click('#sheet >> text=📥 Plutôt dans le Brain Dump');
    st = await state();
    check('… et peut aller dans le Brain Dump', st.anchor.dump.length === 1 && /exemple\.fr/.test(st.anchor.dump[0].text));

    section('📥 Brain Dump et tri a froid');
    for (const t of ['Payer la facture EDF', 'Idée cadeau Léa', 'Ranger le garage']) {
      await page.click('#dumpFab');
      await page.fill('#sheet textarea', t);
      await page.press('#sheet textarea', 'Enter');
    }
    st = await state();
    check('capture en 2 gestes (bouton 📥, Entrée)', st.anchor.dump.length === 4);
    check('pastille du Dump sur l\'onglet', (await page.textContent('#dumpCount')) === '4');
    await tab('dump');
    await page.click('#sortStart');
    const card = page.locator('.sort-card');
    const box = await card.boundingBox();
    // 1re idee : glissee du doigt vers la droite -> action
    const cdp = await ctx.newCDPSession(page);
    const x = box.x + box.width / 2, y = box.y + box.height / 2;
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
    for (let i = 1; i <= 6; i++) await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: x + i * 30, y }] });
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
    await page.waitForTimeout(250);
    const trace = [(await state()).anchor.dump.length];
    for (const label of ['📦 Archiver', '⚡ À débloquer', '🗂 Carte (tableau)']) {
      await page.click(`#focusMode button:has-text("${label}")`);
      trace.push((await state()).anchor.dump.length);
    }
    console.log(`  (reste dans le bac apres chaque geste : ${trace.join(' -> ')})`);
    st = await state();
    check('tri : glisser = action, puis archive, deblocage, carte', st.anchor.dump.length === 0 && st.anchor.tasks.filter((t) => t.status === 'todo').length === 2 && st.anchor.tasks.some((t) => t.status === 'archived') && st.kanban.cards.some((c) => /Ranger le garage/.test(c.text)) && st.anchor.unstick);
    check('bac trie : bouton pour se debloquer', await page.locator('#focusMode >> text=⚡ Me débloquer').isVisible());

    section('⚡ Unstick Me (une seule chose a la fois)');
    await page.click('#focusMode >> text=⚡ Me débloquer');
    check('une seule etape affichee', (await page.locator('.fm-step').count()) === 1 && /Étape 1 sur/.test(await page.textContent('#focusMode')));
    await page.click('#focusMode >> text=▶ Je commence');
    await page.clock.fastForward('03:00');
    await page.waitForTimeout(200);
    check('minuteur doux : fini sans alarme, on peut continuer', /✓/.test(await page.textContent('#runnerText')));
    await page.click('#focusMode >> text=🔪 Plus petit');
    st = await state();
    const n0 = st.anchor.unstick.steps.length;
    check('« plus petit » ajoute une micro-etape de preparation', /Prépare-toi juste/.test(st.anchor.unstick.steps[0].content));
    for (let i = 0; i < n0; i++) await page.click("#focusMode >> text=✅ C'est fait !");
    check('fin : « Tu es lancé(e) » et victoire', /Tu es lancé/.test(await page.textContent('#focusMode')) && (await state()).anchor.wins.some((w) => w.kind === 'unstick'));
    await page.click('#focusMode >> text=Fermer');

    section('🚨 S.O.S depuis n\'importe ou');
    await tab('kanban');
    await page.click('#sosBtn');
    await page.fill('#focusMode textarea', 'Répondre au mail de Julie');
    await page.click('#focusMode >> text=⚡ Découper');
    check('S.O.S : decoupage immediat (messagerie)', /messagerie/.test(await page.textContent('.fm-step')));
    await page.click('#focusMode >> text=✖ Plus tard');
    await tab('home');
    check('la seance reste reprenable depuis l\'accueil', await visible('#homeUnstick'));

    section('📋 DopaList et journal des victoires');
    await tab('dopa');
    await page.fill('#dopaInput', 'Prendre mes médicaments');
    await page.selectOption('#dopaRepeat', 'daily');
    await page.click('#dopaForm button[type=submit]');
    await page.locator('.dopa', { hasText: 'Prendre mes médicaments' }).click();
    st = await state();
    check('routine cochee : victoire du jour', st.anchor.tasks.find((t) => t.title === 'Prendre mes médicaments').lastDone === '2026-10-05');
    check('aucun compteur « en retard » dans la DopaList', !/retard/i.test(await page.textContent('#view-dopa')));
    await page.click('#openJournal');
    const journal = await page.textContent('#view-journal');
    check('journal : victoires du jour (focus, reprise, deblocage, routine)', /Prendre mes médicaments/.test(journal) && /Focus de 50 min/.test(journal) && /Débloqué/.test(journal) && /victoires/.test(journal));

    section('🔍 Recherche');
    await page.click('#openSearch');
    await page.fill('#searchInput', 'facture edf');
    check('recherche partout (accents et majuscules ignores)', /Payer la facture EDF/.test(await page.textContent('#searchResults')));

    section('💻 Echange avec Orbit PC');
    await page.goto(base);
    await page.click('.tabbar [data-tab=more]');
    await page.click('[data-go=transfer]');
    const zip = path.join(tmp, 'Orbit-transfert.zip');
    fs.writeFileSync(zip, pcZip({
      'Orbit/orbit.ps1': '# programme',
      'Orbit/donnees/orbit-export.json': '{}',
      'Orbit/donnees/kanban.json': '\uFEFF' + JSON.stringify({ current: 'b1', boards: [{ id: 'b1', name: 'Projet PC', columns: [{ id: 'c1', name: 'À faire', done: false }, { id: 'c2', name: 'Terminé', done: true }] }], cards: [{ id: 'k1', text: 'Carte venue du PC', prio: 3, board: 'b1', col: 'c1' }], focus: [] }),
      'Orbit/donnees/notes.json': JSON.stringify([{ id: 'n1', text: 'Note du PC', updated: '2026-10-01T10:00:00' }]),
    }));
    await page.setInputFiles('#importZip', zip);
    await page.click('#sheet button:has-text("Remplacer")');
    await page.waitForFunction(() => window.__orbit.state().kanban.boards[0].name === 'Projet PC', null, { timeout: 5000 }).catch(() => {});
    st = await state();
    check('zip d\'Orbit PC importe (tableaux, notes)', st.kanban.boards[0].name === 'Projet PC' && st.notes[0].text === 'Note du PC');
    check('DopaList du telephone gardee (absente du zip)', st.anchor.tasks.length > 0);
    await page.click('#undoImport');
    await page.waitForTimeout(200);
    st = await state();
    check('annuler l\'import', st.kanban.boards[0].name === 'Mon tableau');
    const [dl] = await Promise.all([page.waitForEvent('download'), page.click('#exportZip')]);
    const out = path.join(tmp, 'export.zip');
    await dl.saveAs(out);
    const buf = fs.readFileSync(out);
    const names = [];
    for (let i = 0; i < buf.length - 4; i++) if (buf.readUInt32LE(i) === 0x02014b50) { const nl = buf.readUInt16LE(i + 28); names.push(buf.slice(i + 46, i + 46 + nl).toString()); }
    check('export pour le PC : dossier « donnees » au format d\'Orbit PC', ['donnees/orbit-export.json', 'donnees/kanban.json', 'donnees/notes.json', 'donnees/reprises.json', 'donnees/lifeanchor.json'].every((n) => names.includes(n)), names.join(','));

    section('Hors ligne et donnees gardees');
    await ctx.setOffline(true);
    await page.reload();
    await page.waitForSelector('#bigClock');
    st = await state();
    check('sans reseau : l\'appli s\'ouvre, les donnees sont la', st.kanban.cards.length >= 2 && st.anchor.wins.length >= 3);
    await page.click('.tabbar [data-tab=more]');
    await page.click('[data-go=notes]');
    await page.click('#noteNew');
    await page.fill('#sheet textarea', 'Note écrite hors ligne');
    await page.click('#sheet >> text=✓ OK');
    await page.reload();
    check('note ecrite hors ligne gardee', (await state()).notes.some((n) => n.text === 'Note écrite hors ligne'));
    await ctx.setOffline(false);

    section('Bouton retour d\'Android');
    await page.click('#dumpFab');
    await page.goBack();
    check('retour : ferme la fenetre sans quitter l\'appli', !(await visible('#sheet')) && page.url().startsWith(base));

    section('Mode sombre');
    await page.emulateMedia({ colorScheme: 'dark' });
    const bg = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    check('couleurs sombres', bg === 'rgb(20, 17, 43)', bg);
    await page.emulateMedia({ colorScheme: 'light' });

    section('Erreurs');
    check('aucune erreur JavaScript pendant tout le parcours', errors.length === 0, errors.slice(0, 5).join(' | '));
    await page.screenshot({ path: path.join(tmp, 'fin.png') });
  } catch (e) {
    check('parcours sans erreur', false, `${e.message.split('\n')[0]}`);
    try { await page.screenshot({ path: path.join(os.tmpdir(), 'orbit-pwa-echec.png') }); console.log('  capture : ' + path.join(os.tmpdir(), 'orbit-pwa-echec.png')); } catch { /* */ }
  }
  await browser.close();
  srv.close();
  console.log(`\n${ok} verification(s) reussie(s), ${ko} echec(s)`);
  process.exit(ko ? 1 : 0);
})();

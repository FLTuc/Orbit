// Tests de la logique de la version telephone (store.js, zip.js), sans navigateur.
// Lancement : node tests/pwa/unit.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as S from '../../pwa/js/store.js';
import { readZip, writeZip, crc32, MAX_ENTRY } from '../../pwa/js/zip.js';
import zlib from 'node:zlib';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const rules = JSON.parse(fs.readFileSync(path.join(ROOT, 'unstick', 'rules.json'), 'utf8'));
let ok = 0, ko = 0;
function check(name, cond, detail = '') {
  if (cond) { ok++; console.log(`  OK    ${name}`); } else { ko++; console.log(`  ECHEC ${name} ${detail}`); }
}
function section(n) { console.log(`\n== ${n}`); }

section('Petites fonctions');
check('adresse sans https:// completee', S.safeUrl('docs.google.com/x') === 'https://docs.google.com/x');
check('adresses dangereuses refusees', !S.safeUrl('javascript:alert(1)') && !S.safeUrl('file:///etc/passwd') && !S.safeUrl('https://a.fr/"><script>') && !S.safeUrl('data:text/html,x') && !S.safeUrl(''));
check('lien trouve dans un texte partage', S.findUrl('Regarde ça https://exemple.fr/page?id=3 super') === 'https://exemple.fr/page?id=3');
check('raccourcis !2 et @14h', (() => { const p = S.parseShortcuts('Appeler Paul !2 @14h', new Date(2026, 0, 5, 10)); return p.text === 'Appeler Paul' && p.prio === 2 && p.remindAt === '2026-01-05T14:00:00'; })());
check('@14h deja passe : demain', S.parseShortcuts('x @9h', new Date(2026, 0, 5, 10)).remindAt === '2026-01-06T09:00:00');
check('raccourcis invalides laisses tels quels', S.parseShortcuts('RDV @25h !11').text === 'RDV @25h !11');
check('recherche : accents et majuscules ignores', S.searchKey('ÉCOLE Été Ça Œuvre') === 'ecole ete ca oeuvre');
check('coupe sans casser un emoji', !/[\uD800-\uDBFF]$/.test(S.shortText('a'.repeat(10) + '🚀'.repeat(10), 12).replace('…', '')));
check('texte nettoye (controles, moities d\'emoji)', S.cleanText('a\u0007b\uD83Dc​d') === 'abcd');
check('formatAgo', S.formatAgo(S.isoLocal(new Date(Date.now() - 25 * 60000))) === 'il y a 25 min');
check('permutation : chaque element une seule fois', (() => { const p = S.permutation(1000, 42); return new Set(p).size === 1000; })());
const stats = { jokeSeed: 0, jokePos: 0 };
const seen = new Set();
for (let i = 0; i < 50; i++) seen.add(S.nextItem(Array.from({ length: 50 }, (_, k) => k), stats, 'jokeSeed', 'jokePos'));
check('blagues : aucune repetition avant d\'avoir tout vu', seen.size === 50);

section('Tableaux et focus');
let s = S.defaultState();
const b = S.currentBoard(s);
const c1 = S.addCard(s, 'Rapport client !2');
const c2 = S.addCard(s, 'Mails');
check('carte ajoutee dans la 1re colonne avec sa priorite', c1.col === b.columns[0].id && c1.prio === 2);
check('carte vide refusee', S.addCard(s, '   ') === null);
S.setCardFocus(s, c1.id, true);
S.startFocus(s, 1000);
check('focus : la carte liee passe dans « En cours »', S.findCard(s, c1.id).col === b.columns[1].id);
check('pause / reprise du chrono', (() => { S.pauseTimer(s, 61000); const left = S.timeLeft(s); S.resumeTimer(s, 500000); return left === 50 * 60000 - 60000 && S.timeLeft(s, 500000) === left; })());
const ev = S.tick(s, s.timer.endsAt + 1);
check('fin du focus : 🍅 et minutes sur la carte, stats', ev === 'focusEnded' && S.findCard(s, c1.id).pomos === 1 && S.findCard(s, c1.id).focusMin === 50 && s.stats.focus === 1 && s.timer.state === 'AwaitBreak');
S.startBreak(s, 0);
check('fin de la pause', S.tick(s, 11 * 60000) === 'breakEnded' && s.timer.state === 'AwaitFocus');
S.setCardDone(s, c1.id, true);
check('carte terminee : colonne Terminé, retiree du focus', S.findCard(s, c1.id).done && !s.kanban.focus.includes(c1.id));
s.kanban.cards.find((t) => t.id === c2.id).due = S.dayString();
check('plan du matin : la carte du jour en premier, avec la raison', S.planCards(s, 3)[0].card.id === c2.id && /aujourd/.test(S.planCards(s, 3)[0].why));
S.startFocus(s);
check('focus sans carte : la plus urgente est proposee', s.kanban.focus.includes(c2.id));

section('Notes et reprises');
const n = S.addNote(s, 'Appeler le garage\nPour le contrôle technique');
check('note ajoutee', n && s.notes.length === 1);
const card = S.noteToCard(s, n.id);
check('note -> carte (1re ligne = titre)', card.text === 'Appeler le garage' && card.desc.includes('contrôle') && s.notes.length === 0);
s.timer = { state: 'Focus', endsAt: Date.now() + 10 * 60000, paused: false, remainingMs: 0, sessionMin: 50 };
const r = S.newReprise(s, { url: 'sharepoint.com/budget', doing: 'vérifier les totaux', next: 'corriger F12' });
S.addReprise(s, r);
check('reprise : lien complete, carte du focus, rappel', r.windows[0].url === 'https://sharepoint.com/budget' && r.wasFocus && r.remindAt > S.isoLocal());
check('la plus recente est proposee', S.latestOpenReprise(s, 12).id === r.id);
check('pas de rappel avant l\'heure, puis oui', !S.dueReprise(s) && S.dueReprise(s, new Date(Date.now() + 31 * 60000)).id === r.id);
S.completeReprise(s, r.id);
check('reprise terminee', !S.latestOpenReprise(s));
const found = S.searchAll(s, 'totaux');
check('recherche : reprises trouvees', found.reprises.length === 1);

section('Brain Dump, DopaList, journal des victoires');
s = S.defaultState();
const d1 = S.dumpAdd(s, 'Prendre RDV dentiste');
const d2 = S.dumpAdd(s, 'Idée de cadeau pour Léa');
S.dumpAdd(s, 'Payer la facture EDF');
check('capture sans tri', s.anchor.dump.length === 3 && !S.dumpAdd(s, '   '));
S.dumpSort(s, d1.id, 'dopa', rules);
S.dumpSort(s, d2.id, 'archive', rules);
const third = s.anchor.dump[0];
S.dumpSort(s, third.id, 'unstick', rules);
check('tri a froid : action, archive, deblocage', s.anchor.dump.length === 0 && s.anchor.tasks.filter((t) => t.status === 'todo').length === 2 && s.anchor.tasks.some((t) => t.status === 'archived') && s.anchor.unstick && /application|site/.test(s.anchor.unstick.steps[0].content));
const rt = S.dopaAdd(s, 'Prendre mes médicaments', 'daily');
const mon = new Date(2026, 9, 5, 9);   // un lundi
check('routine du jour a faire', S.dopaView(s, mon).routines.some((x) => x.task.id === rt.id && x.due));
S.dopaComplete(s, rt.id, mon);
check('routine faite : victoire, plus « a faire » aujourd\'hui', S.winsOfDay(s, mon).length === 1 && !S.routineDue(rt, mon));
check('et de nouveau a faire demain', S.routineDue(rt, new Date(2026, 9, 6, 9)));
check('pas deux victoires pour la meme routine le meme jour', S.dopaComplete(s, rt.id, mon) === null);
const we = S.dopaAdd(s, 'Point équipe', 'weekdays');
check('routine « en semaine » : pas le samedi', !S.routineDue(we, new Date(2026, 9, 10, 9)) && S.routineDue(we, mon));
S.dopaUndo(s, rt.id, mon);
check('annuler : la victoire disparait', S.winsOfDay(s, mon).length === 0 && S.routineDue(rt, mon));
S.dopaComplete(s, rt.id, mon);
S.dopaComplete(s, rt.id, new Date(2026, 9, 4, 9));
check('serie de jours avec une victoire', S.winStreak(s, mon) === 2);

section('Unstick Me : decoupage local');
const steps = S.decompose('Répondre au mail de Julie', rules);
check('3 a 5 micro-etapes', steps.length >= 3 && steps.length <= 5);
check('mail : « Ouvre ta messagerie »', /messagerie/.test(steps[0]));
check('compte-rendu = ecrire (pas la banque)', /fichier/.test(S.decompose('Faire mon compte-rendu', rules)[0]));
check('tache inconnue : etapes generiques avec la tache', S.decompose('Réparer le vélo', rules)[0].includes('Réparer le vélo'));
check('tache vide : rien', S.decompose('   ', rules).length === 0);
const expected = JSON.parse(fs.readFileSync(path.join(ROOT, 'tests', 'fixtures', 'unstick-expected.json'), 'utf8'));
check('decoupage conforme au fichier de reference commun avec le PC', Object.entries(expected).every(([t, steps]) => JSON.stringify(S.decompose(t, rules)) === JSON.stringify(steps)));
S.startUnstick(s, 'Ranger le bureau', rules);
let res = '';
for (let i = 0; i < 10 && res !== 'finished'; i++) res = S.unstickStepDone(s);
check('toutes les etapes faites : victoire « Débloqué »', res === 'finished' && !s.anchor.unstick && s.anchor.wins.some((w) => /Débloqué : Ranger le bureau/.test(w.title)));
const task = S.dopaAdd(s, 'Payer la facture');
S.startUnstick(s, task.title, rules, task.id);
for (let i = 0; i < 10 && s.anchor.unstick; i++) S.unstickStepDone(s);
check('debloquer une action de la DopaList la termine', s.anchor.tasks.find((t) => t.id === task.id).status === 'completed');

section('Echange avec Orbit PC (zip)');
s = S.defaultState();
S.addCard(s, 'Carte du téléphone 🚀');
S.addNote(s, 'Note');
S.dopaAdd(s, 'Méditer', 'daily');
S.dumpAdd(s, 'Idée');
const files = S.toDesktopFiles(s);
const zipped = writeZip(Object.fromEntries(Object.entries(files).map(([k, v]) => [`Orbit/donnees/${k}`, v])));
const back = await readZip(zipped, Object.keys(files));
check('zip ecrit puis relu a l\'identique', Object.keys(files).every((k) => back[k] === files[k]));
const s2 = S.fromDesktopFiles(S.defaultState(), back);
check('donnees reprises (cartes, notes, DopaList, dump)', s2.kanban.cards[0].text === 'Carte du téléphone 🚀' && s2.notes.length === 1 && s2.anchor.tasks[0].isRoutine && s2.anchor.dump.length === 1);
// un zip d'Orbit PC : compresse (deflate) avec BOM, comme ZipFile.CreateFromDirectory
function deflateZip(entries) {
  const parts = [], central = [];
  let off = 0;
  const enc = new TextEncoder();
  for (const [name, text] of Object.entries(entries)) {
    const raw = Buffer.from(text, 'utf8');
    const comp = zlib.deflateRawSync(raw);
    const nb = enc.encode(name);
    const lh = Buffer.alloc(30); lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE(8, 8);
    lh.writeUInt32LE(crc32(raw), 14); lh.writeUInt32LE(comp.length, 18); lh.writeUInt32LE(raw.length, 22); lh.writeUInt16LE(nb.length, 26);
    const ch = Buffer.alloc(46); ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6); ch.writeUInt16LE(8, 10);
    ch.writeUInt32LE(crc32(raw), 16); ch.writeUInt32LE(comp.length, 20); ch.writeUInt32LE(raw.length, 24); ch.writeUInt16LE(nb.length, 28); ch.writeUInt32LE(off, 42);
    parts.push(lh, Buffer.from(nb), comp); central.push(ch, Buffer.from(nb));
    off += 30 + nb.length + comp.length;
  }
  const cd = Buffer.concat(central);
  const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(Object.keys(entries).length, 8); end.writeUInt16LE(Object.keys(entries).length, 10);
  end.writeUInt32LE(cd.length, 12); end.writeUInt32LE(off, 16);
  return new Uint8Array(Buffer.concat([...parts, cd, end]));
}
const pcKanban = '﻿' + JSON.stringify({ current: 'b1', boards: [{ id: 'b1', name: 'Projet', columns: [{ id: 'c1', name: 'À faire', done: false }, { id: 'c2', name: 'Terminé', done: true }] }],
  cards: [{ id: 'k1', text: 'Budget T3', prio: 3, board: 'b1', col: 'c1', checks: [{ text: 'totaux', done: true }], repeat: 'weekly' }], focus: ['k1'], upcoming: [], templates: [{ name: 'Modèle', text: 'x', prio: 4 }] });
const pcZip = deflateZip({ 'Orbit/orbit.ps1': '# programme', 'Orbit/donnees/kanban.json': pcKanban, 'Orbit/donnees/settings.json': '{}', 'Orbit/donnees/orbit-export.json': '{}' });
const pcFiles = await readZip(pcZip, ['kanban.json', 'notes.json', 'reprises.json', 'lifeanchor.json']);
const s3 = S.fromDesktopFiles(S.defaultState(), pcFiles);
check('zip d\'Orbit PC (compresse, avec BOM) : tableaux recuperes', s3.kanban.boards[0].name === 'Projet' && s3.kanban.cards[0].checks[0].done && s3.kanban.focus[0] === 'k1' && s3.kanban.templates.length === 1);
check('fichiers absents du zip : le telephone garde les siens', s3.notes.length === 0 && Object.keys(pcFiles).length === 1);

section('Securite : fichiers trafiques et zip pieges');
const evil = { boards: [{ id: "b'; alert(1)//", name: '<img src=x onerror=alert(1)>', columns: [{ id: 'c1', name: 'x' }] }, { id: 'ok', name: 'Ok', columns: [{ id: 'c9', name: 'A' }] }],
  cards: [{ id: '<script>', text: '<b>gras</b>', board: 'ok', col: 'c9', prio: 999, due: 'pas une date', checks: 'pas une liste' }], focus: ['<x>'] };
const k = S.sanitizeKanban(evil);
check('identifiant pirate : tableau ignore', k.boards.length === 1 && k.boards[0].id === 'ok');
check('carte : identifiant remplace, priorite bornee, date ignoree', S.SAFE_ID.test(k.cards[0].id) && k.cards[0].prio === 10 && k.cards[0].due === '' && Array.isArray(k.cards[0].checks));
check('le texte reste du texte (affiche tel quel, jamais interprete)', k.cards[0].text === '<b>gras</b>' && k.focus.length === 0);
const rep = S.sanitizeReprises([{ id: 'x', windows: [{ url: 'javascript:alert(1)', app: 'a";b', title: 't' }, { url: 'https://ok.fr/"onclick' }] }]);
check('reprise : adresses javascript: et avec guillemet effacees', rep[0].windows.every((w) => !w.url) && rep[0].windows[0].app === 'ab');
const st = S.normalizeState({ settings: { rhythm: 'x', customFocus: -5, ctxRemindMin: 1e9, sounds: 'oui' }, timer: { state: 'Hack' }, notes: 'x', anchor: { dump: [{ text: 'a' }, null, 5], unstick: { steps: [] } } });
check('etat trafique : valeurs par defaut ou bornees', st.settings.rhythm === '50/10' && st.settings.customFocus === 1 && st.settings.ctxRemindMin === 480 && st.settings.sounds === true && st.timer.state === 'Idle' && st.notes.length === 0 && st.anchor.dump.length === 1 && st.anchor.unstick === null);
check('limites : 5000 notes -> 2000 gardees', S.sanitizeNotes(Array.from({ length: 5000 }, (_, i) => ({ text: `n${i}` }))).length === 2000);
let threw = '';
try { await readZip(new Uint8Array([1, 2, 3, 4]), ['kanban.json']); } catch (e) { threw = e.message; }
check('fichier qui n\'est pas un zip : refuse proprement', /zip/.test(threw));
// bombe zip : 50 Mo de zeros compresses en quelques dizaines de Ko
const bomb = deflateZip({ 'donnees/kanban.json': ' '.repeat(MAX_ENTRY + 1000) });
threw = '';
try { await readZip(bomb, ['kanban.json']); } catch (e) { threw = e.message; }
check('bombe zip refusee (fichier trop gros une fois decompresse)', /trop gros/.test(threw), threw);
threw = '';
try { await readZip(bomb.slice(0, bomb.length - 30), ['kanban.json']); } catch (e) { threw = e.message; }
check('zip tronque : refuse proprement', threw.length > 0);
// au hasard : rien ne plante, rien de dangereux ne passe
let crash = 0, leak = 0;
const alpha = ['a', '/', ':', '.', '"', "'", '<', '>', ' ', 'http', 'https://', 'javascript:', '\u0000', '\uD83D', 'é', '%', '#', '?', '\\', '`'];
for (let i = 0; i < 3000; i++) {
  let x = '';
  for (let j = Math.floor(Math.random() * 20); j >= 0; j--) x += alpha[Math.floor(Math.random() * alpha.length)];
  try {
    const u = S.safeUrl(x);
    if (u && !/^https?:\/\/[^\s"'<>`^{}|\\]+$/.test(u)) leak++;
    S.normalizeState({ kanban: { boards: [{ id: x, columns: [{ id: x }] }], cards: [{ id: x, text: x, board: x, col: x }] }, notes: [{ id: x, text: x }], reprises: [{ id: x, windows: [{ url: x }] }], anchor: { dump: [{ text: x }], tasks: [{ title: x, steps: [{ content: x }] }] } });
    S.decompose(x, rules); S.searchAll(S.defaultState(), x); S.parseShortcuts(x);
  } catch { crash++; }
}
check('3000 donnees au hasard : aucun plantage, aucune fuite', crash === 0 && leak === 0, `${crash} plantage(s), ${leak} fuite(s)`);

console.log(`\n${ok} verification(s) reussie(s), ${ko} echec(s)`);
process.exit(ko ? 1 : 0);

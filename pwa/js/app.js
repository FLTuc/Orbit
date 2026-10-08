// Orbit (telephone) : l'interface. Toute la logique et les verifications sont dans store.js.
// Regle de securite : aucun texte n'est jamais interprete comme du HTML (pas d'innerHTML) :
// tout passe par h(), qui ne pose que du texte.
'use strict';
import * as St from './store.js';
import { readZip, writeZip } from './zip.js';
import * as Ob from './orbit.js';

const $ = (id) => document.getElementById(id);
const VIEWS = ['home', 'journal', 'kanban', 'more', 'notes', 'reprises', 'search', 'settings', 'transfer'];
const TAB_OF = { home: 'home', kanban: 'kanban', notes: 'notes', reprises: 'reprises' };
const WIN_ICON = { task: '✅', routine: '🔁', unstick: '⚡', focus: '🍅', card: '🗂', reprise: '↩' };

// --- petit outil : construire un element sans jamais passer par du HTML ------------------
function h(tag, props, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === 'class') el.className = v;
    else if (k === 'text') el.textContent = v;
    else if (k === 'value') el.value = v;
    else if (k === 'checked') el.checked = !!v;
    else if (k.startsWith('on')) { if (typeof v === 'function') el.addEventListener(k.slice(2), v); }   // jamais de code en texte
    else if ((k === 'href' || k === 'src') && !String(v).startsWith('blob:')) continue;              // seulement nos fichiers generes
    else el.setAttribute(k, v === true ? '' : String(v));
  }
  for (const c of kids.flat(Infinity)) {
    if (c === null || c === undefined || c === false) continue;
    el.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return el;
}
const btn = (label, onclick, cls = 'btn', extra = {}) => h('button', { type: 'button', class: cls, onclick, ...extra }, label);
function clear(el) { while (el.firstChild) el.firstChild.remove(); return el; }

// --- etat, enregistrement ---------------------------------------------------------------
function load() {
  try { const raw = localStorage.getItem(St.STORAGE_KEY); return St.normalizeState(raw ? JSON.parse(raw) : null); }
  catch { return St.defaultState(); }
}
let S = load();
let persistAsked = false;
function save() {
  try {
    localStorage.setItem(St.STORAGE_KEY, JSON.stringify(S));
    if (!persistAsked && navigator.storage && navigator.storage.persist) { persistAsked = true; navigator.storage.persist().catch(() => {}); }
  } catch { toast("⚠ La mémoire du téléphone est pleine : je n'ai pas pu enregistrer."); }
}
function commit() { save(); render(); }
// l'ancien Brain Dump et l'ancienne DopaList ont ete retires : rien n'est perdu
let migrated = St.migrateAnchor(S);
if (migrated) save();
// une autre fenetre d'Orbit a modifie les donnees
window.addEventListener('storage', (e) => { if (e.key === St.STORAGE_KEY) { S = load(); render(); } });

// --- donnees chargees a la demande (blagues, culture G, decoupeur) -----------------------
const cache = {};
async function data(name) {
  if (!cache[name]) {
    cache[name] = fetch(`data/${name}.json`).then((r) => (r.ok ? r.json() : [])).catch(() => []);
  }
  return cache[name];
}
let RULES = null;
data('unstick').then((r) => { RULES = r; });

// --- navigation (le bouton retour d'Android ferme d'abord les fenetres) ---------------------
// Une seule entree d'historique sert a toutes les fenetres : fermer une fenetre et en ouvrir
// une autre aussitot (ex. « Renommer » depuis un menu) reutilise la meme entree.
let view = 'home';
let modal = null;        // 'sheet' | 'focus'
let modalEntry = false;  // une entree d'historique « fenetre ouverte » existe
let ignorePop = false;
function go(v, push = true) {
  if (!VIEWS.includes(v)) v = 'home';
  if (modal) { hideModal(); modalEntry = false; }
  view = v;
  for (const id of VIEWS) $(`view-${id}`).classList.toggle('hidden', id !== v);
  const tab = TAB_OF[v] || 'more';
  for (const b of document.querySelectorAll('.tabbar button')) b.classList.toggle('active', b.dataset.tab === tab);
  $('noteFab').classList.toggle('on-home', v === 'home');   // sur l'accueil, le 📝 est colle a Orbit
  if (push) history.pushState({ v }, '', location.pathname);
  render();
  window.scrollTo(0, 0);
  if (v === 'search') setTimeout(() => $('searchInput').focus(), 50);
}
window.addEventListener('popstate', (e) => {
  if (ignorePop) { ignorePop = false; return; }
  if (modal) { modalEntry = false; closeModal(true); return; }
  modalEntry = false;
  go((e.state && e.state.v) || 'home', false);
});
function openModal(kind) {
  if (modal) hideModal();
  modal = kind;
  if (!modalEntry) { history.pushState({ v: view, modal: true }, '', location.pathname); modalEntry = true; }
}
let onSheetClose = null;
function hideModal() {
  if (!modal) return;
  const kind = modal;
  modal = null;
  if (kind === 'sheet') {
    $('sheet').classList.add('hidden'); $('sheetBackdrop').classList.add('hidden');
    const cb = onSheetClose; onSheetClose = null;
    if (cb) cb();
  } else {
    $('focusMode').classList.add('hidden');
    stopRunnerTimer();
  }
}
function closeModal(fromPop = false) {
  if (!modal) return;
  hideModal();
  if (!fromPop) {
    // on retire l'entree d'historique, sauf si une autre fenetre s'ouvre juste apres
    setTimeout(() => { if (!modal && modalEntry) { modalEntry = false; ignorePop = true; history.back(); } }, 0);
  }
  render();
}

function sheet(title, build, onClose) {
  openModal('sheet');
  const el = clear($('sheet'));
  el.append(h('h2', { text: title }));
  build(el);
  onSheetClose = onClose || null;
  $('sheet').classList.remove('hidden');
  $('sheetBackdrop').classList.remove('hidden');
  const first = el.querySelector('textarea, input[type=text]');
  if (first) setTimeout(() => first.focus(), 60);
}
$('sheetBackdrop').addEventListener('click', () => closeModal());

function askText(title, initial = '', placeholder = '') {
  return new Promise((resolve) => {
    let done = false;
    const finish = (v) => { if (!done) { done = true; resolve(v); } };
    sheet(title, (el) => {
      const inp = h('input', { type: 'text', value: initial, maxlength: 300, placeholder });
      inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); finish(inp.value.trim() || null); closeModal(); } });
      el.append(inp, h('div', { class: 'actions' },
        btn('Annuler', () => { finish(null); closeModal(); }),
        btn('✓ OK', () => { finish(inp.value.trim() || null); closeModal(); }, 'btn primary')));
    }, () => finish(null));
  });
}
function askConfirm(text, yes = 'Oui') {
  return new Promise((resolve) => {
    let done = false;
    const finish = (v) => { if (!done) { done = true; resolve(v); } };
    sheet(text, (el) => {
      el.append(h('div', { class: 'actions' },
        btn('Non', () => { finish(false); closeModal(); }),
        btn(yes, () => { finish(true); closeModal(); }, 'btn primary')));
    }, () => finish(false));
  });
}

// --- retours : toast, confettis, sons ------------------------------------------------
let toastTimer = 0;
function toast(text, action, seconds = 4) {
  const t = clear($('toast'));
  t.append(h('span', { text }));
  if (action) t.append(btn(action.label, () => { t.classList.add('hidden'); action.run(); }, ''));
  t.classList.remove('hidden');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.add('hidden'), seconds * 1000);
}
function confetti() {
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  const box = $('confetti');
  const colors = ['#6C5CE7', '#FF9F1C', '#3DDC84', '#5FD3FF', '#FF6B9D', '#FFD43B'];
  for (let i = 0; i < 26; i++) {
    const p = h('i');
    p.style.left = `${Math.random() * 100}%`;
    p.style.background = colors[i % colors.length];
    p.style.animationDelay = `${Math.random() * 0.25}s`;
    p.style.transform = `rotate(${Math.random() * 180}deg)`;
    box.append(p);
    setTimeout(() => p.remove(), 1800);
  }
}
// petite fete a chaque victoire (son, vibration, confettis)
function celebrate(el, big = false) {
  if (S.settings.sounds) Ob.success();
  if (S.settings.vibrate) Ob.vibrate(big ? [30, 40, 60] : 25);
  if (el) { el.classList.remove('celebrate'); void el.offsetWidth; el.classList.add('celebrate'); }
  if (big) confetti();
}

// --- la bulle d'Orbit --------------------------------------------------------------------
let bubbleTimer = 0;
let punch = null;
function bubble(text, buttons = [], opts = {}) {
  const b = $('bubble');
  clear($('bubbleText')).append(document.createTextNode(St.cleanText(text, 4000)));
  const box = clear($('bubbleButtons'));
  for (const x of buttons) {
    box.append(btn(x.label, () => { hideBubble(); x.run(); }, x.primary ? 'btn primary' : 'btn'));
  }
  b.classList.remove('hidden');
  b.style.animation = 'none'; void b.offsetWidth; b.style.animation = '';
  clearTimeout(bubbleTimer);
  const secs = opts.seconds ?? (buttons.length ? 0 : 9);
  if (secs > 0) bubbleTimer = setTimeout(hideBubble, secs * 1000);
  if (S.settings.sounds && !opts.silent) Ob.chirp(buttons.length > 0 || /\?\s*$/.test(text));
  // un message important arrive quand on est sur un autre ecran : petit rappel
  if (opts.important && view !== 'home') toast(St.shortText(text, 60), { label: 'Voir', run: () => go('home') }, 8);
}
function hideBubble() { $('bubble').classList.add('hidden'); clearTimeout(bubbleTimer); punch = null; }
function bubbleHasQuestion() { return !$('bubble').classList.contains('hidden') && $('bubbleButtons').children.length > 0; }

// --- notifications (fin de session) ----------------------------------------------------
async function notify(title, body) {
  if (!S.settings.notifications || !('Notification' in window) || Notification.permission !== 'granted') return;
  try {
    const reg = await navigator.serviceWorker?.getRegistration();
    if (reg) await reg.showNotification(title, { body, icon: 'icons/icon-192.png', badge: 'icons/icon-192.png', tag: 'orbit', renotify: true });
  } catch { /* pas grave */ }
}

// --- maintien de l'ecran pendant un focus ---------------------------------------------------
let wakeLock = null;
async function updateWakeLock() {
  const want = S.settings.wakeLock && S.timer.state === 'Focus' && !S.timer.paused && document.visibilityState === 'visible';
  try {
    if (want && !wakeLock && navigator.wakeLock) {
      wakeLock = await navigator.wakeLock.request('screen');
      wakeLock.addEventListener('release', () => { wakeLock = null; });
    } else if (!want && wakeLock) { await wakeLock.release(); wakeLock = null; }
  } catch { wakeLock = null; }
}

// =========================================================================================
//  Chrono
// =========================================================================================
const fmtClock = (ms) => { const s = Math.ceil(ms / 1000); return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`; };
let nextJoke = 0;
let nextMotivation = 0;
let endTimer = 0;

function scheduleEnd() {
  clearTimeout(endTimer);
  const t = S.timer;
  if ((t.state === 'Focus' || t.state === 'Break') && !t.paused) endTimer = setTimeout(loop, Math.max(0, t.endsAt - Date.now()) + 300);
}

function focusLabel(cards) {
  if (!cards.length) return '';
  if (cards.length === 1) return `🎯 ${St.shortText(cards[0].text, 50)}`;
  return `🎯 ${cards.slice(0, 3).map((t) => St.shortText(t.text, 22)).join(' · ')}${cards.length > 3 ? ` +${cards.length - 3}` : ''}`;
}

function startFocus() {
  St.startFocus(S);
  const cards = St.focusCards(S, true);
  let msg = Ob.fmt(Ob.pick(Ob.LINES.focusStart), St.rhythmMinutes(S.settings)[0]);
  if (cards.length) msg += `\n\n${focusLabel(cards)}`;
  nextMotivation = Date.now() + 9 * 60000;
  commit();
  scheduleEnd();
  updateWakeLock();
  if (view !== 'home') go('home');
  bubble(msg, [], { seconds: 8 });
}
function startBreak() {
  St.startBreak(S);
  nextJoke = Date.now() + 40000;
  commit();
  scheduleEnd();
  updateWakeLock();
  bubble(Ob.pick(Ob.LINES.breakStart), [], { seconds: 8 });
}
function togglePause() {
  if (S.timer.paused) { St.resumeTimer(S); bubble("Et c'est reparti ▶", [], { seconds: 3 }); }
  else { St.pauseTimer(S); bubble('Chrono en pause ⏸', [], { seconds: 3 }); }
  commit(); scheduleEnd(); updateWakeLock();
}
function stopTimer() { St.stopTimer(S); commit(); scheduleEnd(); updateWakeLock(); bubble("Ok, on s'arrête là. Reviens quand tu veux 😊", [], { seconds: 5 }); }

function askBreak(prefix = '') {
  const cards = St.focusCards(S, true);
  const btns = [{ label: '☕ Je prends ma pause', run: startBreak, primary: true }];
  if (cards.length === 1) btns.push({ label: "✅ C'est fait !", run: () => { completeCard(cards[0].id); startBreak(); } });
  btns.push({ label: "⏹ On arrête là", run: stopTimer });
  bubble(prefix + Ob.fmt(Ob.pick(Ob.LINES.focusEnd), S.timer.sessionMin), btns, { important: true });
}
function askFocus(prefix = '') {
  const next = St.planCards(S, 1)[0];
  let msg = prefix + Ob.pick(Ob.LINES.breakEnd);
  if (next && S.settings.taskReminders) msg += `\n\nProchaine carte : « ${St.shortText(next.card.text, 50)} »`;
  bubble(msg, [{ label: '🚀 On repart !', run: startFocus, primary: true }, { label: '⏹ On arrête là', run: stopTimer }], { important: true });
}

function onTimerEvent(ev, away) {
  const prefix = away ? '(Pendant que tu étais ailleurs) ' : '';
  if (S.settings.sounds) Ob.chime();
  if (S.settings.vibrate) Ob.vibrate([200, 120, 200]);
  if (ev === 'focusEnded') {
    St.addWin(S, `Focus de ${Math.round(S.timer.sessionMin)} min`, 'focus');
    save();
    notify('Focus terminé 🎉', 'Une pause ? Ouvre Orbit pour la lancer.');
    askBreak(prefix);
  } else {
    notify('Fin de la pause', 'On repart ? Ouvre Orbit pour relancer un focus.');
    askFocus(prefix);
  }
  updateWakeLock();
}

let lastReminderCheck = 0;
function loop() {
  const ev = St.tick(S);
  if (ev) { commit(); onTimerEvent(ev, document.visibilityState !== 'visible'); return; }
  const now = Date.now();
  const t = S.timer;
  if (t.state === 'Break' && !t.paused && S.settings.jokes && now >= nextJoke && St.timeLeft(S) > 20000 && view === 'home' && !bubbleHasQuestion()) {
    nextJoke = now + 120000;
    tellBreakItem();
  }
  if (t.state === 'Focus' && !t.paused && S.settings.motivation && now >= nextMotivation && view === 'home' && !bubbleHasQuestion()) {
    nextMotivation = now + 9 * 60000;
    bubble(Ob.pick(Ob.LINES.motivation), [], { seconds: 7 });
  }
  if (punch && now >= punch.at) { const p = punch; punch = null; if (!$('bubble').classList.contains('hidden')) bubble(p.full, [], { seconds: 12, silent: true }); }
  if (now - lastReminderCheck > 15000) { lastReminderCheck = now; checkRepriseReminder(); checkMorningPlan(); }
  renderClock();
  renderRunnerTimer();
}

let breakAlt = 0;
async function tellBreakItem() {
  const mode = S.settings.breakContent;
  const culture = mode === 'Culture' || (mode === 'Both' && (breakAlt++ % 2 === 1));
  const list = await data(culture ? 'culture' : 'jokes');
  const item = St.nextItem(list, S.stats, culture ? 'factSeed' : 'jokeSeed', culture ? 'factPos' : 'jokePos');
  save();
  if (!item) return;
  const [q, a] = item.split('|');
  const head = culture ? '🧠 ' : '😄 ';
  if (a) {
    bubble(`${head}${culture ? 'Quiz : ' : ''}${q} 🤔`, [], { seconds: culture ? 20 : 16 });
    punch = { at: Date.now() + (culture ? 6000 : 4000), full: `${head}${q}\n\n👉 ${a}` };
  } else bubble(`${head}${q}`, [], { seconds: 14 });
}

// =========================================================================================
//  Accueil (Orbit)
// =========================================================================================
function renderClock() {
  const t = S.timer;
  const bot = $('orbitBot');
  let txt = '▶ FOCUS', big = St.rhythmMinutes(S.settings)[0] + ':00', state = "Prêt(e) quand tu l'es", mood = 'Idle';
  if (t.state === 'Focus' || t.state === 'Break') {
    big = fmtClock(St.timeLeft(S));
    txt = (t.paused ? '⏸' : t.state === 'Break' ? '☕' : '') + big;
    state = t.paused ? 'En pause' : t.state === 'Focus' ? 'Focus en cours' : 'Pause';
    mood = t.state === 'Focus' ? 'Focus' : 'Break';
  } else if (t.state === 'AwaitBreak') { txt = '☕ ?'; big = '☕'; state = 'Focus terminé : une pause ?'; mood = 'Await'; }
  else if (t.state === 'AwaitFocus') { txt = '🚀 ?'; big = '🚀'; state = 'Pause finie : on repart ?'; mood = 'Await'; }
  $('botClock').textContent = txt;
  $('bigClock').textContent = big;
  $('timerState').textContent = state;
  Ob.setMood(bot, mood);
  document.title = (t.state === 'Focus' || t.state === 'Break') ? `${big} · Orbit` : 'Orbit';
  $('ctxBadge').classList.toggle('hidden', !(S.settings.ctxButton && t.state === 'Focus' && !t.paused));
  $('dockReprises').classList.toggle('hidden', !St.openReprises(S).length);
}

function renderHome() {
  renderClock();
  const t = S.timer;
  const box = clear($('timerButtons'));
  if (t.state === 'Idle') {
    const [f, b] = St.rhythmMinutes(S.settings);
    box.append(btn(`🚀 Lancer un focus (${f} min)`, startFocus, 'btn primary'));
    const sel = h('select', { 'aria-label': 'Rythme', onchange: (e) => { S.settings.rhythm = e.target.value; commit(); } },
      ['50/10', '25/5', 'Perso'].map((r) => h('option', { value: r, selected: S.settings.rhythm === r }, r === 'Perso' ? `Perso ${S.settings.customFocus}/${S.settings.customBreak}` : r)));
    sel.style.width = 'auto';
    box.append(sel, btn('🎯 Cartes', chooseFocusCards));
    void b;
  } else if (t.state === 'Focus' || t.state === 'Break') {
    box.append(btn(t.paused ? '▶ Reprendre' : '⏸ Pause', togglePause, 'btn primary'));
    if (t.state === 'Focus') box.append(btn('✋ Je m\'interromps', () => openInterrupt()));
    if (t.state === 'Break') box.append(btn('🚀 Reprendre le focus', startFocus));
    box.append(btn('⏹ Arrêter', stopTimer));
  } else if (t.state === 'AwaitBreak') {
    box.append(btn('☕ Pause', startBreak, 'btn primary'), btn('⏹ Arrêter', stopTimer));
  } else {
    box.append(btn('🚀 On repart', startFocus, 'btn primary'), btn('⏹ Arrêter', stopTimer));
  }
  $('focusCardsLine').textContent = (t.state === 'Idle' || t.state === 'Focus' || t.state === 'AwaitBreak') ? focusLabel(St.focusCards(S, true)) : '';

  const u = S.anchor.unstick;
  const un = clear($('homeUnstick'));
  un.classList.toggle('hidden', !u);
  if (u) un.append(h('div', { class: 'item-title', text: `⚡ En train de te débloquer : « ${St.shortText(u.title, 50)} »` }),
    h('div', { class: 'item-sub', text: `Étape ${u.index + 1} sur ${u.steps.length} : ${u.steps[u.index].content}` }),
    h('div', { class: 'item-actions' }, btn('▶ Continuer', openRunner, 'btn primary')));

  const today = clear($('homeToday'));
  const wins = St.winsOfDay(S).length;
  const rep = St.latestOpenReprise(S);
  today.append(h('h2', { text: "Aujourd'hui" }));
  const row = h('div', { class: 'item-actions' });
  if (rep) row.append(btn(`↩ Où j'en étais`, () => showResumeBubble(rep)));
  row.append(btn(wins ? `🏆 ${wins} victoire${wins > 1 ? 's' : ''}` : '🏆 Mes victoires', () => go('journal')));
  today.append(row);
}

function chooseFocusCards() {
  const plan = St.planCards(S, 200);
  const chosen = new Set(S.kanban.focus);
  sheet('🎯 Cartes de mon focus', (el) => {
    if (!plan.length) el.append(h('p', { class: 'muted', text: 'Aucune carte ouverte. Ajoute-en dans 🗂 Tableaux, ou lance un focus sans carte.' }));
    const list = h('div', { class: 'list' });
    for (const p of plan.slice(0, 60)) {
      const b = St.getBoard(S, p.card.board);
      const cb = h('input', { type: 'checkbox', checked: chosen.has(p.card.id), onchange: (e) => { if (e.target.checked) chosen.add(p.card.id); else chosen.delete(p.card.id); } });
      list.append(h('label', { class: 'check-row' }, cb, h('span', {}, h('b', { text: `P${p.card.prio} ` }), p.card.text, h('br'), h('small', { class: 'muted', text: `${b ? b.name : ''}${p.why ? ' · ' + p.why : ''}` }))));
    }
    el.append(list, h('div', { class: 'actions' },
      btn('Enregistrer', () => { S.kanban.focus = [...chosen]; commit(); closeModal(); }),
      btn('🚀 Lancer le focus', () => { S.kanban.focus = [...chosen]; save(); closeModal(); startFocus(); }, 'btn primary')));
  });
}

// --- plan du matin ---------------------------------------------------------------------
function checkMorningPlan() {
  const now = new Date();
  if (!S.settings.morningPlan || S.timer.state !== 'Idle' || now.getHours() < 5 || S.stats.planDay === St.dayString(now) || view !== 'home' || bubbleHasQuestion() || modal) return;
  showMorningPlan(false);
}
function showMorningPlan(manual) {
  // proposé tout seul : seulement sur l'accueil (jamais en arrachant l'utilisateur à un autre écran)
  if (view !== 'home' || modal) { if (!manual) return; go('home'); }
  S.stats.planDay = St.dayString();
  save();
  const hello = new Date().getHours() < 12 ? '☀ Bonjour !' : '👋 Re-bonjour !';
  const plan = St.planCards(S, 3);
  const rep = St.latestOpenReprise(S);
  let text = hello;
  const btns = [];
  if (rep) { text += `\n↩ Tu t'étais arrêté(e) ${St.formatAgo(rep.created)} sur « ${St.repriseTitle(rep, 50)} ».`; btns.push({ label: '↩ Reprendre là', run: () => resumeReprise(rep.id) }); }
  if (plan.length) {
    text += '\n\nMon plan pour ta journée :';
    plan.forEach((p, i) => { text += `\n${i + 1}. P${p.card.prio} « ${St.shortText(p.card.text, 45)} »${p.why ? `\n     ${p.why}` : ''}`; });
    btns.push({ label: '🎯 Go, focus sur ces cartes', primary: true, run: () => { S.kanban.focus = plan.map((p) => p.card.id); save(); startFocus(); } });
  }
  if (!plan.length && !rep) text += "\nRien de prévu : ajoute une carte dans 🗂 Tableaux, ou note une idée avec 📝.";
  btns.push({ label: 'Plus tard', run: () => {} });
  bubble(text, btns, { seconds: manual ? 0 : 180 });
}

// =========================================================================================
//  ✋ Je m'interromps / reprises
// =========================================================================================
let offeredAt = {};
function openInterrupt({ url = '', title = '', fromShare = false, edit = null } = {}) {
  let pausedHere = false;
  if (!edit && S.timer.state === 'Focus' && !S.timer.paused) { St.pauseTimer(S); pausedHere = true; save(); renderClock(); }
  let saved = false;
  const c = edit;
  sheet(edit ? '✏ Modifier la reprise' : "✋ Je m'interromps", (el) => {
    const summary = [];
    if (pausedHere) summary.push(`⏸ Focus en pause (${Math.ceil(St.timeLeft(S) / 60000)} min restantes)`);
    const fc = St.focusCards(S, true);
    if (!edit && fc.length) summary.push(focusLabel(fc));
    if (summary.length) el.append(h('div', { class: 'summary', text: summary.join('\n') }));
    const link = h('input', { type: 'text', value: c ? (c.windows[0]?.url || '') : url, placeholder: 'Lien de la page (facultatif)', inputmode: 'url', maxlength: 2048 });
    const doing = h('textarea', { rows: 2, maxlength: 2000, placeholder: 'Ex. : je relisais le contrat, page 4' });
    doing.value = c ? c.doing : (title && !fromShare ? title : '');
    const next = h('textarea', { rows: 2, maxlength: 2000, placeholder: 'Ex. : appeler Julie pour valider l’article 4' });
    next.value = c ? c.next : St.suggestedNext(S);
    const paste = btn('📋 Coller', async () => {
      try { const t = await navigator.clipboard.readText(); const u = St.findUrl(t) || St.safeUrl(t); if (u) link.value = u; else toast('Pas de lien dans le presse-papiers'); }
      catch { toast('Copie le lien, puis appuie longuement dans la case pour coller'); }
    });
    el.append(h('label', { class: 'field', text: '🔗 Où j’étais (lien)' }), h('div', { class: 'row' }, link, paste),
      h('label', { class: 'field', text: "J'étais en train de…" }), doing, micButton(doing),
      h('label', { class: 'field', text: '➡ Prochaine étape exacte (pour m’y remettre sans réfléchir)' }), next, micButton(next));
    const doSave = () => {
      saved = true;
      const u = St.safeUrl(link.value) || St.findUrl(link.value);
      if (c) {
        c.doing = St.cleanText(doing.value, 2000).trim();
        c.next = St.cleanText(next.value, 2000).trim();
        c.windows = u ? [{ app: 'telephone', title: c.windows[0]?.title || '', url: u, path: '', hwnd: 0, pid: 0, private: false }] : c.windows.filter((w) => !w.url);
        commit(); closeModal(); return;
      }
      const r = St.newReprise(S, { url: u, title: fromShare ? title : '', doing: doing.value.trim(), next: next.value.trim() });
      St.addReprise(S, r);
      commit(); closeModal();
      bubble(`✋ C'est noté, je garde où tu en es.${r.next ? `\n➡ ${St.shortText(r.next, 80)}` : ''}\nQuand tu reviens, touche-moi : je te remets là où tu en étais.${pausedHere ? '\n⏸ Focus en pause.' : ''}`, [], { seconds: 8 });
    };
    const actions = h('div', { class: 'actions' });
    if (fromShare) actions.append(btn('📝 Plutôt en note', () => { saved = true; St.addNote(S, [title, link.value].filter(Boolean).join('\n')); commit(); closeModal(); toast('📝 Gardé dans tes notes'); }));
    actions.append(btn('Annuler', () => closeModal()), btn('✓ Enregistrer', doSave, 'btn primary'));
    el.append(actions);
  }, () => {
    if (!saved && pausedHere && S.timer.state === 'Focus' && S.timer.paused) { St.resumeTimer(S); save(); scheduleEnd(); }
  });
}

function showResumeBubble(c, reminder = false) {
  if (!c) return;
  offeredAt[c.id] = Date.now();
  if (view !== 'home') go('home');
  let text = `${reminder ? '⏰ Tu reprends ? ' : '↩ '}Tu t'étais arrêté(e) ${St.formatAgo(c.created)}`;
  const w = c.windows[0];
  if (w && (w.title || w.url)) text += ` sur :\n🔗 ${w.title || w.url.replace(/^https?:\/\//, '')}`;
  if (c.doing) text += `\n✍ J'étais en train de : ${c.doing}`;
  if (c.next) text += `\n➡ Prochaine étape : ${c.next}`;
  const more = St.openReprises(S).length - 1;
  if (more > 0) text += `\n(${more} autre${more > 1 ? 's' : ''} reprise${more > 1 ? 's' : ''} en attente)`;
  const id = c.id;
  const btns = [
    { label: '▶ Reprendre', primary: true, run: () => resumeReprise(id) },
    { label: '⏰ Plus tard', run: () => snoozeReprise(id) },
    { label: '🗂 En carte', run: () => { const card = St.repriseToCard(S, id); commit(); if (card) toast('🗂 Transformée en carte'); } },
    { label: '✓ Déjà fait', run: () => { St.completeReprise(S, id); commit(); celebrate(null); } },
  ];
  if (more > 0) btns.push({ label: '↩ Toutes', run: () => go('reprises') });
  bubble(text, btns, { seconds: 120 });
}

function resumeReprise(id) {
  const c = S.reprises.find((x) => x.id === id);
  if (!c) return;
  const w = c.windows.find((x) => St.safeUrl(x.url));
  if (w) window.open(St.safeUrl(w.url), '_blank', 'noopener,noreferrer');
  let focusMsg = '';
  if (S.timer.state === 'Focus' && S.timer.paused) { St.resumeTimer(S); focusMsg = `\n▶ Le focus reprend : encore ${Math.ceil(St.timeLeft(S) / 60000)} min.`; }
  else if (S.timer.state === 'Idle' && c.wasFocus) {
    S.kanban.focus = c.focusCards.filter((x) => St.findCard(S, x));
    St.startFocus(S);
    focusMsg = '\n▶ Nouveau focus lancé.';
  }
  St.completeReprise(S, id);
  St.addWin(S, `Repris : ${St.repriseTitle(c, 60)}`, 'reprise');
  commit(); scheduleEnd(); updateWakeLock();
  if (view !== 'home') go('home');
  let text = "▶ C'est reparti !";
  if (c.next) text += `\n➡ Prochaine étape : ${c.next}`;
  else if (c.doing) text += `\n✍ Tu étais en train de : ${c.doing}`;
  bubble(text + focusMsg, [], { seconds: 15 });
}
function snoozeReprise(id) {
  const c = S.reprises.find((x) => x.id === id);
  if (!c) return;
  if (S.settings.ctxRemind) {
    c.remindAt = St.isoLocal(new Date(Date.now() + S.settings.ctxRemindMin * 60000));
    commit();
    toast(`⏰ Je te le rappelle dans ${S.settings.ctxRemindMin} min`);
  } else toast('Ok ! Tout est gardé dans ☰ Plus > ↩ Reprises');
}
function checkRepriseReminder() {
  if (document.visibilityState !== 'visible' || modal || bubbleHasQuestion()) return;
  if (S.timer.state === 'Focus' && !S.timer.paused) return;
  const c = St.dueReprise(S);
  if (!c) return;
  c.reminders++;
  c.remindAt = St.isoLocal(new Date(Date.now() + Math.max(5, S.settings.ctxRemindMin) * 60000));
  save();
  if (S.settings.vibrate) Ob.vibrate(40);
  showResumeBubble(c, true);
}

function renderReprises() {
  const list = clear($('repriseList'));
  const open = St.openReprises(S);
  if (!open.length) list.append(h('div', { class: 'empty', text: "Aucune reprise en attente 🎉\nQuand on t'interrompt : ✋ Je m'interromps. Je garde le lien et la prochaine étape." }));
  for (const c of open) list.append(repriseItem(c));
  const done = S.reprises.filter((c) => c.status === 'done').sort((a, b) => (a.doneAt < b.doneAt ? 1 : -1)).slice(0, 15);
  if (done.length) { list.append(h('h2', { class: 'section', text: '✓ Déjà reprises (14 jours)' })); for (const c of done) list.append(repriseItem(c)); }
}
function repriseItem(c) {
  const open = c.status === 'open';
  const w = c.windows[0];
  const it = h('div', { class: `item${open ? '' : ' dim'}` },
    h('div', { class: 'item-sub', text: open ? `✋ ${St.formatAgo(c.created)}` : `✓ reprise ${St.formatAgo(c.doneAt)}` }),
    w && (w.title || w.url) ? h('div', { class: 'item-title', text: w.title || w.url.replace(/^https?:\/\//, '') }) : null,
    w && w.url ? h('div', { class: 'item-sub', text: `🔗 ${St.shortText(w.url, 70)}` }) : null,
    c.doing ? h('div', { class: 'item-sub', text: `✍ ${c.doing}` }) : null,
    c.next ? h('div', { class: 'item-next', text: `➡ ${c.next}` }) : null);
  const acts = h('div', { class: 'item-actions' });
  if (open) {
    acts.append(btn('▶ Reprendre', () => resumeReprise(c.id), 'btn primary'),
      btn('✏', () => openInterrupt({ edit: c }), 'btn', { 'aria-label': 'Modifier' }),
      btn('🗂', () => { St.repriseToCard(S, c.id); commit(); toast('🗂 Transformée en carte'); }, 'btn', { 'aria-label': 'En carte' }),
      btn('✓', () => { St.completeReprise(S, c.id); commit(); celebrate(it); }, 'btn', { 'aria-label': 'Terminé' }));
  }
  acts.append(btn('🗑', async () => { if (!open || await askConfirm('Supprimer cette reprise ?', 'Supprimer')) { S.reprises = S.reprises.filter((x) => x.id !== c.id); commit(); } }, 'btn', { 'aria-label': 'Supprimer' }));
  it.append(acts);
  return it;
}

// =========================================================================================
//  🏆 Journal des victoires (rempli tout seul : focus, cartes finies, deblocages, reprises)
// =========================================================================================
function renderJournal() {
  const today = St.winsOfDay(S);
  const streak = St.winStreak(S);
  $('journalIntro').textContent = today.length
    ? `Aujourd'hui, tu as déjà ${today.length} victoire${today.length > 1 ? 's' : ''} 🎉${streak >= 2 ? `  ·  🔥 ${streak} jours d'affilée` : ''}`
    : "La journée commence. Chaque petite chose faite comptera ici 🌱";
  const l = clear($('journalToday'));
  for (const w of today) l.append(h('div', { class: 'item win' }, h('span', { class: 'ico', text: WIN_ICON[w.kind] || '✅' }), h('span', { class: 'grow', text: w.title }), h('span', { class: 'muted small', text: w.at.slice(11, 16) })));
  const p = clear($('journalPast'));
  const d = new Date();
  for (let i = 1; i <= 7; i++) {
    d.setDate(d.getDate() - 1);
    const list = St.winsOfDay(S, d);
    if (!list.length) continue;
    p.append(h('div', { class: 'item' }, h('div', { class: 'item-title', text: `${d.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })} : ${list.length} victoire${list.length > 1 ? 's' : ''}` }),
      h('div', { class: 'item-sub', text: list.slice(0, 4).map((w) => `${WIN_ICON[w.kind] || '✅'} ${w.title}`).join('\n') + (list.length > 4 ? '\n…' : '') })));
  }
  if (!p.children.length) p.append(h('div', { class: 'empty', text: 'Tes victoires des jours précédents apparaîtront ici.' }));
}

// =========================================================================================
//  ⚡ Unstick Me : une seule chose a la fois
// =========================================================================================
let runnerTick = 0;
function stopRunnerTimer() { clearInterval(runnerTick); runnerTick = 0; }
function startUnstickFor(title) {
  if (!RULES) { toast('Un instant…'); data('unstick').then((r) => { RULES = r; startUnstickFor(title); }); return; }
  St.startUnstick(S, title, RULES);
  commit();
  openRunner();
}
function openSos() {
  if (S.anchor.unstick) { openRunner(); return; }
  openModal('focus');
  const fm = clear($('focusMode'));
  fm.classList.remove('hidden');
  const inp = h('textarea', { rows: 2, maxlength: 300, placeholder: 'Ex. : répondre au mail de Julie' });
  const go2 = () => { const v = inp.value.trim(); if (v) startUnstickFor(v); };
  inp.addEventListener('keydown', (e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); go2(); } });
  const sugg = h('div', { class: 'item-actions' });
  const ideas = [...St.focusCards(S, true), ...St.planCards(S, 4).map((p) => p.card)].map((t) => t.text).filter((t, i, a) => a.indexOf(t) === i).slice(0, 4);
  for (const t of ideas) sugg.append(btn(St.shortText(t, 28), () => startUnstickFor(t), 'chip'));
  fm.append(h('div', { class: 'fm-top' }, h('b', { text: '🚨 S.O.S déblocage' }), btn('✖ Fermer', () => closeModal(), 'btn ghost')),
    h('div', { class: 'fm-center' },
      h('div', { class: 'fm-step', text: "Qu'est-ce que tu n'arrives pas à commencer ?" }),
      h('p', { class: 'muted', text: 'Je le découpe en micro-étapes ridiculement petites. Tu ne verras que la première.' }),
      h('div', { class: 'fm-actions' }, inp, h('div', { class: 'row' }, micButton(inp), btn('⚡ Découper', go2, 'btn primary grow'))),
      ideas.length ? h('p', { class: 'muted small', text: 'Ou bien :' }) : null, sugg));
  setTimeout(() => inp.focus(), 80);
}
function openRunner() {
  if (!S.anchor.unstick) { openSos(); return; }
  if (modal !== 'focus') openModal('focus');
  $('focusMode').classList.remove('hidden');
  renderRunner();
}
function renderRunner() {
  const u = S.anchor.unstick;
  const fm = clear($('focusMode'));
  if (!u) return;
  const step = u.steps[u.index];
  const noise = btn(Ob.brownNoiseOn() ? '🟤 Bruit brun : oui' : '🟤 Bruit brun', () => { Ob.brownNoise(!Ob.brownNoiseOn()); renderRunner(); }, 'btn ghost');
  fm.append(h('div', { class: 'fm-top' }, btn('✖ Plus tard', () => closeModal(), 'btn ghost'), noise));
  const dots = h('div', { class: 'dots' }, u.steps.map((s, i) => h('i', { class: s.done ? 'done' : i === u.index ? 'on' : '' })));
  const total = step.sec;
  const r = 70, circ = 2 * Math.PI * r;
  const ring = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  ring.setAttribute('viewBox', '0 0 170 170'); ring.setAttribute('class', 'ring-timer');
  const mk = (cls) => { const c = document.createElementNS('http://www.w3.org/2000/svg', 'circle'); c.setAttribute('cx', 85); c.setAttribute('cy', 85); c.setAttribute('r', r); c.setAttribute('class', cls); return c; };
  const bg = mk('bg'), fg = mk('fg');
  fg.setAttribute('stroke-dasharray', String(circ));
  fg.setAttribute('stroke-dashoffset', '0');
  fg.id = 'runnerRing';
  const txt = document.createElementNS('http://www.w3.org/2000/svg', 'text');
  txt.setAttribute('x', 85); txt.setAttribute('y', 95); txt.setAttribute('text-anchor', 'middle'); txt.id = 'runnerText';
  txt.textContent = fmtClock(total * 1000);
  ring.append(bg, fg, txt);
  const acts = h('div', { class: 'fm-actions' },
    btn("✅ C'est fait !", stepDone, 'btn ok big'),
    u.timerEndsAt ? null : btn(`▶ Je commence (minuteur ${fmtClock(total * 1000)})`, () => { St.unstickStartTimer(S); save(); renderRunner(); }, 'btn primary'),
    h('div', { class: 'row' },
      btn('🔪 Plus petit', splitStep, 'btn grow'),
      btn('✏ Modifier', async () => { const v = await askText('Modifier cette étape', step.content); if (v) { step.content = St.cleanText(v); save(); } openRunner(); }, 'btn grow'),
      btn('⏭ Passer', () => { if (u.index < u.steps.length - 1) { u.index++; u.timerEndsAt = 0; save(); renderRunner(); } else stepDone(); }, 'btn grow')));
  fm.append(h('div', { class: 'fm-center' },
    h('div', { class: 'fm-task', text: `⚡ ${St.shortText(u.title, 60)}` }), dots,
    h('div', { class: 'muted', text: `Étape ${u.index + 1} sur ${u.steps.length} · une seule chose` }),
    h('div', { class: 'fm-step', text: step.content }), ring,
    h('p', { class: 'muted small', id: 'runnerHint', text: u.timerEndsAt ? 'Juste pour amorcer : pas besoin de finir.' : 'Le minuteur est doux : il ne sonne pas.' }),
    acts));
  stopRunnerTimer();
  if (u.timerEndsAt) runnerTick = setInterval(renderRunnerTimer, 500);
  renderRunnerTimer();
}
let runnerBuzzed = 0;
function renderRunnerTimer() {
  const u = S.anchor.unstick;
  const fg = $('runnerRing');
  if (!u || !fg || modal !== 'focus') return;
  const total = u.steps[u.index].sec * 1000;
  const left = u.timerEndsAt ? Math.max(0, u.timerEndsAt - Date.now()) : total;
  const circ = 2 * Math.PI * 70;
  fg.setAttribute('stroke-dashoffset', String(circ * (1 - left / total)));
  $('runnerText').textContent = fmtClock(left);
  if (u.timerEndsAt && left <= 0) {
    fg.classList.add('over');
    $('runnerText').textContent = '✓';
    $('runnerHint').textContent = 'Le temps est passé : continue sur ta lancée, ou passe à la suite 🙂';
    if (runnerBuzzed !== u.timerEndsAt) { runnerBuzzed = u.timerEndsAt; if (S.settings.vibrate) Ob.vibrate(30); }
    stopRunnerTimer();
  }
}
function splitStep() {
  const u = S.anchor.unstick;
  if (!u || u.steps.length >= 12) return;
  const s = u.steps[u.index];
  u.steps.splice(u.index, 0, { content: `Prépare-toi juste pour : « ${St.shortText(s.content, 80)} » (pose ce qu'il faut devant toi)`, sec: 90, done: false });
  u.timerEndsAt = 0;
  save(); renderRunner();
}
function stepDone() {
  const r = St.unstickStepDone(S);
  save();
  if (r === 'next') { celebrate($('focusMode').querySelector('.fm-step')); renderRunner(); return; }
  if (r === 'finished') {
    celebrate(null, true);
    const fm = clear($('focusMode'));
    stopRunnerTimer();
    fm.append(h('div', { class: 'fm-center' },
      h('div', { class: 'fm-step', text: '🎉 Tu es lancé(e) !' }),
      h('p', { class: 'muted', text: "Le plus dur, c'était de commencer. C'est fait, et c'est noté dans tes victoires." }),
      h('div', { class: 'fm-actions' },
        btn('🚀 Enchaîner avec un focus', () => { closeModal(); startFocus(); }, 'btn primary big'),
        btn('🏆 Voir mes victoires', () => { closeModal(); go('journal'); }, 'btn big'),
        btn('Fermer', () => closeModal(), 'btn ghost'))));
    render();
  }
}

// =========================================================================================
//  🗂 Tableaux
// =========================================================================================
function completeCard(id) {
  const t = St.findCard(S, id);
  if (!t) return;
  St.setCardDone(S, id, true);
  St.addWin(S, t.text, 'card');
  commit();
}
function renderKanban() {
  const pick = clear($('boardPick'));
  for (const b of S.kanban.boards) pick.append(h('option', { value: b.id, selected: b.id === S.kanban.current }, b.name));
  const board = St.currentBoard(S);
  const cols = clear($('columns'));
  for (const c of board.columns) {
    const col = h('div', { class: `column${c.done ? ' done-col' : ''}` });
    const cards = St.columnCards(S, c.id);
    col.append(h('div', { class: 'column-head' }, h('span', { text: `${c.done ? '✅ ' : ''}${c.name} (${cards.length})` }), btn('⋯', () => columnMenu(board, c), '', { 'aria-label': 'Options de la colonne' })));
    for (const t of cards) {
      const meta = [];
      if (t.due && !t.done) meta.push(`📅 ${St.formatDue(t.due)}`);
      if (t.checks.length) meta.push(`☑ ${t.checks.filter((x) => x.done).length}/${t.checks.length}`);
      if (t.pomos) meta.push(`🍅 ${t.pomos}`);
      if (t.remindAt && !t.done) meta.push(`⏰ ${t.remindAt.slice(8, 10)}/${t.remindAt.slice(5, 7)} ${t.remindAt.slice(11, 16)}`);
      const card = h('button', { type: 'button', class: `card${S.kanban.focus.includes(t.id) ? ' in-focus' : ''}`, onclick: () => openCard(t.id) },
        h('span', { class: `prio p${t.prio}`, text: `P${t.prio}` }), h('span', { text: t.text }),
        meta.length ? h('div', { class: 'meta', text: meta.join('  ') }) : null);
      const row = h('div', { class: 'card-row' }, card,
        btn(t.done ? '↺' : '✓', () => { if (t.done) { St.setCardDone(S, t.id, false); commit(); } else { completeCard(t.id); celebrate(card, true); } }, 'card-done', { 'aria-label': t.done ? 'Rouvrir' : 'Terminer' }));
      col.append(row);
    }
    const inp = h('input', { type: 'text', maxlength: 300, placeholder: '＋ Ajouter (!2 = priorité, @14h = rappel)' });
    col.append(h('form', { onsubmit: (e) => { e.preventDefault(); if (St.addCard(S, inp.value, c.id)) { commit(); setTimeout(() => { const f = $('columns').querySelectorAll('.column')[board.columns.indexOf(c)]?.querySelector('input'); if (f) f.focus(); }, 0); } } }, inp));
    cols.append(col);
  }
}
async function boardMenu() {
  const b = St.currentBoard(S);
  sheet(`🗂 ${b.name}`, (el) => {
    el.append(h('div', { class: 'list' },
      btn('＋ Nouveau tableau', async () => { closeModal(); const n = await askText('Nom du nouveau tableau'); if (n) { const nb = St.newBoard(St.cleanText(n, 60)); S.kanban.boards.push(nb); S.kanban.current = nb.id; commit(); } }),
      btn('＋ Ajouter une colonne', async () => { closeModal(); const n = await askText('Nom de la colonne'); if (n && b.columns.length < St.LIMITS.columns) { const di = b.columns.findIndex((c) => c.done); const col = St.newColumn(St.cleanText(n, 60)); if (di >= 0) b.columns.splice(di, 0, col); else b.columns.push(col); commit(); } }),
      btn('✏ Renommer ce tableau', async () => { closeModal(); const n = await askText('Renommer le tableau', b.name); if (n) { b.name = St.cleanText(n, 60); commit(); } }),
      btn('🗑 Supprimer ce tableau', async () => {
        closeModal();
        if (S.kanban.boards.length < 2) { toast('Il faut garder au moins un tableau'); return; }
        if (await askConfirm(`Supprimer « ${b.name} » et ses cartes ?`, 'Supprimer')) {
          S.kanban.cards.filter((t) => t.board === b.id).forEach((t) => St.removeCard(S, t.id));
          S.kanban.boards = S.kanban.boards.filter((x) => x.id !== b.id);
          S.kanban.current = S.kanban.boards[0].id; commit();
        }
      })));
  });
}
function columnMenu(b, c) {
  const i = b.columns.indexOf(c);
  sheet(`Colonne « ${c.name} »`, (el) => {
    el.append(h('div', { class: 'list' },
      btn('✏ Renommer', async () => { closeModal(); const n = await askText('Renommer la colonne', c.name); if (n) { c.name = St.cleanText(n, 60); commit(); } }),
      i > 0 ? btn('← Déplacer à gauche', () => { b.columns.splice(i, 1); b.columns.splice(i - 1, 0, c); commit(); closeModal(); }) : null,
      i < b.columns.length - 1 ? btn('→ Déplacer à droite', () => { b.columns.splice(i, 1); b.columns.splice(i + 1, 0, c); commit(); closeModal(); }) : null,
      btn(c.done ? '↺ Ne plus marquer « terminé »' : '✅ Marquer comme colonne « terminé »', () => {
        c.done = !c.done;
        for (const t of St.columnCards(S, c.id)) { t.done = c.done; t.doneAt = c.done ? St.isoLocal() : ''; }
        commit(); closeModal();
      }),
      btn('🗑 Supprimer la colonne', async () => {
        closeModal();
        if (b.columns.length < 2) { toast('Il faut garder au moins une colonne'); return; }
        const cards = St.columnCards(S, c.id);
        if (cards.length && !(await askConfirm(`Supprimer « ${c.name} » ? Ses ${cards.length} carte(s) iront dans une autre colonne.`, 'Supprimer'))) return;
        b.columns = b.columns.filter((x) => x.id !== c.id);
        const target = St.openColumn(b);
        for (const t of cards) St.moveCard(S, t.id, target.id);
        commit();
      })));
  });
}
function openCard(id) {
  const t = St.findCard(S, id);
  if (!t) return;
  const title = h('input', { type: 'text', value: t.text, maxlength: 300 });
  const desc = h('textarea', { rows: 3, maxlength: 20000 }); desc.value = t.desc;
  const prio = h('select', {}, Array.from({ length: 10 }, (_, i) => h('option', { value: i + 1, selected: t.prio === i + 1 }, `P${i + 1}${i === 0 ? ' (le plus urgent)' : ''}`)));
  const due = h('input', { type: 'date', value: t.due });
  const colSel = h('select', {});
  for (const b of S.kanban.boards) {
    const g = h('optgroup', { label: b.name });
    for (const c of b.columns) g.append(h('option', { value: c.id, selected: c.id === t.col }, c.name));
    colSel.append(g);
  }
  const checks = h('div');
  const drawChecks = () => {
    clear(checks);
    t.checks.forEach((ck, i) => checks.append(h('div', { class: 'check-row' },
      h('input', { type: 'checkbox', checked: ck.done, onchange: (e) => { ck.done = e.target.checked; if (ck.done) celebrate(e.target); save(); } }),
      h('span', { text: ck.text }), btn('✕', () => { t.checks.splice(i, 1); drawChecks(); }, '', { 'aria-label': 'Retirer' }))));
  };
  drawChecks();
  const newCheck = h('input', { type: 'text', maxlength: 300, placeholder: '＋ Sous-tâche (Entrée)' });
  newCheck.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); const v = St.cleanText(newCheck.value).trim(); if (v && t.checks.length < St.LIMITS.checks) { t.checks.push({ text: v, done: false }); newCheck.value = ''; drawChecks(); } } });
  let deleted = false;
  const apply = () => {
    if (deleted || !St.findCard(S, id)) return;
    t.text = St.cleanText(title.value).trim() || t.text;
    t.desc = St.cleanText(desc.value, St.LIMITS.long);
    t.prio = St.limitPrio(prio.value);
    t.due = /^\d{4}-\d{2}-\d{2}$/.test(due.value) ? due.value : '';
    if (colSel.value !== t.col) {
      const wasDone = t.done;
      St.moveCard(S, t.id, colSel.value);
      if (t.done && !wasDone) { St.addWin(S, t.text, 'card'); celebrate(null, true); }
    }
    commit();
  };
  sheet('🗂 Carte', (el) => {
    const inFocus = S.kanban.focus.includes(t.id);
    el.append(h('label', { class: 'field', text: 'Titre' }), title,
      h('label', { class: 'field', text: 'Description' }), desc,
      h('div', { class: 'row' }, h('div', { class: 'grow' }, h('label', { class: 'field', text: 'Priorité' }), prio), h('div', { class: 'grow' }, h('label', { class: 'field', text: 'Échéance' }), due)),
      h('label', { class: 'field', text: 'Colonne' }), colSel,
      h('label', { class: 'field', text: 'Sous-tâches' }), checks, newCheck,
      h('div', { class: 'actions' },
        btn(inFocus ? '🎯 Retirer du focus' : '🎯 Lier au focus', () => { St.setCardFocus(S, t.id, !inFocus); closeModal(); }),
        btn('⚡ Débloquer', () => { apply(); deleted = true; closeModal(); startUnstickFor(t.text); }),
        btn('🗑 Supprimer', async () => { closeModal(); if (await askConfirm(`Supprimer « ${St.shortText(t.text, 40)} » ?`, 'Supprimer')) { St.removeCard(S, t.id); commit(); } }),
        btn('✓ OK', () => closeModal(), 'btn primary')));
  }, apply);
}

// =========================================================================================
//  📝 Notes
// =========================================================================================
function renderNotes() {
  const l = clear($('notesList'));
  const notes = St.sortedNotes(S);
  if (!notes.length) l.append(h('div', { class: 'empty', text: 'Aucune note pour l’instant. ＋ Nouvelle, ou le bouton 📥 pour une idée en vrac.' }));
  for (const n of notes) {
    l.append(h('button', { type: 'button', class: 'card', onclick: () => openNote(n.id) },
      h('div', { class: 'item-sub', text: `${n.pinned ? '📌 ' : ''}${n.updated.slice(8, 10)}/${n.updated.slice(5, 7)} à ${n.updated.slice(11, 16)}` }),
      h('div', { class: 'item-title', text: St.noteTitle(n, 80) }),
      h('div', { class: 'item-sub', text: St.shortText(n.text.split('\n').slice(1).join(' '), 120) })));
  }
}
function openNote(id = '') {
  let n = id ? S.notes.find((x) => x.id === id) : null;
  const ta = h('textarea', { rows: 8, maxlength: 20000, placeholder: 'Ta note… (1re ligne = titre si tu la transformes en carte)' });
  ta.value = n ? n.text : '';
  let handled = false;
  const finish = () => {
    if (handled) return;
    handled = true;
    if (n) St.updateNote(S, n.id, ta.value); else if (ta.value.trim()) n = St.addNote(S, ta.value);
    commit();
  };
  sheet(n ? '📝 Note' : '📝 Nouvelle note', (el) => {
    el.append(ta, h('div', { class: 'actions' }, micButton(ta),
      n ? btn(n.pinned ? '📌 Désépingler' : '📍 Épingler', () => { n.pinned = !n.pinned; closeModal(); }) : null,
      btn('🗂 En carte', () => { finish(); if (n && St.noteToCard(S, n.id)) { commit(); toast('🗂 Note transformée en carte'); } closeModal(); }),
      n ? btn('🗑', async () => { handled = true; closeModal(); if (await askConfirm('Supprimer cette note ?', 'Supprimer')) { S.notes = S.notes.filter((x) => x.id !== n.id); commit(); } }, 'btn', { 'aria-label': 'Supprimer' }) : null,
      btn('✓ OK', () => closeModal(), 'btn primary')));
  }, finish);
}

// =========================================================================================
//  🔍 Recherche
// =========================================================================================
function renderSearch() {
  const q = $('searchInput').value;
  const out = clear($('searchResults'));
  if (St.searchKey(q).length < 2) { out.append(h('p', { class: 'muted', text: 'Plusieurs mots : ils doivent tous y être. Les accents et majuscules ne comptent pas.' })); return; }
  const r = St.searchAll(S, q);
  const section = (title, items, make) => { if (!items.length) return; out.append(h('h2', { class: 'section', text: `${title} (${items.length})` })); items.slice(0, 50).forEach((x) => out.append(make(x))); };
  section('🗂 Cartes', r.cards, (t) => h('button', { type: 'button', class: `card${t.done ? ' dim' : ''}`, onclick: () => openCard(t.id) }, h('span', { class: `prio p${t.prio}`, text: `P${t.prio}` }), t.text, h('div', { class: 'meta', text: St.getBoard(S, t.board)?.name || '' })));
  section('📝 Notes', r.notes, (n) => h('button', { type: 'button', class: 'card', onclick: () => openNote(n.id) }, St.noteTitle(n, 80)));
  section('↩ Reprises', r.reprises, (c) => h('button', { type: 'button', class: 'card', onclick: () => go('reprises') }, St.repriseTitle(c, 80)));
  if (!out.children.length) out.append(h('p', { class: 'muted', text: 'Rien trouvé.' }));
}

// =========================================================================================
//  ⚙ Reglages
// =========================================================================================
const SETTINGS_FORM = [
  ['⏱ Rythme', [['rhythm', 'select', 'Rythme', [['50/10', '50 min / 10 min'], ['25/5', '25 min / 5 min'], ['Perso', 'Perso']]], ['customFocus', 'number', 'Focus perso (min)', 1, 240], ['customBreak', 'number', 'Pause perso (min)', 1, 120]]],
  ['😄 Pendant la pause', [['jokes', 'bool', 'Blagues ou culture G'], ['breakContent', 'select', 'Contenu', [['Both', 'Les deux, en alternance'], ['Jokes', 'Des blagues'], ['Culture', 'De la culture G']]], ['motivation', 'bool', 'Petites phrases de motivation pendant le focus']]],
  ['🔔 Sons et rappels', [['sounds', 'bool', 'Sons doux (jamais stridents)'], ['vibrate', 'bool', 'Vibrations'], ['notifications', 'bool', 'Notification à la fin d’une session', "Tant que l'appli est ouverte ou en arrière-plan récent."], ['wakeLock', 'bool', 'Garder l’écran allumé pendant un focus', "Pour que le chrono sonne à coup sûr."], ['taskReminders', 'bool', 'Proposer ma carte la plus urgente au début du focus'], ['morningPlan', 'bool', 'Plan du matin']]],
  ["✋ Je m'interromps", [['ctxButton', 'bool', 'Bouton ✋ à côté d’Orbit pendant un focus'], ['ctxRemind', 'bool', 'Me relancer si je n’ai pas repris (3 fois max)'], ['ctxRemindMin', 'number', 'Après (minutes)', 5, 480]]],
];
function renderSettings() {
  const f = clear($('settingsForm'));
  for (const [legend, fields] of SETTINGS_FORM) {
    const fs = h('fieldset', {}, h('legend', { text: legend }));
    for (const [key, type, label, a, b] of fields) {
      let input;
      if (type === 'bool') input = h('input', { type: 'checkbox', checked: S.settings[key] });
      else if (type === 'number') input = h('input', { type: 'number', min: a, max: b, value: S.settings[key], inputmode: 'numeric' });
      else input = h('select', {}, a.map(([v, t]) => h('option', { value: v, selected: S.settings[key] === v }, t)));
      input.addEventListener('change', async () => {
        const v = type === 'bool' ? input.checked : type === 'number' ? Number(input.value) : input.value;
        if (key === 'notifications' && v && 'Notification' in window && Notification.permission !== 'granted') {
          const p = await Notification.requestPermission().catch(() => 'denied');
          if (p !== 'granted') { input.checked = false; toast('Notifications refusées par le téléphone'); return; }
        }
        S.settings = St.sanitizeSettings({ ...S.settings, [key]: v });
        save(); updateWakeLock(); renderClock();
      });
      fs.append(type === 'bool' ? h('label', {}, input, label) : h('label', {}, h('span', { class: 'grow', text: label }), input));
      if (type === 'bool' && a) fs.append(h('div', { class: 'hint', text: a }));
    }
    f.append(fs);
  }
  f.append(h('fieldset', {}, h('legend', { text: '🟤 Ambiance' }),
    btn(Ob.brownNoiseOn() ? '⏹ Arrêter le bruit brun' : '▶ Bruit brun (aide à se concentrer)', () => { Ob.brownNoise(!Ob.brownNoiseOn()); renderSettings(); })));
  f.append(h('fieldset', {}, h('legend', { text: '🧹 Mes données' }),
    h('p', { class: 'muted small', text: 'Tout est enregistré sur ce téléphone uniquement. Pour une sauvegarde : ☰ Plus > 💻 PC ↔ téléphone.' }),
    btn('Tout effacer', async () => {
      if (await askConfirm('Effacer toutes les données d’Orbit sur ce téléphone ?', 'Oui, tout effacer') && await askConfirm('Vraiment ? (tableaux, notes, reprises, victoires…)', 'Effacer')) {
        S = St.defaultState(); commit(); toast('Données effacées');
      }
    })));
}

// =========================================================================================
//  💻 Echange avec Orbit PC
// =========================================================================================
const BACKUP_KEY = 'orbit.avant-import';
const DESKTOP_FILES = ['kanban.json', 'notes.json', 'reprises.json', 'lifeanchor.json'];
async function importZip(file) {
  try {
    const files = await readZip(await file.arrayBuffer(), DESKTOP_FILES);
    if (!Object.keys(files).length) { toast("Ce zip ne contient pas de données d'Orbit"); return; }
    const next = St.fromDesktopFiles(S, files);
    const what = [`${next.kanban.cards.length} carte(s)`, `${next.notes.length} note(s)`, `${next.reprises.length} reprise(s)`].join(', ');
    if (!(await askConfirm(`Remplacer les données du téléphone par celles du zip ?\n${what}`, 'Remplacer'))) return;
    try { localStorage.setItem(BACKUP_KEY, JSON.stringify(S)); } catch { /* pas de place : tant pis pour la copie */ }
    S = St.normalizeState(next);
    St.migrateAnchor(S);
    commit();
    toast('📥 Données du PC récupérées ✓', { label: 'Annuler', run: undoImport }, 8);
  } catch (e) { toast(`Import impossible : ${St.shortText(e.message || 'fichier illisible', 60)}`); }
}
function undoImport() {
  const raw = localStorage.getItem(BACKUP_KEY);
  if (!raw) return;
  try { S = St.normalizeState(JSON.parse(raw)); localStorage.removeItem(BACKUP_KEY); commit(); toast('↩ Retour à avant l’import'); } catch { toast('Copie illisible'); }
}
async function exportZip() {
  const files = St.toDesktopFiles(S);
  const manifest = { from: '', date: St.isoLocal(), files: Object.keys(files).length, computer: 'Téléphone (Orbit mobile)' };
  const zipFiles = { 'donnees/orbit-export.json': JSON.stringify(manifest, null, 2) };
  for (const [k, v] of Object.entries(files)) zipFiles[`donnees/${k}`] = v;
  const blob = new Blob([writeZip(zipFiles)], { type: 'application/zip' });
  const name = `Orbit-telephone-${St.dayString()}.zip`;
  const f = new File([blob], name, { type: 'application/zip' });
  if (navigator.canShare && navigator.canShare({ files: [f] })) {
    try { await navigator.share({ files: [f], title: name }); return; } catch (e) { if (e && e.name === 'AbortError') return; }
  }
  const url = URL.createObjectURL(blob);
  const a = h('a', { href: url, download: name });
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
  toast('💾 Zip enregistré dans tes téléchargements');
}

// =========================================================================================
//  Dictee (micro)
// =========================================================================================
function micButton(target) {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  return btn('🎙', () => {
    if (!SR) { toast('Dictée : utilise le micro 🎙 de ton clavier'); target.focus(); return; }
    try {
      const rec = new SR();
      rec.lang = 'fr-FR'; rec.interimResults = false; rec.maxAlternatives = 1;
      rec.onresult = (e) => { const t = St.cleanText(e.results[0][0].transcript, 2000); target.value = (target.value ? `${target.value.trimEnd()} ` : '') + t; target.dispatchEvent(new Event('input')); };
      rec.onerror = () => toast('Je n’ai pas entendu… réessaie, ou utilise le micro du clavier');
      rec.start();
      toast('🎙 Je t’écoute…', null, 3);
    } catch { toast('Dictée indisponible ici : utilise le micro du clavier'); }
  }, 'btn', { 'aria-label': 'Dicter' });
}

// =========================================================================================
//  Rendu general
// =========================================================================================
function render() {
  const open = St.openReprises(S).length;
  $('tileReprises').textContent = open ? `Reprises (${open})` : 'Reprises';
  $('undoImport').classList.toggle('hidden', !localStorage.getItem(BACKUP_KEY));
  if (view === 'home') renderHome();
  else if (view === 'journal') renderJournal();
  else if (view === 'kanban') renderKanban();
  else if (view === 'notes') renderNotes();
  else if (view === 'reprises') renderReprises();
  else if (view === 'search') renderSearch();
  else if (view === 'settings') renderSettings();
  else renderClock();
  if (modal === 'focus' && S.anchor.unstick && $('runnerRing')) renderRunnerTimer();
}

// --- evenements fixes --------------------------------------------------------------------
for (const b of document.querySelectorAll('.tabbar button')) b.addEventListener('click', () => go(b.dataset.tab));
for (const b of document.querySelectorAll('[data-go]')) b.addEventListener('click', () => go(b.dataset.go));
$('goHome').addEventListener('click', () => go('home'));
$('openSearch').addEventListener('click', () => go('search'));
$('sosBtn').addEventListener('click', openSos);
$('noteFab').addEventListener('click', () => openNote());
$('ctxBadge').addEventListener('click', () => openInterrupt());
$('dockNote').addEventListener('click', () => openNote());
$('dockWins').addEventListener('click', () => go('journal'));
$('dockReprises').addEventListener('click', () => go('reprises'));
$('dockPlan').addEventListener('click', () => showMorningPlan(true));
$('ctxNew').addEventListener('click', () => openInterrupt());
$('noteNew').addEventListener('click', () => openNote());
$('boardMenu').addEventListener('click', boardMenu);
$('boardPick').addEventListener('change', (e) => { S.kanban.current = e.target.value; commit(); });
$('searchInput').addEventListener('input', renderSearch);
$('exportZip').addEventListener('click', exportZip);
$('undoImport').addEventListener('click', undoImport);
$('importZip').addEventListener('change', (e) => { const f = e.target.files[0]; e.target.value = ''; if (f) importZip(f); });
$('orbitBot').addEventListener('click', () => {
  if (bubbleHasQuestion()) return;
  const rep = St.latestOpenReprise(S, 12);
  const pausedOrIdle = S.timer.state === 'Idle' || S.timer.paused;
  if (rep && pausedOrIdle && !(offeredAt[rep.id] && Date.now() - offeredAt[rep.id] < 15 * 60000)) { showResumeBubble(rep); return; }
  const t = S.timer;
  if (t.state === 'Focus') bubble(`Encore ${Math.ceil(St.timeLeft(S) / 60000)} min de focus. ${Ob.pick(Ob.LINES.motivation)}`);
  else if (t.state === 'Break') bubble(`Encore ${Math.ceil(St.timeLeft(S) / 60000)} min de pause, profite 😌`);
  else if (t.state === 'AwaitBreak') askBreak();
  else if (t.state === 'AwaitFocus') askFocus();
  else bubble(Ob.pick(Ob.LINES.hello), [{ label: '🚀 Focus', run: startFocus, primary: true }, { label: '🚨 Je bloque', run: openSos }, { label: '📝 Note rapide', run: () => openNote() }]);
});
Ob.followPointer($('orbitBot'), [$('eyeL'), $('eyeR')]);

// retour dans l'appli apres une absence : « Où j'en étais ? »
let hiddenAt = 0;
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') { hiddenAt = Date.now(); updateWakeLock(); return; }
  const away = hiddenAt ? Date.now() - hiddenAt : 0;
  hiddenAt = 0;
  loop();
  updateWakeLock();
  if (away >= 120000 && !modal && !bubbleHasQuestion()) {
    const rep = St.latestOpenReprise(S, 12);
    if (rep && !(offeredAt[rep.id] && Date.now() - offeredAt[rep.id] < 30 * 60000)) showResumeBubble(rep);
  }
});

// installation sur l'ecran d'accueil
let installEvt = null;
window.addEventListener('beforeinstallprompt', (e) => { e.preventDefault(); installEvt = e; $('installBtn').classList.remove('hidden'); });
$('installBtn').addEventListener('click', async () => { if (!installEvt) return; installEvt.prompt(); await installEvt.userChoice.catch(() => {}); installEvt = null; $('installBtn').classList.add('hidden'); });

if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});

// --- demarrage --------------------------------------------------------------------------
St.pruneReprises(S);
history.replaceState({ v: 'home' }, '', location.pathname + location.search);
const params = new URLSearchParams(location.search);
history.replaceState({ v: 'home' }, '', location.pathname);
go('home', false);
const startEvent = St.tick(S);
if (startEvent) { save(); onTimerEvent(startEvent, true); }
scheduleEnd();
updateWakeLock();
setInterval(loop, 1000);
// ouverture depuis « Partager » ou un raccourci de l'icone
const shared = [params.get('share_title'), params.get('share_text'), params.get('share_url')].filter(Boolean).join(' ');
const action = params.get('action');
if (shared) {
  const url = St.safeUrl(params.get('share_url')) || St.findUrl(shared);
  const title = St.cleanText(params.get('share_title') || (params.get('share_text') || '').replace(url, '').trim(), 200);
  openInterrupt({ url, title, fromShare: true });
} else if (action === 'interrupt') openInterrupt();
else if (action === 'note' || action === 'dump') openNote();
else if (action === 'sos') openSos();
else if (action === 'focus' && S.timer.state === 'Idle') startFocus();
else if (migrated) {
  bubble(`Le Brain Dump et la DopaList ont été retirés. Rien n'est perdu : ${migrated.notes} idée(s) sont devenues des notes 📝 et ${migrated.cards} action(s) ou routine(s) des cartes 🗂.`, [], { seconds: 12 });
} else if (!startEvent) {
  const rep = St.latestOpenReprise(S, 12);
  if (rep) showResumeBubble(rep);
  else setTimeout(() => { if (view === 'home' && !modal && !bubbleHasQuestion()) { if (S.settings.morningPlan && S.timer.state === 'Idle' && new Date().getHours() >= 5 && S.stats.planDay !== St.dayString()) showMorningPlan(false); else bubble(Ob.pick(Ob.LINES.hello), [], { seconds: 6, silent: true }); } }, 400);
}
// pour les tests automatiques (lecture seule de l'etat)
Object.defineProperty(window, '__orbit', { value: Object.freeze({ state: () => JSON.parse(JSON.stringify(S)) }) });

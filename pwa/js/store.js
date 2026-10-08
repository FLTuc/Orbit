// Orbit (telephone) : les donnees et toute la logique, sans interface.
// Memes formats que la version PC (kanban.json, notes.json, reprises.json) pour passer
// de l'un a l'autre. Tout ce qui est lu (stockage du telephone, fichier importe, lien
// partage) est verifie ici : identifiants, adresses web, longueurs, types.
'use strict';

export const SAFE_ID = /^[A-Za-z0-9_-]{1,64}$/;
export const STORAGE_KEY = 'orbit.v1';
export const RHYTHMS = { '50/10': [50, 10], '25/5': [25, 5] };
export const LIMITS = { boards: 50, columns: 20, cards: 3000, checks: 100, notes: 2000, reprises: 200, text: 300, long: 20000 };

// --- petites fonctions ------------------------------------------------------
export function newId() {
  if (globalThis.crypto && crypto.randomUUID) return crypto.randomUUID().replace(/-/g, '');
  let s = '';
  for (let i = 0; i < 32; i++) s += Math.floor(Math.random() * 16).toString(16);
  return s;
}
export function safeId(v) { return typeof v === 'string' && SAFE_ID.test(v) ? v : newId(); }
export function isSafeId(v) { return typeof v === 'string' && SAFE_ID.test(v); }

// texte affichable : sans caracteres de controle ni moitie d'emoji, longueur bornee
export function cleanText(v, max = LIMITS.text) {
  if (v === null || v === undefined) return '';
  let s = String(v)
    .replace(/\r\n?/g, '\n')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u200B\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF\uFFFD]/g, '')
    .replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/g, '');
  if (s.length > max) s = shortText(s, max);
  return s;
}

// coupe sans jamais casser un emoji en deux
export function shortText(v, max = 60) {
  const s = String(v ?? '').replace(/\s+/g, ' ').trim();
  const chars = Array.from(s);
  if (chars.length <= max) return s;
  return chars.slice(0, Math.max(0, max - 1)).join('').replace(/[\u200D\uFE0E\uFE0F\u20E3]+$/, '') + '…';
}

export function limitPrio(p) {
  const n = parseInt(p, 10);
  if (Number.isNaN(n)) return 5;
  return Math.min(10, Math.max(1, n));
}

// Adresse web : seulement http(s), sans caractere qui pourrait servir a autre chose.
// Les navigateurs du telephone cachent souvent « https:// » : on le remet.
export function safeUrl(v) {
  let u = String(v ?? '').trim().replace(/ /g, '%20');
  if (!u || u.length > 2048) return '';
  if (!/^[A-Za-z][A-Za-z0-9+.-]*:/.test(u) && /^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d{1,5})?([/?#]|$)/.test(u)) u = 'https://' + u;
  return /^https?:\/\/[^\s"'<>`^{}|\\]+$/.test(u) ? u : '';
}

// premiere adresse web trouvee dans un texte partage
export function findUrl(text) {
  const m = String(text ?? '').match(/https?:\/\/[^\s"'<>`^{}|\\]+/);
  return m ? safeUrl(m[0]) : '';
}

const FOLD = { 'œ': 'oe', 'æ': 'ae', 'ß': 'ss' };
export function searchKey(v) {
  return String(v ?? '').toLowerCase().replace(/[œæß]/g, (c) => FOLD[c]).replace(/\u2019/g, "'")
    .normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ').trim();
}
export function matches(haystack, words) {
  const h = searchKey(haystack);
  return words.every((w) => h.includes(w));
}

const pad = (n) => String(n).padStart(2, '0');
// meme format de date que la version PC : 2026-10-07T15:04:05 (heure locale)
export function isoLocal(d = new Date()) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}
export function dayString(d = new Date()) { return isoLocal(d).slice(0, 10); }
function isoOrEmpty(v) {
  const s = String(v ?? '');
  return /^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2})?)?/.test(s) ? s.slice(0, 19) : '';
}
function dayOrEmpty(v) { const s = isoOrEmpty(v); return s ? s.slice(0, 10) : ''; }
export function parseLocal(iso) {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?)?/.exec(String(iso ?? ''));
  if (!m) return null;
  return new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 0), +(m[5] || 0), +(m[6] || 0));
}

export function formatAgo(iso, now = new Date()) {
  const d = parseLocal(iso);
  if (!d) return '';
  const min = (now - d) / 60000;
  if (min < 1) return "à l'instant";
  if (min < 60) return `il y a ${Math.floor(min)} min`;
  const hm = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  if (dayString(d) === dayString(now)) return `à ${hm}`;
  const y = new Date(now); y.setDate(y.getDate() - 1);
  if (dayString(d) === dayString(y)) return `hier à ${hm}`;
  return `le ${pad(d.getDate())}/${pad(d.getMonth() + 1)} à ${hm}`;
}

export function formatDue(day, now = new Date()) {
  if (!day) return '';
  const d = parseLocal(day);
  if (!d) return '';
  const diff = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(now.getFullYear(), now.getMonth(), now.getDate())) / 86400000);
  if (diff < 0) return `en retard (${pad(d.getDate())}/${pad(d.getMonth() + 1)})`;
  if (diff === 0) return "aujourd'hui";
  if (diff === 1) return 'demain';
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`;
}

// --- melange sans repetition (blagues, culture G) ------------------------------
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export function permutation(n, seed) {
  const p = Array.from({ length: n }, (_, i) => i);
  const r = mulberry32(seed);
  for (let i = n - 1; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [p[i], p[j]] = [p[j], p[i]]; }
  return p;
}
// prend l'element suivant ; quand tout est passe, nouveau melange
export function nextItem(list, stats, seedKey, posKey) {
  if (!list.length) return '';
  if (!stats[seedKey] || stats[posKey] >= list.length) { stats[seedKey] = 1 + Math.floor(Math.random() * 2e9); stats[posKey] = 0; }
  const idx = permutation(list.length, stats[seedKey])[stats[posKey]];
  stats[posKey]++;
  return list[idx];
}

// --- etat complet ------------------------------------------------------------
export function newColumn(name, done = false) { return { id: newId(), name, done }; }
export function newBoard(name) {
  return { id: newId(), name, columns: [newColumn('À faire'), newColumn('En cours'), newColumn('Terminé', true)] };
}

export function defaultSettings() {
  return {
    rhythm: '50/10', customFocus: 40, customBreak: 8,
    jokes: true, breakContent: 'Both', motivation: true,
    sounds: true, vibrate: true, wakeLock: false, notifications: false,
    taskReminders: true, morningPlan: true, idleNudge: true, idleNudgeMin: 45,
    ctxButton: true, ctxRemind: true, ctxRemindMin: 30,
  };
}

export function defaultState() {
  const b = newBoard('Mon tableau');
  return {
    version: 1,
    settings: defaultSettings(),
    timer: { state: 'Idle', endsAt: 0, paused: false, remainingMs: 0, sessionMin: 0 },
    stats: { date: dayString(), focus: 0, minutes: 0, jokeSeed: 0, jokePos: 0, factSeed: 0, factPos: 0, planDay: '' },
    kanban: { current: b.id, boards: [b], cards: [], focus: [], upcoming: [], templates: [] },
    notes: [],
    reprises: [],
    anchor: defaultAnchor(),
  };
}

const bool = (v) => v === true;
const num = (v, min, max, def) => { const n = Number(v); return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : def; };

export function sanitizeSettings(s) {
  const d = defaultSettings();
  if (!s || typeof s !== 'object') return d;
  const out = { ...d };
  for (const k of Object.keys(d)) {
    if (typeof d[k] === 'boolean' && typeof s[k] === 'boolean') out[k] = s[k];
  }
  if (['50/10', '25/5', 'Perso'].includes(s.rhythm)) out.rhythm = s.rhythm;
  out.customFocus = num(s.customFocus, 1, 240, d.customFocus);
  out.customBreak = num(s.customBreak, 1, 120, d.customBreak);
  if (['Both', 'Jokes', 'Culture'].includes(s.breakContent)) out.breakContent = s.breakContent;
  out.ctxRemindMin = num(s.ctxRemindMin, 5, 480, d.ctxRemindMin);
  out.idleNudgeMin = num(s.idleNudgeMin, 10, 240, d.idleNudgeMin);
  return out;
}

function sanitizeChecks(list) {
  const out = [];
  for (const c of Array.isArray(list) ? list : []) {
    if (!c || typeof c !== 'object') continue;
    const text = cleanText(c.text);
    if (text) out.push({ text, done: bool(c.done) });
    if (out.length >= LIMITS.checks) break;
  }
  return out;
}

export function sanitizeCard(t, board, col, order) {
  return {
    id: safeId(t.id), text: cleanText(t.text) || 'Sans titre', desc: cleanText(t.desc, LIMITS.long), prio: limitPrio(t.prio),
    due: dayOrEmpty(t.due), remindAt: isoOrEmpty(t.remindAt), reminded: bool(t.reminded),
    done: bool(t.done), created: isoOrEmpty(t.created) || isoLocal(), doneAt: isoOrEmpty(t.doneAt),
    board, col, order: num(order, -1e9, 1e9, 0),
    pomos: Math.floor(num(t.pomos, 0, 1e6, 0)), focusMin: Math.floor(num(t.focusMin, 0, 1e8, 0)), lastFocus: isoOrEmpty(t.lastFocus),
    checks: sanitizeChecks(t.checks), repeat: ['', 'workdays', 'weekdays', 'daily', 'weekly', 'biweekly', 'monthly'].includes(t.repeat) ? t.repeat : '',
    spawned: bool(t.spawned),
  };
}

// kanban.json (PC ou telephone) : tout est reverifie, ce qui est incomprehensible est ignore
export function sanitizeKanban(data) {
  const out = { current: '', boards: [], cards: [], focus: [], upcoming: [], templates: [] };
  const d = data && typeof data === 'object' ? data : {};
  const seenIds = new Set();
  for (const b of Array.isArray(d.boards) ? d.boards : []) {
    if (!b || !isSafeId(b.id) || seenIds.has(b.id) || out.boards.length >= LIMITS.boards) continue;
    const cols = [];
    for (const c of Array.isArray(b.columns) ? b.columns : []) {
      if (c && isSafeId(c.id) && !seenIds.has(c.id) && cols.length < LIMITS.columns) {
        seenIds.add(c.id);
        cols.push({ id: c.id, name: cleanText(c.name, 60) || 'Colonne', done: bool(c.done) });
      }
    }
    if (!cols.length) continue;
    seenIds.add(b.id);
    out.boards.push({ id: b.id, name: cleanText(b.name, 60) || 'Tableau', columns: cols });
  }
  if (!out.boards.length) out.boards.push(newBoard('Mon tableau'));
  out.current = out.boards.some((b) => b.id === d.current) ? d.current : out.boards[0].id;
  const cardIds = new Set();
  for (const t of Array.isArray(d.cards) ? d.cards : []) {
    if (!t || typeof t !== 'object' || out.cards.length >= LIMITS.cards) continue;
    const b = out.boards.find((x) => x.id === t.board);
    if (!b) continue;
    let col = b.columns.find((c) => c.id === t.col);
    if (!col) col = b.columns.find((c) => !c.done) || b.columns[0];
    const card = sanitizeCard(t, b.id, col.id, t.order);
    if (cardIds.has(card.id)) card.id = newId();
    cardIds.add(card.id);
    card.done = col.done;
    out.cards.push(card);
  }
  out.focus = (Array.isArray(d.focus) ? d.focus : []).filter((id) => isSafeId(id) && cardIds.has(id));
  // cartes recurrentes a venir et modeles : geres par la version PC, gardes tels quels (verifies)
  out.upcoming = (Array.isArray(d.upcoming) ? d.upcoming : []).filter((u) => u && typeof u === 'object').slice(0, 500)
    .map((u) => Object.assign(sanitizeCard(u, isSafeId(u.board) ? u.board : '', '', 0), { showAt: dayOrEmpty(u.showAt) }))
    .filter((u) => u.showAt);
  out.templates = (Array.isArray(d.templates) ? d.templates : []).filter((m) => m && typeof m === 'object' && m.name).slice(0, 200)
    .map((m) => ({ name: cleanText(m.name, 60), text: cleanText(m.text), desc: cleanText(m.desc, LIMITS.long), prio: limitPrio(m.prio), checks: sanitizeChecks(m.checks), repeat: ['', 'workdays', 'weekdays', 'daily', 'weekly', 'biweekly', 'monthly'].includes(m.repeat) ? m.repeat : '' }));
  return out;
}

export function sanitizeNotes(list) {
  const out = [];
  const ids = new Set();
  for (const n of Array.isArray(list) ? list : []) {
    if (!n || typeof n !== 'object' || out.length >= LIMITS.notes) continue;
    const text = cleanText(n.text, LIMITS.long);
    if (!text.trim()) continue;
    let id = safeId(n.id);
    if (ids.has(id)) id = newId();
    ids.add(id);
    const updated = isoOrEmpty(n.updated) || isoOrEmpty(n.created) || isoLocal();
    out.push({ id, text, created: isoOrEmpty(n.created) || updated, updated, pinned: bool(n.pinned) });
  }
  return out;
}

function sanitizeWindow(w) {
  const priv = bool(w.private);
  return {
    app: String(w.app ?? '').replace(/[^A-Za-z0-9_.-]/g, '').toLowerCase().slice(0, 40),
    title: priv ? 'Fenêtre de navigation privée' : cleanText(w.title, 200),
    url: priv ? '' : safeUrl(w.url),
    // un chemin de fichier n'a pas de sens sur le telephone : garde tel quel pour la version PC, jamais ouvert ici
    path: priv ? '' : cleanText(w.path, 400).replace(/["<>|*?]/g, ''),
    hwnd: 0, pid: 0, private: priv,
  };
}

export function sanitizeReprises(list) {
  const out = [];
  const ids = new Set();
  for (const c of Array.isArray(list) ? list : []) {
    if (!c || typeof c !== 'object' || out.length >= LIMITS.reprises) continue;
    let id = safeId(c.id);
    if (ids.has(id)) id = newId();
    ids.add(id);
    out.push({
      id, created: isoOrEmpty(c.created) || isoLocal(), status: c.status === 'done' ? 'done' : 'open', doneAt: isoOrEmpty(c.doneAt),
      doing: cleanText(c.doing, 2000), next: cleanText(c.next, 2000),
      windows: (Array.isArray(c.windows) ? c.windows : []).filter((w) => w && typeof w === 'object').slice(0, 10).map(sanitizeWindow),
      focusCards: (Array.isArray(c.focusCards) ? c.focusCards : []).filter(isSafeId).slice(0, 50),
      wasFocus: bool(c.wasFocus), focusLeftMin: num(c.focusLeftMin, 0, 1000, 0),
      remindAt: isoOrEmpty(c.remindAt), reminders: Math.floor(num(c.reminders, 0, 100, 0)),
    });
  }
  return out;
}

export function normalizeState(raw) {
  const d = defaultState();
  if (!raw || typeof raw !== 'object') return d;
  const s = {
    version: 1,
    settings: sanitizeSettings(raw.settings),
    timer: d.timer,
    stats: d.stats,
    kanban: sanitizeKanban(raw.kanban),
    notes: sanitizeNotes(raw.notes),
    reprises: sanitizeReprises(raw.reprises),
    anchor: sanitizeAnchor(raw.anchor),
  };
  const t = raw.timer || {};
  if (['Idle', 'Focus', 'Break', 'AwaitBreak', 'AwaitFocus'].includes(t.state)) {
    s.timer = { state: t.state, endsAt: num(t.endsAt, 0, 1e15, 0), paused: bool(t.paused), remainingMs: num(t.remainingMs, 0, 864e5, 0), sessionMin: num(t.sessionMin, 0, 1000, 0) };
  }
  const st = raw.stats || {};
  s.stats = {
    date: dayOrEmpty(st.date) || dayString(), focus: Math.floor(num(st.focus, 0, 1e6, 0)), minutes: num(st.minutes, 0, 1e7, 0),
    jokeSeed: Math.floor(num(st.jokeSeed, 0, 4e9, 0)), jokePos: Math.floor(num(st.jokePos, 0, 1e6, 0)),
    factSeed: Math.floor(num(st.factSeed, 0, 4e9, 0)), factPos: Math.floor(num(st.factPos, 0, 1e6, 0)),
    planDay: dayOrEmpty(st.planDay),
  };
  return s;
}

// --- tableaux ---------------------------------------------------------------
export function getBoard(s, id) { return s.kanban.boards.find((b) => b.id === id); }
export function currentBoard(s) { return getBoard(s, s.kanban.current) || s.kanban.boards[0]; }
export function findCard(s, id) { return s.kanban.cards.find((t) => t.id === id); }
export function findColumn(s, colId) {
  for (const b of s.kanban.boards) { const c = b.columns.find((x) => x.id === colId); if (c) return { board: b, col: c }; }
  return null;
}
export function openColumn(b) { return b.columns.find((c) => !c.done) || b.columns[0]; }
export function doneColumn(b) { return b.columns.find((c) => c.done) || b.columns[b.columns.length - 1]; }
export function columnCards(s, colId) {
  return s.kanban.cards.filter((t) => t.col === colId).sort((a, b) => a.order - b.order || a.prio - b.prio);
}

// raccourcis du texte : « !2 » = priorite 2, « @14h » / « @14h30 » = rappel
export function parseShortcuts(text, now = new Date()) {
  let t = String(text ?? '').trim();
  let prio = null;
  let remindAt = '';
  const pr = /(^|\s)!(10|[1-9])(?=\s|$)/;
  const m1 = t.match(pr);
  if (m1) { prio = +m1[2]; t = t.replace(pr, ' ').replace(/\s{2,}/g, ' ').trim(); }
  const rx = /(^|\s)@([01]?\d|2[0-3])(?:h|:)([0-5]\d)?(?=\s|$)/;
  const m2 = t.match(rx);
  if (m2) {
    const at = new Date(now.getFullYear(), now.getMonth(), now.getDate(), +m2[2], m2[3] ? +m2[3] : 0, 0);
    if (at <= now) at.setDate(at.getDate() + 1);
    remindAt = isoLocal(at);
    t = t.replace(rx, ' ').replace(/\s{2,}/g, ' ').trim();
  }
  return { text: t, prio, remindAt };
}

export function addCard(s, rawText, colId = '', prio = 5) {
  const p = parseShortcuts(rawText);
  const text = cleanText(p.text);
  if (!text || s.kanban.cards.length >= LIMITS.cards) return null;
  let place = colId ? findColumn(s, colId) : null;
  if (!place) { const b = currentBoard(s); place = { board: b, col: openColumn(b) }; }
  const cards = columnCards(s, place.col.id);
  const card = sanitizeCard({ id: newId(), text, prio: p.prio ?? prio, remindAt: p.remindAt, created: isoLocal(), done: place.col.done },
    place.board.id, place.col.id, cards.length ? cards[cards.length - 1].order + 1 : 0);
  card.done = place.col.done;
  if (card.done) card.doneAt = isoLocal();
  s.kanban.cards.push(card);
  return card;
}

export function moveCard(s, id, colId) {
  const t = findCard(s, id);
  const place = findColumn(s, colId);
  if (!t || !place) return;
  const cards = columnCards(s, colId).filter((x) => x.id !== id);
  t.board = place.board.id;
  t.col = colId;
  t.order = cards.length ? cards[cards.length - 1].order + 1 : 0;
  const wasDone = t.done;
  t.done = place.col.done;
  if (t.done && !wasDone) { t.doneAt = isoLocal(); s.kanban.focus = s.kanban.focus.filter((x) => x !== id); }
  if (!t.done) t.doneAt = '';
}

export function setCardDone(s, id, done) {
  const t = findCard(s, id);
  if (!t) return;
  const b = getBoard(s, t.board);
  if (!b) return;
  moveCard(s, id, (done ? doneColumn(b) : openColumn(b)).id);
}

export function removeCard(s, id) {
  s.kanban.cards = s.kanban.cards.filter((t) => t.id !== id);
  s.kanban.focus = s.kanban.focus.filter((x) => x !== id);
}

export function focusCards(s, openOnly = false) {
  return s.kanban.focus.map((id) => findCard(s, id)).filter((t) => t && (!openOnly || !t.done));
}
export function setCardFocus(s, id, on) {
  const t = findCard(s, id);
  if (!t) return;
  s.kanban.focus = s.kanban.focus.filter((x) => x !== id);
  if (on && !t.done) s.kanban.focus.push(id);
}

// au debut d'un focus, une carte encore dans la 1re colonne passe dans « En cours »
export function moveToDoing(s, t) {
  const b = getBoard(s, t.board);
  if (!b || t.done || t.col !== openColumn(b).id) return;
  const doing = b.columns.find((c) => !c.done && /^\s*en\s*cours/i.test(c.name));
  if (doing && doing.id !== t.col) moveCard(s, t.id, doing.id);
}

// Plan du matin : les cartes les plus urgentes, tous tableaux confondus, avec la raison
export function planCards(s, n = 3, now = new Date()) {
  const today = dayString(now);
  const tomorrow = dayString(new Date(now.getTime() + 86400000));
  const scored = [];
  for (const t of s.kanban.cards) {
    if (t.done) continue;
    let score = (11 - t.prio) * 10;
    let why = '';
    if (t.due && t.due < today) { score += 400; why = `📅 en retard (${formatDue(t.due, now)})`; }
    else if (t.due === today) { score += 300; why = "📅 à rendre aujourd'hui"; }
    else if (t.due === tomorrow) { score += 200; why = '📅 à rendre demain'; }
    if (t.remindAt && t.remindAt.slice(0, 10) === today) { score += 150; why = why || `⏰ rappel à ${t.remindAt.slice(11, 16)}`; }
    if (s.kanban.focus.includes(t.id)) { score += 60; why = why || '🎯 déjà liée au focus'; }
    const b = getBoard(s, t.board);
    if (b && t.col !== openColumn(b).id) { score += 40; why = why || '▶ déjà commencée'; }
    if (t.pomos) score += 10;
    scored.push({ card: t, score, why });
  }
  scored.sort((a, b) => b.score - a.score || a.card.prio - b.card.prio);
  return scored.slice(0, n);
}

// --- chrono -----------------------------------------------------------------
export function rhythmMinutes(settings) {
  if (settings.rhythm === 'Perso') return [settings.customFocus, settings.customBreak];
  return RHYTHMS[settings.rhythm] || RHYTHMS['50/10'];
}
export function timeLeft(s, now = Date.now()) {
  const t = s.timer;
  if (t.state !== 'Focus' && t.state !== 'Break') return 0;
  return Math.max(0, t.paused ? t.remainingMs : t.endsAt - now);
}
export function startFocus(s, now = Date.now()) {
  const [f] = rhythmMinutes(s.settings);
  s.timer = { state: 'Focus', endsAt: now + f * 60000, paused: false, remainingMs: 0, sessionMin: f };
  s.kanban.focus = s.kanban.focus.filter((id) => { const t = findCard(s, id); return t && !t.done; });
  if (!s.kanban.focus.length && s.settings.taskReminders) {
    const first = planCards(s, 1)[0];
    if (first) s.kanban.focus.push(first.card.id);
  }
  for (const t of focusCards(s, true)) moveToDoing(s, t);
}
export function startBreak(s, now = Date.now()) {
  const [, b] = rhythmMinutes(s.settings);
  s.timer = { state: 'Break', endsAt: now + b * 60000, paused: false, remainingMs: 0, sessionMin: b };
}
export function pauseTimer(s, now = Date.now()) {
  const t = s.timer;
  if ((t.state === 'Focus' || t.state === 'Break') && !t.paused) { t.remainingMs = Math.max(0, t.endsAt - now); t.paused = true; }
}
export function resumeTimer(s, now = Date.now()) {
  const t = s.timer;
  if ((t.state === 'Focus' || t.state === 'Break') && t.paused) { t.endsAt = now + t.remainingMs; t.paused = false; }
}
export function stopTimer(s) { s.timer = { state: 'Idle', endsAt: 0, paused: false, remainingMs: 0, sessionMin: 0 }; }

function rollStats(s, now) {
  const d = dayString(now);
  if (s.stats.date !== d) { s.stats.date = d; s.stats.focus = 0; s.stats.minutes = 0; }
}

// Avance le chrono. Renvoie 'focusEnded', 'breakEnded' ou ''.
export function tick(s, now = Date.now()) {
  const t = s.timer;
  if ((t.state !== 'Focus' && t.state !== 'Break') || t.paused || now < t.endsAt) return '';
  if (t.state === 'Focus') {
    const nowD = new Date(now);
    rollStats(s, nowD);
    s.stats.focus++;
    s.stats.minutes += t.sessionMin;
    for (const c of focusCards(s)) { c.pomos++; c.focusMin += Math.round(t.sessionMin); c.lastFocus = isoLocal(nowD); }
    s.timer = { state: 'AwaitBreak', endsAt: 0, paused: false, remainingMs: 0, sessionMin: t.sessionMin };
    return 'focusEnded';
  }
  s.timer = { state: 'AwaitFocus', endsAt: 0, paused: false, remainingMs: 0, sessionMin: 0 };
  return 'breakEnded';
}

// --- notes --------------------------------------------------------------------
export function sortedNotes(s) {
  return [...s.notes].sort((a, b) => (b.pinned - a.pinned) || (a.updated < b.updated ? 1 : a.updated > b.updated ? -1 : 0));
}
export function addNote(s, text) {
  const t = cleanText(text, LIMITS.long).trim();
  if (!t || s.notes.length >= LIMITS.notes) return null;
  const now = isoLocal();
  const n = { id: newId(), text: t, created: now, updated: now, pinned: false };
  s.notes.unshift(n);
  return n;
}
export function updateNote(s, id, text) {
  const n = s.notes.find((x) => x.id === id);
  if (!n) return;
  const t = cleanText(text, LIMITS.long).trim();
  if (!t) { s.notes = s.notes.filter((x) => x.id !== id); return; }
  if (n.text !== t) { n.text = t; n.updated = isoLocal(); }
}
export function noteTitle(n, max = 60) {
  const first = String(n.text).split('\n').find((l) => l.trim()) || '';
  return shortText(first.trim(), max);
}
export function noteToCard(s, id) {
  const n = s.notes.find((x) => x.id === id);
  if (!n) return null;
  const lines = n.text.split('\n');
  let i = 0;
  while (i < lines.length && !lines[i].trim()) i++;
  const card = addCard(s, lines[i] || 'Note');
  if (!card) return null;
  card.desc = cleanText(lines.slice(i + 1).join('\n').trim(), LIMITS.long);
  s.notes = s.notes.filter((x) => x.id !== id);
  return card;
}

// --- reprises (« Je m'interromps ») ------------------------------------------
export function openReprises(s) {
  return s.reprises.filter((c) => c.status === 'open').sort((a, b) => (a.created < b.created ? 1 : -1));
}
export function latestOpenReprise(s, hours = 0, now = new Date()) {
  const c = openReprises(s)[0];
  if (!c) return null;
  if (hours > 0) { const d = parseLocal(c.created); if (!d || (now - d) / 3600000 > hours) return null; }
  return c;
}
export function suggestedNext(s) {
  for (const t of focusCards(s, true)) for (const ck of t.checks) if (!ck.done && ck.text) return ck.text;
  return '';
}
export function newReprise(s, { url = '', title = '', doing = '', next = '' } = {}) {
  return sanitizeReprises([{
    id: newId(), created: isoLocal(), status: 'open', doing, next,
    windows: (safeUrl(url) || title) ? [{ app: 'telephone', title: title || '', url }] : [],
    focusCards: focusCards(s, true).map((t) => t.id), wasFocus: s.timer.state === 'Focus',
    focusLeftMin: s.timer.state === 'Focus' ? Math.round(timeLeft(s) / 6000) / 10 : 0,
  }])[0];
}
export function addReprise(s, c, now = new Date()) {
  if (s.settings.ctxRemind) c.remindAt = isoLocal(new Date(now.getTime() + s.settings.ctxRemindMin * 60000));
  s.reprises.unshift(c);
  if (s.reprises.length > LIMITS.reprises) s.reprises.length = LIMITS.reprises;
}
export function completeReprise(s, id) {
  const c = s.reprises.find((x) => x.id === id);
  if (c) { c.status = 'done'; c.doneAt = isoLocal(); }
}
export function dueReprise(s, now = new Date()) {
  if (!s.settings.ctxRemind) return null;
  const iso = isoLocal(now);
  return openReprises(s).find((c) => c.remindAt && c.remindAt <= iso && c.reminders < 3) || null;
}
// reprises terminees depuis plus de 14 jours : oubliees
export function pruneReprises(s, now = new Date()) {
  const limit = isoLocal(new Date(now.getTime() - 14 * 86400000));
  s.reprises = s.reprises.filter((c) => !(c.status === 'done' && c.doneAt && c.doneAt < limit));
}
export function repriseTitle(c, max = 70) {
  if (c.next) return shortText(c.next, max);
  if (c.doing) return shortText(c.doing, max);
  const w = c.windows[0];
  if (w && w.title) return shortText(w.title, max);
  if (w && w.url) return shortText(w.url.replace(/^https?:\/\//, ''), max);
  return 'Reprise sans détail';
}
export function repriseToCard(s, id) {
  const c = s.reprises.find((x) => x.id === id);
  if (!c) return null;
  const card = addCard(s, repriseTitle(c, 140));
  if (!card) return null;
  const lines = [];
  if (c.doing) lines.push(`J'étais en train de : ${c.doing}`);
  if (c.next && c.doing) lines.push(`Prochaine étape : ${c.next}`);
  for (const w of c.windows) if (!w.private) lines.push(`${w.title || w.app}${w.url ? `\n   ${w.url}` : ''}`);
  card.desc = cleanText(lines.join('\n'), LIMITS.long);
  completeReprise(s, id);
  return card;
}

// --- recherche ------------------------------------------------------------------
export function searchAll(s, q) {
  const words = searchKey(q).split(' ').filter(Boolean);
  const r = { cards: [], notes: [], reprises: [] };
  if (!words.length) return r;
  r.cards = s.kanban.cards.filter((t) => matches(`${t.text} ${t.desc} ${t.checks.map((c) => c.text).join(' ')}`, words))
    .sort((a, b) => (a.done - b.done) || a.prio - b.prio);
  r.notes = s.notes.filter((n) => matches(n.text, words));
  r.reprises = s.reprises.filter((c) => matches(`${c.doing} ${c.next} ${c.windows.map((w) => `${w.title} ${w.url}`).join(' ')}`, words));
  return r;
}

// --- echange avec la version PC -------------------------------------------------------
// fichiers au format d'Orbit PC (dossier « donnees » d'un export)
export function toDesktopFiles(s) {
  return {
    'kanban.json': JSON.stringify(s.kanban, null, 2),
    'notes.json': JSON.stringify(s.notes, null, 2),
    'reprises.json': JSON.stringify(s.reprises, null, 2),
    'lifeanchor.json': JSON.stringify({ dump: [], tasks: [], wins: s.anchor.wins }, null, 2),
  };
}
// fichiers lus dans un export d'Orbit PC (ceux qui manquent : on garde l'existant)
export function fromDesktopFiles(s, files) {
  const out = JSON.parse(JSON.stringify(s));
  const read = (name) => {
    if (!(name in files)) return undefined;
    const txt = String(files[name]).replace(/^\uFEFF/, '');
    return JSON.parse(txt);
  };
  const k = read('kanban.json');
  if (k !== undefined) out.kanban = sanitizeKanban(k);
  const n = read('notes.json');
  if (n !== undefined) out.notes = sanitizeNotes(Array.isArray(n) ? n : [n]);
  const r = read('reprises.json');
  if (r !== undefined) out.reprises = sanitizeReprises(Array.isArray(r) ? r : [r]);
  const a = read('lifeanchor.json');
  if (a !== undefined) out.anchor = Object.assign(sanitizeAnchor(a), { unstick: out.anchor ? out.anchor.unstick : null });
  return out;
}

// =============================================================================
//  S.O.S / Unstick Me et journal des victoires
//  (meme fichier lifeanchor.json que la version PC ; « dump » et « tasks » ne sont plus
//  lus que pour convertir l'ancien Brain Dump et l'ancienne DopaList)
// =============================================================================
const REPEATS = { daily: 'chaque jour', weekdays: 'en semaine', weekly: 'chaque semaine' };

export function defaultAnchor() { return { dump: [], tasks: [], wins: [], unstick: null }; }

function sanitizeSteps(list) {
  return (Array.isArray(list) ? list : []).filter((x) => x && typeof x === 'object').slice(0, 12)
    .map((x) => ({ content: cleanText(x.content, 300), sec: Math.round(num(x.sec, 30, 900, 150)), done: bool(x.done) }))
    .filter((x) => x.content);
}

export function sanitizeAnchor(a) {
  const d = a && typeof a === 'object' ? a : {};
  const ids = new Set();
  const uid = (v) => { let id = safeId(v); if (ids.has(id)) id = newId(); ids.add(id); return id; };
  const out = defaultAnchor();
  out.dump = (Array.isArray(d.dump) ? d.dump : []).filter((x) => x && typeof x === 'object').slice(0, 1000)
    .map((x) => ({ id: uid(x.id), text: cleanText(x.text, 2000), created: isoOrEmpty(x.created) || isoLocal() }))
    .filter((x) => x.text.trim());
  out.tasks = (Array.isArray(d.tasks) ? d.tasks : []).filter((x) => x && typeof x === 'object').slice(0, 2000)
    .map((x) => ({
      id: uid(x.id), title: cleanText(x.title, 300) || 'Sans titre',
      status: ['todo', 'completed', 'archived'].includes(x.status) ? x.status : 'todo',
      isRoutine: bool(x.isRoutine), repeat: Object.keys(REPEATS).includes(x.repeat) ? x.repeat : (bool(x.isRoutine) ? 'daily' : ''),
      created: isoOrEmpty(x.created) || isoLocal(), completedAt: isoOrEmpty(x.completedAt), lastDone: dayOrEmpty(x.lastDone),
      steps: sanitizeSteps(x.steps),
    }));
  out.wins = (Array.isArray(d.wins) ? d.wins : []).filter((x) => x && typeof x === 'object').slice(-3000)
    .map((x) => ({ id: uid(x.id), title: cleanText(x.title, 200), kind: String(x.kind ?? '').replace(/[^a-z]/g, '').slice(0, 20) || 'task', at: isoOrEmpty(x.at) || isoLocal() }))
    .filter((x) => x.title);
  const u = d.unstick;
  if (u && typeof u === 'object') {
    const steps = sanitizeSteps(u.steps);
    if (steps.length) {
      out.unstick = { title: cleanText(u.title, 300), taskId: isSafeId(u.taskId) ? u.taskId : '', steps,
        index: Math.floor(num(u.index, 0, steps.length - 1, 0)), timerEndsAt: num(u.timerEndsAt, 0, 1e15, 0) };
    }
  }
  return out;
}

// --- journal des victoires -------------------------------------------------------
export function addWin(s, title, kind = 'task', now = new Date()) {
  const w = { id: newId(), title: cleanText(title, 200) || 'Une victoire', kind, at: isoLocal(now) };
  s.anchor.wins.push(w);
  const limit = isoLocal(new Date(now.getTime() - 60 * 86400000));
  s.anchor.wins = s.anchor.wins.filter((x) => x.at >= limit).slice(-3000);
  return w;
}
export function winsOfDay(s, now = new Date()) {
  const d = dayString(now);
  return s.anchor.wins.filter((w) => w.at.slice(0, 10) === d).sort((a, b) => (a.at < b.at ? 1 : -1));
}
// series de jours avec au moins une victoire (sans jamais compter « en retard »)
export function winStreak(s, now = new Date()) {
  const days = new Set(s.anchor.wins.map((w) => w.at.slice(0, 10)));
  let n = 0;
  const d = new Date(now);
  if (!days.has(dayString(d))) d.setDate(d.getDate() - 1);   // aujourd'hui pas encore commence : la serie tient
  while (days.has(dayString(d))) { n++; d.setDate(d.getDate() - 1); }
  return n;
}

// --- ancien Brain Dump / DopaList : rien n'est perdu ------------------------------------
// idees -> notes rapides, actions -> cartes, routines -> cartes qui se repetent (comme sur le PC)
// relance « Tu attends quoi ? » : aucun focus ni pause depuis idleNudgeMin minutes
// (« Pas aujourd'hui » = offDay, la date du jour ou on ne relance plus)
export function idleNudgeDue(settings, timerState, lastBusyMs, now = new Date(), offDay = '') {
  if (!settings.idleNudge || timerState !== 'Idle') return false;
  if (offDay === dayString(now)) return false;
  return now.getTime() - lastBusyMs >= settings.idleNudgeMin * 60000;
}

export function migrateAnchor(s) {
  let notes = 0, cards = 0;
  for (const d of s.anchor.dump) if (addNote(s, d.text)) notes++;
  for (const t of s.anchor.tasks.filter((x) => x.status === 'todo')) {
    const c = addCard(s, t.title);
    if (!c) continue;
    if (t.isRoutine) { c.repeat = t.repeat === 'weekdays' ? 'workdays' : t.repeat === 'weekly' ? 'weekly' : 'daily'; c.desc = 'Ancienne routine de la DopaList'; }
    cards++;
  }
  const had = s.anchor.dump.length + s.anchor.tasks.length > 0;
  s.anchor.dump = []; s.anchor.tasks = [];
  return had ? { notes, cards } : null;
}

// --- Unstick Me : decoupage local en micro-etapes ------------------------------------
export function decompose(text, rules) {
  const task = cleanText(text, 300).trim();
  if (!task) return [];
  const norm = ' ' + searchKey(task).replace(/[^a-z0-9' -]/g, ' ').replace(/\s+/g, ' ') + ' ';
  let obj = task;
  for (const v of (rules && rules.verbs) || []) {
    const m = searchKey(task);
    if (m.startsWith(v + ' ')) { obj = task.slice(v.length).trim(); break; }
  }
  obj = obj.replace(/^(le|la|les|l'|un|une|des|du|de|d'|mon|ma|mes|ton|ta|tes)\s*/i, '').trim() || task;
  let steps = (rules && rules.generic) || ['Commence « {x} » : la toute première action', 'Continue 2 minutes', 'Note où tu en es'];
  for (const r of (rules && rules.rules) || []) {
    if (r.keys.some((k) => norm.includes(' ' + searchKey(k)))) { steps = r.steps; break; }
  }
  return steps.slice(0, 5).map((x) => x.replace(/\{x\}/g, task).replace(/\{o\}/g, obj));
}

export function startUnstick(s, title, rules, taskId = '') {
  const steps = decompose(title, rules).map((content) => ({ content, sec: 150, done: false }));
  if (!steps.length) return null;
  s.anchor.unstick = { title: cleanText(title, 300), taskId: isSafeId(taskId) ? taskId : '', steps, index: 0, timerEndsAt: 0 };
  return s.anchor.unstick;
}
// etape faite : on passe a la suivante (renvoie 'next', 'finished' ou '')
export function unstickStepDone(s, now = new Date()) {
  const u = s.anchor.unstick;
  if (!u) return '';
  u.steps[u.index].done = true;
  u.timerEndsAt = 0;
  if (u.index < u.steps.length - 1) { u.index++; return 'next'; }
  addWin(s, `Débloqué : ${u.title}`, 'unstick', now);
  s.anchor.unstick = null;
  return 'finished';
}
export function unstickStartTimer(s, now = Date.now()) {
  const u = s.anchor.unstick;
  if (u) u.timerEndsAt = now + u.steps[u.index].sec * 1000;
}

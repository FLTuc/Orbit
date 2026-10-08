// Orbit (telephone) : le personnage (couleurs, chrono, yeux), les sons et les vibrations.
// Les sons sont fabriques par le telephone (Web Audio) : aucun fichier, aucun telechargement.
'use strict';

let ctx = null;
function audio() {
  // le navigateur n'autorise le son qu'apres un premier toucher de l'ecran
  if (!ctx && globalThis.navigator && navigator.userActivation && !navigator.userActivation.hasBeenActive) return null;
  if (!ctx) {
    const AC = globalThis.AudioContext || globalThis.webkitAudioContext;
    if (!AC) return null;
    ctx = new AC();
  }
  if (ctx.state === 'suspended') ctx.resume().catch(() => {});
  return ctx;
}

function tone(ac, freq, start, dur, vol, type = 'sine', glideTo = 0) {
  const o = ac.createOscillator();
  const g = ac.createGain();
  o.type = type;
  o.frequency.setValueAtTime(freq, start);
  if (glideTo) o.frequency.exponentialRampToValueAtTime(glideTo, start + dur);
  g.gain.setValueAtTime(0.0001, start);
  g.gain.exponentialRampToValueAtTime(vol, start + 0.015);
  g.gain.exponentialRampToValueAtTime(0.0001, start + dur);
  o.connect(g).connect(ac.destination);
  o.start(start);
  o.stop(start + dur + 0.05);
}

const SCALE = [523.25, 587.33, 659.25, 783.99, 880, 1046.5];
// petits bips de droide (la derniere note monte pour une question)
export function chirp(question = false, volume = 0.12) {
  const ac = audio();
  if (!ac) return;
  let t = ac.currentTime + 0.02;
  const n = 2 + Math.floor(Math.random() * 3);
  for (let i = 0; i < n; i++) {
    const f = SCALE[Math.floor(Math.random() * SCALE.length)];
    const last = i === n - 1;
    const d = last && question ? 0.17 : 0.07 + Math.random() * 0.06;
    tone(ac, f, t, d, volume, 'sine', last && question ? f * 1.33 : f * (0.9 + Math.random() * 0.25));
    t += d + 0.04;
  }
}
// carillon doux de fin de session (jamais strident)
export function chime(volume = 0.16) {
  const ac = audio();
  if (!ac) return;
  const t = ac.currentTime + 0.02;
  [659.25, 783.99, 1046.5].forEach((f, i) => tone(ac, f, t + i * 0.18, 0.9, volume, 'triangle'));
}
// « tic » court et doux du compte a rebours (plus aigu pour les 10 dernieres secondes)
export function tick(high = false, volume = 0.09) {
  const ac = audio();
  if (!ac) return;
  tone(ac, high ? 1568 : 1046.5, ac.currentTime + 0.01, 0.05, volume, 'sine');
}
// « ding » de victoire
export function success(volume = 0.14) {
  const ac = audio();
  if (!ac) return;
  const t = ac.currentTime + 0.02;
  tone(ac, 880, t, 0.12, volume, 'triangle');
  tone(ac, 1318.5, t + 0.09, 0.35, volume, 'triangle');
}

// bruit brun (ambiance pour se concentrer), en boucle
let noise = null;
export function brownNoise(on, volume = 0.18) {
  if (!on) {
    if (noise) { try { noise.src.stop(); } catch { /* deja arrete */ } noise = null; }
    return false;
  }
  if (noise) return true;
  const ac = audio();
  if (!ac) return false;
  const len = ac.sampleRate * 4;
  const buf = ac.createBuffer(1, len, ac.sampleRate);
  const d = buf.getChannelData(0);
  let last = 0;
  for (let i = 0; i < len; i++) {
    last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02;
    d[i] = last * 3.5;
  }
  // fondu pour une boucle sans clic
  for (let i = 0; i < 2000; i++) { const k = i / 2000; d[i] *= k; d[len - 1 - i] *= k; }
  const src = ac.createBufferSource();
  src.buffer = buf;
  src.loop = true;
  const g = ac.createGain();
  g.gain.value = volume;
  src.connect(g).connect(ac.destination);
  src.start();
  noise = { src, g };
  return true;
}
export function brownNoiseOn() { return !!noise; }

export function vibrate(pattern) {
  try { if (navigator.vibrate) navigator.vibrate(pattern); } catch { /* pas de vibreur */ }
}

// --- le personnage ------------------------------------------------------------------
export function setMood(el, mood) {
  if (!el) return;
  el.classList.remove('mood-Idle', 'mood-Focus', 'mood-Break', 'mood-Await');
  el.classList.add(`mood-${mood}`);
}

// les yeux suivent le doigt (ou la souris)
export function followPointer(bot, eyes) {
  const move = (x, y) => {
    const r = bot.getBoundingClientRect();
    const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    const dx = x - cx, dy = y - cy;
    const len = Math.hypot(dx, dy) || 1;
    const k = Math.min(3.5, len / 40);
    for (const e of eyes) e.style.transform = `translate(${(dx / len) * k}px, ${(dy / len) * k}px)`;
  };
  globalThis.addEventListener('pointermove', (e) => move(e.clientX, e.clientY), { passive: true });
  globalThis.addEventListener('pointerdown', (e) => move(e.clientX, e.clientY), { passive: true });
}

// --- textes d'Orbit -------------------------------------------------------------------
export const LINES = {
  hello: ["Salut ! On attaque quoi aujourd'hui ? 🚀", 'Me revoilà 🛰 Prêt(e) pour un focus ?', 'Hello ! Une chose à la fois, on y va doucement 😊'],
  focusStart: ['Focus lancé : {0} min ! Je garde le temps pour toi ⏱', "C'est parti pour {0} min. Une seule chose à la fois 🎯", 'Go ! {0} min de concentration, tu peux le faire 💪'],
  focusEnd: ['Focus terminé, bravo ! 🎉 Une pause ?', "Et voilà {0} min de travail. Tu mérites une pause ☕", 'Session bouclée 🔥 On souffle un peu ?'],
  breakStart: ['Pause ! Lève-toi, bois un verre d’eau 💧', "Pause bien méritée ☕ Je m'occupe du temps.", 'Respire un grand coup 🌬 La pause commence.'],
  breakEnd: ['Fin de la pause ! On repart ?', 'La pause est finie 🙂 Prêt(e) pour la suite ?'],
  motivation: ['Tu avances, même si ça ne se voit pas encore 🌱', 'Une petite étape, puis la suivante 👣', "Pas besoin que ce soit parfait, juste que ce soit commencé ✨", 'Je suis là, on continue ensemble 🛰'],
  // pendant la pause : de petites phrases sympas (ni blagues ni culture G)
  breakLines: ['Lève-toi et étire-toi un peu, ton dos te dira merci 🙆', 'Un verre d’eau ? Ton cerveau adore ça 💧',
    'Regarde au loin quelques secondes, tes yeux respirent 👀', 'Trois respirations lentes… voilà, c’est tout 🌬',
    'Fais rouler tes épaules, ça détend 😌', 'Ouvre la fenêtre une minute, un peu d’air frais 🌿', 'Profite, tu as bien bossé 🙌',
    'Desserre la mâchoire, relâche les épaules 😊', 'Pense à un truc qui t’a fait sourire aujourd’hui 🙂',
    'Tu avances bien, sois fier(e) de toi ✨', 'Rien à faire pendant la pause, c’est le principe 😌',
    'Envoie un petit message sympa à quelqu’un ? 💌', 'Bouge un peu les mains et les poignets 🙌'],
  win: ['Bravo ! 🎉', 'Une victoire de plus 🏆', 'Yes ! ✨', 'Bien joué 💪', 'Et hop, fait ✅'],
};
export function pick(list) { return list[Math.floor(Math.random() * list.length)]; }
export function fmt(s, ...args) { return s.replace(/\{(\d)\}/g, (_, i) => String(args[+i] ?? '')); }

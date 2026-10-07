// Controle de securite de la version telephone (lit le code, ne l'execute pas).
// Lancement : node tests/pwa/static.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'pwa');
let ok = 0, ko = 0;
function check(name, cond, detail = '') {
  if (cond) { ok++; console.log(`  OK    ${name}`); } else { ko++; console.log(`  ECHEC ${name} ${detail}`); }
}
const read = (f) => fs.readFileSync(path.join(ROOT, f), 'utf8');
const js = ['js/app.js', 'js/store.js', 'js/zip.js', 'js/orbit.js', 'sw.template.js'];
// le code sans ses commentaires
const code = Object.fromEntries(js.map((f) => [f, read(f).replace(/\/\*[\s\S]*?\*\//g, '').split('\n').map((l) => l.replace(/(^|[^:'"`])\/\/.*$/, '$1')).join('\n')]));
const find = (re) => Object.entries(code).flatMap(([f, src]) => src.split('\n').map((l, i) => ({ f, n: i + 1, l })).filter((x) => re.test(x.l)));
const report = (hits) => hits.slice(0, 5).map((x) => `${x.f}:${x.n} ${x.l.trim()}`).join(' | ');

console.log('\n== Code de la version telephone');
let h = find(/innerHTML|outerHTML|insertAdjacentHTML|document\.write|DOMParser|createContextualFragment/);
check('aucun texte n\'est jamais interprete comme du HTML', h.length === 0, report(h));
h = find(/\beval\s*\(|new Function\s*\(|set(Timeout|Interval)\s*\(\s*['"`]/);
check('aucun code fabrique a partir de texte (eval, new Function...)', h.length === 0, report(h));
h = find(/fetch\s*\(\s*['"`]https?:|import\s*\(\s*['"`]https?:|new WebSocket|EventSource|XMLHttpRequest|sendBeacon/);
check('aucun envoi ni chargement sur internet', h.length === 0, report(h));
h = find(/window\.open\s*\(/);
check('liens rouverts : seulement des adresses verifiees, sans acces a Orbit (noopener)', h.length > 0 && h.every((x) => /St\.safeUrl\(/.test(x.l) && /noopener/.test(x.l)), report(h));
h = find(/setAttribute\(\s*['"`](href|src)['"`]|\.href\s*=|\.src\s*=/);
check('aucun lien ni image construit a partir des donnees', h.length === 0, report(h));
const hfn = (code['js/app.js'].match(/function h\(tag, props, \.\.\.kids\) \{[\s\S]*?\n\}/) || [''])[0];
check('outil h() : jamais d\'attribut « on… » en texte, liens seulement vers nos fichiers (blob:)', /k\.startsWith\('on'\)\) \{ if \(typeof v === 'function'\)/.test(hfn) && /k === 'href' \|\| k === 'src'\) && !String\(v\)\.startsWith\('blob:'\)/.test(hfn));
check('pas de cookie, rien d\'autre que le stockage du telephone', find(/document\.cookie|indexedDB\.deleteDatabase/).length === 0);

const invisible = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\uFE0E\uFE0F\uFEFF\uFFFD]/;
const inv = js.concat(['index.html', 'css/app.css']).filter((f) => invisible.test(read(f)));
check('aucun caractere invisible cache dans le code (ils sont ecrits \\uXXXX)', inv.length === 0, inv.join(', '));

console.log('\n== Page et appli installable');
const html = read('index.html');
const csp = (html.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/) || [])[1] || '';
check('politique de securite : scripts du site seulement, rien en ligne', /default-src 'self'/.test(csp) && /script-src 'self'/.test(csp) && !/unsafe-inline|unsafe-eval/.test(csp) && /object-src 'none'/.test(csp) && /base-uri 'none'/.test(csp) && /form-action 'none'/.test(csp));
check('aucun script ni gestionnaire d\'evenement dans la page', !/<script(?![^>]*\ssrc=)/.test(html) && !/\son[a-z]+\s*=/.test(html));
check('aucune ressource exterieure dans la page', !/(src|href)="https?:/.test(html));
check('pas de referent envoye aux liens', /name="referrer" content="no-referrer"/.test(html));
const man = JSON.parse(read('manifest.webmanifest'));
check('manifeste : partage limite a l\'appli elle-meme', man.scope === './' && man.share_target.action === './' && man.share_target.method === 'GET');
const sw = read('sw.js');
check('service worker : seulement les fichiers de l\'appli (meme origine, lecture)', /url\.origin !== self\.location\.origin\) return/.test(sw) && /req\.method !== 'GET'\) return/.test(sw));

console.log(`\n${ok} verification(s) reussie(s), ${ko} echec(s)`);
process.exit(ko ? 1 : 0);

// Fichiers de reference communs aux tests PC (PowerShell) et telephone (JavaScript) :
// les deux versions doivent decouper les taches de la meme facon et lire les memes fichiers.
// Lancement : node tools/make_fixtures.mjs
import fs from 'node:fs';
import * as S from '../pwa/js/store.js';
const rules = JSON.parse(fs.readFileSync('unstick/rules.json', 'utf8'));
const tasks = ['Répondre au mail de Julie', 'Faire mon compte-rendu de réunion', 'Payer la facture EDF', 'Ranger le bureau',
  'Appeler le dentiste', 'Finir le dossier CAF', 'Réparer le vélo', 'Préparer la présentation client', 'Réviser le chapitre 3',
  'Faire les courses', 'Aller courir', 'Cuisiner le dîner', 'Corriger le bug du script', "Prendre rendez-vous chez l'ophtalmo", 'Trier mes papiers'];
const expected = Object.fromEntries(tasks.map((t) => [t, S.decompose(t, rules)]));
fs.writeFileSync('tests/fixtures/unstick-expected.json', JSON.stringify(expected, null, 2) + '\n');
const s = S.defaultState();
S.dumpAdd(s, 'Idée notée sur le téléphone 🚀');
const r = S.dopaAdd(s, 'Boire un verre d’eau', 'daily');
r.lastDone = '2026-10-04';
S.dopaAdd(s, 'Envoyer le devis');
s.anchor.wins.push({ id: 'w1', title: 'Débloqué : Ranger le bureau', kind: 'unstick', at: '2026-10-04T10:00:00' });
fs.writeFileSync('tests/fixtures/lifeanchor-telephone.json', S.toDesktopFiles(s)['lifeanchor.json'] + '\n');
console.log('ok');

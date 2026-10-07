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
// tests/fixtures/lifeanchor-telephone.json n'est plus genere : c'est un exemple de l'ANCIEN format
// (Brain Dump + DopaList), garde pour verifier que la conversion en notes et cartes ne perd rien.
console.log('ok');

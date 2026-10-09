"""Fichier de reference commun aux tests PC (PowerShell) et Linux (Python) :
les deux versions doivent decouper les taches du S.O.S de la meme facon.
A relancer apres une modification de unstick/rules.json : python3 tools/make_fixtures.py
(tests/fixtures/lifeanchor-ancien.json n'est pas genere : c'est un exemple de l'ANCIEN format
(Brain Dump + DopaList), garde pour verifier que la conversion en notes et cartes ne perd rien.)
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'linux'))
import orbit_core as C  # noqa: E402

TASKS = ['Répondre au mail de Julie', 'Faire mon compte-rendu de réunion', 'Payer la facture EDF', 'Ranger le bureau',
         'Appeler le dentiste', 'Finir le dossier CAF', 'Réparer le vélo', 'Préparer la présentation client', 'Réviser le chapitre 3',
         'Faire les courses', 'Aller courir', 'Cuisiner le dîner', 'Corriger le bug du script', "Prendre rendez-vous chez l'ophtalmo", 'Trier mes papiers']

rules = json.loads((ROOT / 'unstick' / 'rules.json').read_text(encoding='utf-8'))
expected = {t: C.decompose(t, rules) for t in TASKS}
(ROOT / 'tests' / 'fixtures' / 'unstick-expected.json').write_text(
    json.dumps(expected, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('ok')

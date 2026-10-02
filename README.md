# Orbit 🛰️

Un petit satellite qui flotte au-dessus de toutes tes fenêtres, en bas à droite de l'écran où se trouve ta souris, et qui t'aide à rester concentré avec des cycles Pomodoro **50/10** (50 min de focus, 10 min de pause) ou **25/5**.

**Aucune installation, aucun droit administrateur** : Orbit n'utilise que PowerShell et WPF, deux composants déjà présents dans Windows 10 et 11.

## Démarrer

1. Télécharge le dossier (bouton *Code > Download ZIP*) et décompresse-le où tu veux, par exemple dans `Documents\Orbit`.
2. Double-clique sur **`Orbit.cmd`**.

Pour tester le cycle complet sans attendre, lance `Orbit.cmd -Demo` depuis un terminal (1 min de focus, 30 s de pause).

Le rythme **50/10 ou 25/5** se choisit dans la bulle d'accueil ou avec clic droit > ⏱ Rythme, et Orbit s'en souvient. Pour des durées sur mesure : `Orbit.cmd -FocusMinutes 40 -BreakMinutes 8`.

## Ce qu'il fait

- **Il te suit** : il se place en bas à droite de l'écran où se trouve ta souris et change d'écran en même temps que toi.
- **Il se balade** : de temps en temps, il part faire un petit tour sur tes écrans, puis il revient. Son capteur optique suit ta souris, sa balise clignote et son voyant change de couleur selon le moment (bleu = focus, vert = pause, orange = il attend ta réponse).
- **Il reste au-dessus** de toutes les applications, sans te voler le focus. Le chrono s'affiche sous lui.
- **Cycle Pomodoro avec confirmation**, en 50/10 ou en 25/5 :
  1. 🚀 focus (50 ou 25 min), puis **il s'arrête et attend** que tu cliques sur « Je prends ma pause » (ou « On arrête là ») ;
  2. ☕ pause (10 ou 5 min), puis **il attend encore** que tu cliques sur « On repart ! » (ou « On arrête là »).
  Tant que tu n'as pas répondu, il te relance toutes les 4 min et sa balise clignote en orange.
- **Rappels de tâches** (clic droit > 🔔, activés par défaut) :
  - **au début du focus**, il annonce ton objectif (la première tâche de ta to-do) et les deux suivantes ;
  - **à la fin du focus**, il demande si l'objectif est bouclé, avec un bouton « ✅ C'est fait ! » qui coche la tâche ;
  - **à la fin de la pause**, il rappelle la prochaine tâche au programme.
- **Des blagues pendant la pause** : environ une toutes les 2 minutes, sans répétition tant que toute la liste n'est pas passée.
- **Des bulles de BD** : tout ce que dit Orbit apparaît dans une bulle de bande dessinée avec un « pop ».
  - Bulle de **parole** (avec une pointe) quand il te parle : questions, chrono, indications.
  - Bulle de **pensée** (avec des petits ronds) pour ses réflexions et ses commentaires sur tes applis.
- **Des petits commentaires** : de la motivation pendant le focus (mi-parcours, 5 dernières minutes…) et des blagues selon l'application sous ta souris (Excel, Outlook, Teams, PowerPoint, VS Code…). Pendant le focus, il te taquine si tu passes sur YouTube, Netflix, Reddit…
- **Statistiques** : il compte tes sessions et tes minutes de focus du jour.
- **Une to-do en vrac** (clic droit > 📝 Ma to-do) :
  - tape une idée et appuie sur Entrée ;
  - chaque ajout, coche ou suppression est **enregistré tout de suite**, rien n'est perdu même si le PC plante ;
  - les tâches non faites restent d'un jour à l'autre, et les tâches terminées des jours précédents partent dans une archive ;
  - Orbit s'en sert pour ses rappels de tâches (voir plus haut).
- **L'historique des copier-coller du jour** (clic droit > 📋 Mes copier-coller du jour) :
  - chaque texte ou fichier copié (Ctrl+C) est noté avec l'heure ;
  - tu peux faire une recherche dedans, et **un clic sur un élément le recopie** pour le recoller ;
  - seule la journée en cours est conservée : l'historique de la veille est effacé automatiquement ;
  - ce que les gestionnaires de mots de passe marquent comme « à ne pas enregistrer » est ignoré, et une case **Pause** arrête l'enregistrement quand tu veux.

## Commandes

| Action | Effet |
|---|---|
| Clic gauche sur Orbit | Affiche le statut (temps restant, ou la question en attente) |
| Glisser Orbit | Le pose où tu veux, et il y reste |
| **Clic droit** | Menu : to-do, copier-coller, lancer un focus, prendre la pause, **rythme 50/10 ou 25/5**, **rappels de tâches**, mettre le chrono en pause, **couper le chrono**, mode silencieux, balades on/off, **réduire**, revenir en bas à droite, **masquer**, lancer au démarrage de Windows, stats, quitter |
| Carnet (to-do / copier-coller) | Entrée pour ajouter une tâche, Échap pour fermer, glisser le titre pour déplacer |
| Icône près de l'horloge | Double-clic pour faire réapparaître Orbit quand il est masqué ; clic droit pour le même menu en version courte |

- **Réduire** : Orbit devient tout petit et arrête de parler, mais il te prévient toujours à la fin d'une session.
- **Masquer** : Orbit disparaît de l'écran mais garde le chrono. Il revient tout seul à la fin d'une session, avec une notification Windows.
- **Lancer au démarrage de Windows** : crée un raccourci dans ton dossier *Démarrage* personnel. Pas besoin d'être administrateur.

## Personnaliser

Tout est dans `orbit.ps1` (le carnet est dans `notebook.ps1`) :
- les réglages (fréquence des commentaires, des balades, etc.) sont dans le bloc `$Config` en haut du fichier ;
- les phrases sont dans `$Lines`, `$AppLines` (par application) et `$TitleLines` (par mot-clé dans le titre de la fenêtre). Ajoute les tiennes !

Si tu modifies un fichier, garde l'encodage **UTF-8 avec BOM**, sinon les accents et les emojis s'afficheront mal.

Tout est enregistré dans `%APPDATA%\Orbit\` :

| Fichier | Contenu |
|---|---|
| `todo.json` / `todo.md` | ta to-do (le `.md` se lit dans n'importe quel éditeur) |
| `todo-archive.md` | les tâches terminées, jour par jour |
| `clipboard\AAAA-MM-JJ.json` | les copier-coller du jour |
| `stats.json`, `orbit.log` | statistiques et petit journal d'erreurs |

Attention : l'historique des copier-coller est stocké en clair dans ton profil. Si tu copies des données sensibles, utilise la case **Pause** ou le bouton **Tout effacer**.

## Et sur un PC d'entreprise ?

Orbit n'installe rien, n'écrit que dans ton profil utilisateur et ne demande aucun droit administrateur. `-ExecutionPolicy Bypass` ne s'applique qu'à ce lancement de PowerShell : ça ne touche pas aux réglages du PC.

Il peut quand même être bloqué si ton service informatique a verrouillé PowerShell (stratégie de groupe qui impose la politique d'exécution, AppLocker/WDAC, ou *Constrained Language Mode*). Dans ce cas, le plus simple est de leur demander : c'est un script lisible de quelques centaines de lignes, sans accès réseau.

Si seule la compilation des fonctions natives est bloquée, Orbit fonctionne quand même, mais sans les commentaires liés à l'application survolée.

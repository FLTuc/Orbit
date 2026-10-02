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
- **Il se balade** : de temps en temps, il part faire un petit tour sur tes écrans, puis il revient. C'est un vrai petit satellite : panneaux solaires où passe un reflet de soleil, antenne parabolique avec balise, viseur d'étoiles, isolation dorée, feux de navigation rouge et vert, propulseurs. Sa caméra suit ta souris et ses voyants changent de couleur selon le moment (bleu = focus, vert = pause, orange = il attend ta réponse). Clin d'œil geek : la rangée de LED sous la caméra affiche **les minutes restantes en binaire** (au repos, elle fait un balayage), et le chrono s'affiche en grand sur un petit écran intégré au dessin.
- **6 apparences au choix, ou ta propre image** (clic droit > 🎨 Apparence, ou dans les réglages) :
  - 🛰️ **Satellite** : le dessin décrit ci-dessus ;
  - 🤖 **Droïde de maintenance** : une sphère qui flotte sur ses réacteurs, avec une visière, un œil-caméra et deux petits bras articulés (l'un tient un tournevis) ;
  - 🦾 **Robot assistant** : un buste de robot avec une visière à deux yeux et un petit terminal sur la poitrine qui affiche son état (`> focus_`, `> pause_`…) ;
  - 🎩 **Majordome robot** : un robot en queue-de-pie, avec nœud papillon, monocle, moustache, serviette sur le bras et plateau avec un café fumant, entouré d'un anneau holographique qui tourne ;
  - 🤵 **Majordome humain** : un gentleman aux cheveux gris, moustache, queue-de-pie et gants blancs, plateau avec café et chrono ; ses yeux te suivent ;
  - 🖼️ **Mon image** : n'importe quelle image (PNG, JPG…) à la place du dessin, affichée telle quelle (un PNG à fond transparent rend le mieux), avec le chrono dans une étiquette sous l'image ;
  - 🧠 **Cerveau humain** : un cerveau dessiné comme une planche d'anatomie (lobes, scissure latérale, sillon central, circonvolutions serrées, cervelet, tronc cérébral), posé sur un socle de présentation qui affiche le chrono et les LED ; de petites étincelles d'activité neuronale s'allument de temps en temps.
  Les yeux (quand le dessin en a) suivent ta souris, les couleurs suivent le moment (focus, pause, attente) et les LED affichent les minutes restantes en binaire (sur le majordome, ce sont les boutons de sa chemise).
- **Il reste au-dessus** de toutes les applications, sans te voler le focus. Le chrono est intégré au dessin : sur un petit écran (panneau du satellite, sphère du droïde, terminal du robot, plateau des majordomes, socle du cerveau).
- **Cycle Pomodoro avec confirmation**, en 50/10, en 25/5 ou avec ton propre rythme (dans les réglages) :
  1. 🚀 focus (50 ou 25 min), puis **il s'arrête et attend** que tu cliques sur « Je prends ma pause » (ou « On arrête là ») ;
  2. ☕ pause (10 ou 5 min), puis **il attend encore** que tu cliques sur « On repart ! » (ou « On arrête là »).
  Tant que tu n'as pas répondu, il te relance toutes les 4 min et sa balise clignote en orange.
- **Rappels de tâches** (clic droit > 🔔, activés par défaut) :
  - **au début du focus**, il annonce ton objectif (la tâche la plus prioritaire) et les deux suivantes ;
  - **à la fin du focus**, il demande si l'objectif est bouclé, avec un bouton « ✅ C'est fait ! » qui coche la tâche ;
  - **à la fin de la pause**, il rappelle la prochaine tâche au programme.
- **Pause automatique si tu t'absentes** : si tu ne touches ni la souris ni le clavier pendant 5 min en plein focus, Orbit met le chrono en pause au moment où tu es parti (le temps d'absence ne compte pas). À ton retour, il te dit combien de temps tu as été absent et te propose de reprendre.
- **Des blagues pendant la pause** : environ une toutes les 2 minutes, piochées parmi **plus de 1000 blagues** (combles, devinettes, « Monsieur et Madame… », bureau, informatique, espace…). Orbit pose la question, puis donne la chute quelques secondes plus tard. Il retient où il en est, même après un redémarrage : aucune blague ne revient tant que toutes ne sont pas passées.
- **Des bulles de BD** : tout ce que dit Orbit apparaît dans une bulle de bande dessinée avec un « pop », accompagné d'un **petit son au choix** : droïde doux, carillon, marimba, pop, bip, **tes propres sons** (ajoute autant de fichiers WAV que tu veux, un est joué au hasard à chaque bulle, sans répéter deux fois de suite le même), ou 🎲 **aléatoire** parmi tous les sons. Les sons sont générés par Orbit lui-même et montent légèrement quand il te pose une question. Le son de fin de session et des rappels se choisit aussi (carillon, son de Windows ou ton fichier).
  - Bulle de **parole** (avec une pointe) quand il te parle : questions, chrono, indications.
  - Bulle de **pensée** (avec des petits ronds) pour ses réflexions et ses commentaires sur tes applis.
- **Des petits commentaires** : de la motivation pendant le focus (mi-parcours, 5 dernières minutes…) et des blagues selon l'application sous ta souris (Excel, Outlook, Teams, PowerPoint, VS Code…). Pendant le focus, il te taquine si tu passes sur YouTube, Netflix, Reddit…
- **Statistiques** : il compte tes sessions et tes minutes de focus du jour.
- **Une to-do en vrac** (clic droit > 📝 Ma to-do) :
  - tape une idée et appuie sur Entrée ;
  - **priorité de 1 à 10** (1 = la plus urgente, 10 = quand j'ai le temps ; 5 par défaut) : choisis-la dans la liste à côté du champ, ou tape « !2 » dans le texte (« !2 Appeler Paul ») ; clique sur la pastille P1…P10 d'une tâche pour la changer ;
  - les tâches sont triées par priorité, avec une couleur : rouge (1 à 3), orange (4 à 6), gris (7 à 10) ;
  - **modifier une tâche** : clique sur son texte (ou sur ✏️). Tu peux changer son titre et lui ajouter une **description** (détails, liens, étapes…), modifiable à tout moment. Tout s'enregistre automatiquement pendant que tu tapes ; Entrée dans le titre passe à la description, Ctrl+Entrée ou Échap termine ;
  - la description apparaît en aperçu sous la tâche, et Orbit la rappelle au début du focus quand c'est ton objectif ;
  - chaque ajout, coche ou suppression est **enregistré tout de suite**, rien n'est perdu même si le PC plante ;
  - les tâches non faites restent d'un jour à l'autre, et les tâches terminées des jours précédents partent dans une archive ;
  - Orbit s'en sert pour ses rappels de tâches (voir plus haut) ;
  - **échéance** (📅) : dans la fiche de la tâche, choisis une date. La tâche affiche « aujourd'hui », « demain », « en retard »… en couleur, et Orbit te signale au démarrage (et chaque matin) ce qui est à rendre aujourd'hui ou en retard ;
  - **rappel à heure fixe** (⏰) : dans la fiche, choisis une date et une heure, ou tape directement « @14h » ou « @14h30 » dans le texte de la tâche (« Appeler Paul @14h »). À l'heure dite, Orbit sonne, réapparaît s'il était caché et affiche la tâche avec trois boutons : « ✅ C'est fait », « ⏰ Dans 15 min » ou « 👍 OK ».
- **L'historique des copier-coller du jour** (clic droit > 📋 Mes copier-coller du jour) :
  - chaque texte ou fichier copié (Ctrl+C) est noté avec l'heure ;
  - tu peux faire une recherche dedans, et **un clic sur un élément le recopie** pour le recoller ;
  - seule la journée en cours est conservée : l'historique de la veille est effacé automatiquement ;
  - ce que les gestionnaires de mots de passe marquent comme « à ne pas enregistrer » est ignoré, et une case **Pause** arrête l'enregistrement quand tu veux ;
  - **favoris** ⭐ : clique sur ☆ pour garder un élément (adresse, signature, numéro de dossier…). Les favoris restent en haut de la liste **d'un jour à l'autre** et ne sont pas effacés par « Tout effacer ».
- **Réglages** (clic droit > ⚙️ Réglages…) : une fenêtre pour tout régler sans toucher au code :
  - rythme 50/10, 25/5 ou personnalisé ;
  - pause automatique en cas d'absence, et au bout de combien de minutes ;
  - rappels de tâches, et fréquence des relances quand Orbit attend ta réponse ;
  - blagues de pause (oui/non et fréquence), phrases de motivation, commentaires sur les applis, mode silencieux ;
  - apparence (satellite, droïde, robot, majordome robot ou humain, cerveau humain) ;
  - balades (oui/non et fréquence), sons (style, fichier perso, volume, bouton ▶ pour écouter), lancement au démarrage de Windows.

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

Le plus simple est de passer par **clic droit > ⚙️ Réglages…**. Pour aller plus loin, tout est dans `orbit.ps1` (le carnet est dans `notebook.ps1`, la fenêtre de réglages dans `settings.ps1`, les blagues dans `jokes\`) :
- les valeurs par défaut des réglages sont dans le bloc `$Config` en haut de `orbit.ps1` ;
- les phrases sont dans `$Lines`, `$AppLines` (par application) et `$TitleLines` (par mot-clé dans le titre de la fenêtre). Ajoute les tiennes !

Si tu modifies un fichier, garde l'encodage **UTF-8 avec BOM**, sinon les accents et les emojis s'afficheront mal.

Tout est enregistré dans `%APPDATA%\Orbit\` :

| Fichier | Contenu |
|---|---|
| `todo.json` / `todo.md` | ta to-do (le `.md` se lit dans n'importe quel éditeur) |
| `todo-archive.md` | les tâches terminées, jour par jour |
| `clipboard\AAAA-MM-JJ.json` | les copier-coller du jour |
| `clipboard-favoris.json` | les copier-coller mis en favori ⭐ (conservés) |
| `settings.json` | tes réglages |
| `sons\` | les sons WAV que tu as ajoutés (copiés ici) |
| `stats.json`, `orbit.log` | statistiques et petit journal d'erreurs |

Attention : l'historique des copier-coller est stocké en clair dans ton profil. Si tu copies des données sensibles, utilise la case **Pause** ou le bouton **Tout effacer**.

## Ajouter tes propres blagues

Les blagues sont dans le dossier `jokes\`, une par ligne, dans de simples fichiers texte (UTF-8) :

```
Quel est le comble pour un électricien ?|Ne pas être au courant.
Orbit a déjà terminé une to-do list. Les scientifiques étudient encore le phénomène.
```

- `question|réponse` : Orbit affiche la question, puis la réponse 4 secondes après ;
- une ligne sans `|` s'affiche d'un coup ;
- les lignes qui commencent par `#` sont ignorées ;
- tu peux créer ton propre fichier, par exemple `jokes\10-mes-blagues.txt`.

Pour vérifier qu'il n'y a ni doublon ni erreur de format (facultatif, il faut Python) : `python tools\check_jokes.py`.

## Et sur un PC d'entreprise ?

Orbit n'installe rien, n'écrit que dans ton profil utilisateur et ne demande aucun droit administrateur. `-ExecutionPolicy Bypass` ne s'applique qu'à ce lancement de PowerShell : ça ne touche pas aux réglages du PC.

Il peut quand même être bloqué si ton service informatique a verrouillé PowerShell (stratégie de groupe qui impose la politique d'exécution, AppLocker/WDAC, ou *Constrained Language Mode*). Dans ce cas, le plus simple est de leur demander : c'est un script lisible de quelques centaines de lignes, sans accès réseau.

Si seule la compilation des fonctions natives est bloquée, Orbit fonctionne quand même, mais sans les commentaires liés à l'application survolée.

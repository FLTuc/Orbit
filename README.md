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
- **Des bulles de BD** : tout ce que dit Orbit apparaît dans une bulle de bande dessinée avec un « pop », accompagné d'un **petit son au choix** : droïde doux, carillon, marimba, pop, bip, **tes propres sons** (ajoute autant de fichiers que tu veux, en WAV, MP3, M4A ou WMA ; un est joué au hasard à chaque bulle, sans répéter deux fois de suite le même), ou 🎲 **aléatoire** parmi tous les sons. Les sons sont générés par Orbit lui-même et montent légèrement quand il te pose une question. Le son de fin de session et des rappels se choisit aussi (carillon, son de Windows ou ton fichier WAV/MP3).
  - Bulle de **parole** (avec une pointe) quand il te parle : questions, chrono, indications.
  - Bulle de **pensée** (avec des petits ronds) pour ses réflexions et ses commentaires sur tes applis.
- **Des petits commentaires** : de la motivation pendant le focus (mi-parcours, 5 dernières minutes…) et des blagues selon l'application sous ta souris (Excel, Outlook, Teams, PowerPoint, VS Code…). Pendant le focus, il te taquine si tu passes sur YouTube, Netflix, Reddit…
- **Statistiques** : il compte tes sessions et tes minutes de focus du jour.
- **Des tableaux Kanban, façon Trello** (clic droit > 🗂️ Mes tableaux) :
  - **plusieurs tableaux** (un par projet, un perso…) : liste déroulante pour passer de l'un à l'autre, boutons ＋ Tableau, ✏️ renommer, 🗑️ supprimer ;
  - chaque tableau a ses **colonnes** (par défaut : À faire, En cours, Terminé) : ＋ Ajouter une colonne, et via le menu ⋯ d'une colonne : renommer (ou double-clic sur son nom), déplacer à gauche/droite, marquer comme colonne « terminé », archiver ses cartes, supprimer ;
  - **glisse les cartes** d'une colonne à l'autre, ou pour changer leur ordre ; clic droit sur une carte : déplacer vers une colonne, envoyer vers un autre tableau, supprimer ;
  - chaque carte garde tout ce que faisaient les tâches : **priorité de 1 à 10** (pastille P1…P10, ou « !2 » dans le texte), **description**, **échéance** 📅, **rappel** ⏰ (ou « @14h » dans le texte) ; clic sur une carte pour la modifier, enregistré automatiquement ;
  - une carte est « terminée » quand elle est dans une colonne marquée ✅ : c'est ce qu'utilisent les rappels de focus d'Orbit (« ✅ C'est fait ! » la range dans Terminé) ;
  - **cartes ↔ focus** : lie **une ou plusieurs cartes** à ton focus avec le bouton 🎯 d'une carte, le clic droit sur une carte, le bouton « 🎯 Choisir mes cartes » d'Orbit ou clic droit sur Orbit > 🎯 Cartes du focus (on peut même y créer une carte). Les cartes liées sont entourées en orange et passent dans « En cours » au début du focus. À la fin de chaque focus, chacune gagne une 🍅 et les minutes travaillées (« 🍅 3 · 2 h 30 » sur la carte) ; Orbit te demande lesquelles sont finies, et les autres restent liées au focus suivant. Une carte peut donc avoir plusieurs focus, et un focus plusieurs cartes. Sans carte liée, Orbit prend la plus prioritaire ;
  - ajout rapide en haut (dans la 1re colonne du tableau affiché) ou en bas de chaque colonne ; tout est enregistré à chaque modification ;
  - ton ancienne to-do est reprise automatiquement dans un premier tableau « Mon tableau » ;
  - **sous-tâches** : dans une carte, une liste à cocher (Entrée pour en ajouter une) ; la carte affiche « ☑ 2/5 », et quand tout est coché Orbit propose de la ranger dans Terminé ;
  - **cartes récurrentes** (🔁 Répéter : chaque jour ouvré, chaque jour, chaque semaine, toutes les 2 semaines, chaque mois) : quand tu la termines, la suivante revient toute seule dans la 1re colonne le jour venu, sous-tâches décochées et échéance décalée. Le bas du tableau indique « 🔁 n à venir » : clic pour la faire apparaître tout de suite ou arrêter la répétition ;
  - **modèles** : clic droit sur une carte > 📋 Enregistrer comme modèle, puis menu ⋯ d'une colonne > Nouvelle carte depuis un modèle (texte, description, sous-tâches, priorité, répétition).
  - **sauvegarde automatique chaque jour** (7 derniers jours gardés dans `%APPDATA%\Orbit\sauvegardes`) : le bouton 🕘 permet de revenir à l'état d'un jour précédent, et une restauration peut elle-même être annulée. Si le fichier des tableaux est abîmé au démarrage, Orbit repart tout seul de la dernière sauvegarde.
- **📝 Notes rapides** : clic droit sur Orbit (ou sur son icône près de l'horloge) > 📝 Note rapide. Un post-it jaune s'ouvre au milieu de l'écran : tu écris, et c'est **gardé automatiquement** dès que tu cliques sur ✓ OK, sur ✕, sur Échap ou ailleurs. Toutes tes notes sont dans l'onglet **📝 Notes** du carnet (clic droit > 📒 Mes notes) : clic pour modifier, 📍 épingler en haut, 🗂️ **transformer en carte** (1re ligne = titre, le reste = description ; « !2 » et « @14h » marchent), 📋 copier, 🗑️ supprimer. Elles sont aussi dans la recherche 🔍 et dans le transfert vers un autre PC.
  - **Sauvegarde des notes** (bouton **🕘 Sauvegardes** de l'onglet Notes) :
    - une copie automatique **chaque jour** (14 jours gardés) : clic pour **revenir** à l'état d'un jour précédent, et une restauration peut elle-même être annulée ;
    - une **corbeille** : une note supprimée reste récupérable **30 jours** (♻️) ;
    - **☁️ copie automatique dans un dossier de ton choix** (OneDrive, dossier réseau, clé USB…) : `Orbit-notes.md` (lisible partout, même sur ton téléphone avec OneDrive) et `Orbit-notes.json` (pour restaurer, même sur un autre PC), mis à jour à chaque note ;
    - **💾 Enregistrer une copie** où tu veux, en .txt ou .md ;
    - si le fichier des notes est abîmé au démarrage, Orbit repart tout seul de la dernière sauvegarde ;
    - et toujours une copie lisible dans `%APPDATA%\Orbit\notes.md`.
- **☀️ Plan du matin** : à ta première apparition de la journée (à partir de 5 h), Orbit propose les 3 cartes les plus urgentes, tous tableaux confondus (en retard, à rendre aujourd'hui ou demain, rappel du jour, déjà commencées, puis priorité), avec la raison. « Go » les lie au focus et le lance ; « Choisir autre chose » ouvre la liste avec ces 3 cartes déjà cochées. À revoir quand tu veux : clic droit > ☀️ Plan du jour. Se désactive dans les réglages.
- **🔍 Recherche partout** (onglet 🔍 du carnet, Ctrl+F, ou clic droit > Rechercher partout) : cartes de tous les tableaux (titre, description, sous-tâches), cartes récurrentes à venir, copier-coller et favoris, archives. Plusieurs mots : ils doivent tous y être ; accents et majuscules ignorés. Clic sur une carte : elle s'ouvre dans son tableau ; clic sur un copier-coller : il est recopié.
- **📦 Changer de PC** (clic droit > 📦 Autre PC) : « Exporter » crée un seul fichier zip avec Orbit et tes données (réglages, tableaux, modèles, favoris, sons, image, sauvegardes). Sur l'autre PC, décompresse-le et double-clic sur `Orbit\Orbit.cmd` : tout est récupéré au premier lancement (les chemins de l'image et des sons sont adaptés). Si Orbit est déjà installé, « Importer un export… » fait la même chose et redémarre Orbit ; les données présentes sont gardées dans `avant-import-<date>`.
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
  - balades (oui/non et fréquence), sons (style, fichiers perso WAV ou MP3, volume, bouton ▶ pour écouter), lancement au démarrage de Windows.

## Commandes

| Action | Effet |
|---|---|
| Clic gauche sur Orbit | Affiche le statut (temps restant, ou la question en attente) |
| Glisser Orbit | Le pose où tu veux, et il y reste |
| **Clic droit** | Menu : to-do, copier-coller, lancer un focus, prendre la pause, **rythme 50/10 ou 25/5**, **rappels de tâches**, mettre le chrono en pause, **couper le chrono**, mode silencieux, balades on/off, **réduire**, revenir en bas à droite, **masquer**, lancer au démarrage de Windows, stats, quitter |
| Carnet (tableaux / copier-coller / 🔍) | Entrée pour ajouter une carte, **Ctrl+F pour chercher partout**, Échap pour fermer, glisser le titre pour déplacer |
| Icône près de l'horloge | Elle affiche le **chrono en direct** (bleu = focus, vert = pause, gris = en pause, orange « ! » = Orbit attend ta réponse, satellite = au repos). **Un clic** : cacher / faire revenir Orbit ; clic droit : menu court (réduire, focus, pause, plan du jour, recherche, épingler l'icône…) |

- **Réduire** : Orbit devient tout petit et arrête de parler, mais il te prévient toujours à la fin d'une session.
- **Masquer** : Orbit disparaît de l'écran mais reste présent près de l'horloge, avec le chrono sur son icône. Il revient tout seul à la fin d'une session, avec une notification Windows.
- **Icône toujours visible** : sous Windows 11, Orbit épingle tout seul son icône à côté de l'horloge (au lieu de la cacher derrière la flèche ^), sauf si tu l'as déjà rangée toi-même. Sinon : clic droit sur l'icône > « Épingler l'icône près de l'horloge », ou fais-la glisser depuis la flèche ^.
- **Lancer au démarrage de Windows** : crée un raccourci dans ton dossier *Démarrage* personnel. Pas besoin d'être administrateur.

## Personnaliser

Le plus simple est de passer par **clic droit > ⚙️ Réglages…**. Pour aller plus loin, tout est dans `orbit.ps1` (le carnet est dans `notebook.ps1`, la fenêtre de réglages dans `settings.ps1`, les blagues dans `jokes\`) :
- les valeurs par défaut des réglages sont dans le bloc `$Config` en haut de `orbit.ps1` ;
- les phrases sont dans `$Lines`, `$AppLines` (par application) et `$TitleLines` (par mot-clé dans le titre de la fenêtre). Ajoute les tiennes !

Si tu modifies un fichier, garde l'encodage **UTF-8 avec BOM**, sinon les accents et les emojis s'afficheront mal.

Tout est enregistré dans `%APPDATA%\Orbit\` :

| Fichier | Contenu |
|---|---|
| `kanban.json` / `todo.md` | tes tableaux et leurs cartes (le `.md` se lit dans n'importe quel éditeur) |
| `todo-archive.md` | les cartes archivées, jour par jour |
| `clipboard\AAAA-MM-JJ.json` | les copier-coller du jour |
| `clipboard-favoris.json` | les copier-coller mis en favori ⭐ (conservés) |
| `settings.json` | tes réglages |
| `sons\` | les sons que tu as ajoutés (copiés ici) |
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

### Léger et solide

- **Peu de processeur** : Orbit ne s'anime à pleine vitesse que quand il se déplace ou que ta souris bouge (ses yeux la suivent). Le reste du temps il tourne au ralenti, et il ne calcule plus rien quand il est caché. Son flottement est confié à Windows, qui le dessine sans effort.
- **Démarrage rapide** : les fonctions natives sont compilées une seule fois puis gardées dans `%APPDATA%\Orbit` (`native-….dll`). Si ton PC refuse de charger ce fichier, Orbit les recompile en mémoire comme avant.
- **Fichiers protégés** : réglages, statistiques et tableaux sont écrits à côté puis échangés d'un coup. Une coupure pendant l'enregistrement ne laisse jamais un fichier à moitié écrit.
- **Tableaux fluides** : quand tu ajoutes, déplaces ou modifies une carte, seules les colonnes concernées sont redessinées. Rien n'est dessiné tant que la fenêtre est fermée.
- **Fenêtres à la demande** : la fenêtre des réglages n'est construite qu'à sa première ouverture, et celle des tableaux 3 s après le démarrage (Orbit apparaît plus vite, l'ouverture reste instantanée).
- **Un seul dessin en mémoire** : seul le dessin affiché est construit ; changer d'apparence construit le nouveau et libère l'ancien.
- **Moins d'écritures disque** : l'historique des copier-coller est enregistré au plus tard 2,5 s après un Ctrl+C (au lieu de chaque fois), `todo.md` au plus tard 10 s après une modification, et tout ce qui attend est écrit à la fermeture. `kanban.json` reste enregistré immédiatement.
- **Mémoire rendue à Windows** : quand tu ne touches à rien depuis une minute (ou qu'Orbit est caché), il fait le ménage, au plus toutes les 10 minutes. Le journal indique la mémoire avant/après.
- **Journal limité** : au-delà de 1 Mo, `orbit.log` devient `orbit.old.log` et repart de zéro.
- **Relance automatique** : une erreur imprévue est notée dans le journal sans faire tomber Orbit ; s'il plante quand même, il se relance tout seul (une fois toutes les 10 minutes au plus). Le cycle en cours (focus, pause, question en attente) est gardé dans `etat.json` : après un plantage ou un redémarrage forcé, Orbit reprend le chrono là où il en était (si c'était il y a moins de 4 h). « Quitter » efface cet état.
- **Testé sous Windows à chaque modification** : le dossier `tests` vérifie la syntaxe, la logique (tableaux, focus, sauvegardes, reprise), puis charge Orbit en entier (fenêtres, 7 dessins, code natif, sons) sur une machine Windows de GitHub, avec le même PowerShell 5.1 que ton PC. Tu peux aussi les lancer toi-même : `powershell -ExecutionPolicy Bypass -File tests\logic.ps1`.

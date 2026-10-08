# Orbit 🛰️

Un petit satellite qui flotte au-dessus de toutes tes fenêtres, en bas à droite de l'écran où se trouve ta souris, et qui t'aide à rester concentré avec des cycles Pomodoro **50/10** (50 min de focus, 10 min de pause) ou **25/5**.

**Aucune installation, aucun droit administrateur** : Orbit n'utilise que PowerShell et WPF, deux composants déjà présents dans Windows 10 et 11.

## Démarrer

1. Télécharge le dossier (bouton *Code > Download ZIP*) et décompresse-le où tu veux, par exemple dans `Documents\Orbit`.
2. Double-clique sur **`Orbit.cmd`**.

Pour tester le cycle complet sans attendre, lance `Orbit.cmd -Demo` depuis un terminal (1 min de focus, 30 s de pause).

Le rythme **50/10 ou 25/5** se choisit dans la bulle d'accueil ou avec clic droit > ☰ Plus > ⏱ Rythme, et Orbit s'en souvient. Pour des durées sur mesure : `Orbit.cmd -FocusMinutes 40 -BreakMinutes 8`.

## Ce qu'il fait

- **Il te suit** : il se place en bas à droite de l'écran où se trouve ta souris et change d'écran en même temps que toi.
- **Il se balade** : de temps en temps, il part faire un petit tour sur tes écrans, puis il revient. C'est un vrai petit satellite : panneaux solaires où passe un reflet de soleil, antenne parabolique avec balise, viseur d'étoiles, isolation dorée, feux de navigation rouge et vert, propulseurs. Sa caméra suit ta souris et ses voyants changent de couleur selon le moment (bleu = focus, vert = pause, orange = il attend ta réponse). Clin d'œil geek : la rangée de LED sous la caméra affiche **les minutes restantes en binaire** (au repos, elle fait un balayage), et le chrono s'affiche en grand sur un petit écran intégré au dessin.
- **6 apparences au choix, ou ta propre image** (clic droit > ☰ Plus > 🎨 Apparence, ou dans les réglages) :
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
- **Des bulles de BD** : tout ce que dit Orbit apparaît dans une bulle de bande dessinée avec un « pop », accompagné d'un **petit son au choix** : droïde doux, carillon, marimba, pop, bip, **tes propres sons** (choix « 📁 Mes sons » : voir ci-dessous), ou 🎲 **aléatoire** parmi tous les sons. Les sons sont générés par Orbit lui-même et montent légèrement quand il te pose une question. Le son de fin de session et des rappels se choisit aussi (carillon, son de Windows ou ton fichier WAV/MP3).
- **🎵 Mes sons = un dossier** : `%APPDATA%\Orbit\sons`. Tout fichier **.wav, .mp3, .m4a ou .wma** posé dedans fait partie de tes sons, sans rien régler. Pour le remplir :
  - dans les réglages (section 🔊), **＋ Ajouter…** copie les fichiers choisis dans ce dossier ;
  - **📂 Dossier** l'ouvre dans l'Explorateur : glisse-y tes sons, ou supprime ceux qui ne te plaisent plus ;
  - **－ Retirer** envoie le son sélectionné à la corbeille de Windows (récupérable) ;
  - **▶ Écouter** joue le son sélectionné (ou le suivant de la liste).

  Les sons passent **chacun leur tour, dans un ordre au hasard** : Orbit mélange la liste, joue chaque son une fois, puis remélange (jamais deux fois de suite le même). Le dossier part avec l'export vers un autre PC. Les sons choisis avec une ancienne version d'Orbit sont rangés tout seuls dans ce dossier au premier lancement.
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
  - **cartes ↔ focus** : lie **une ou plusieurs cartes** à ton focus avec le bouton 🎯 d'une carte, le clic droit sur une carte, le bouton « 🎯 Choisir mes cartes » d'Orbit ou clic droit sur Orbit > ☰ Plus > 🎯 Cartes du focus (on peut même y créer une carte). Les cartes liées sont entourées en orange et passent dans « En cours » au début du focus. À la fin de chaque focus, chacune gagne une 🍅 et les minutes travaillées (« 🍅 3 · 2 h 30 » sur la carte) ; Orbit te demande lesquelles sont finies, et les autres restent liées au focus suivant. Une carte peut donc avoir plusieurs focus, et un focus plusieurs cartes. Sans carte liée, Orbit prend la plus prioritaire ;
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
- **🚨 Quand tu bloques, et tes victoires** (pensé pour le TDAH, aussi sur le téléphone) :
  - **🚨 S.O.S / ⚡ Unstick Me** : clic droit > 🚨 S.O.S, ou ⚡ sur une carte. Tu écris ce que tu n'arrives pas à commencer (Win+H pour dicter) ; Orbit le découpe en 3 à 5 micro-étapes ridiculement petites (« Ouvre ta messagerie (juste l'ouvrir) »…) et n'en montre **qu'une à la fois**, avec une barre de 2 min 30 qui se vide doucement **sans jamais sonner**. « 🔪 Encore plus petit » ajoute une étape de préparation, ✏ la modifie, ⏭ la passe. À la fin : « 🎉 Tu es lancé(e) » et la victoire est notée. Un fond sonore 🟤 bruit brun est disponible.
  - **Les boutons ronds collés à Orbit** (réglable) : 📝 note rapide (tu écris, Entrée, c'est gardé), ✋ je m'interromps (pendant un focus), 🚨 S.O.S, 🗂 tableaux, 📒 notes et ↩ reprises (quand il y en a en attente). Sur le téléphone : 📝, ✋, ↩, 🏆 victoires et ☀ plan du jour juste sous Orbit.
  - **🏆 Mes victoires du jour** (clic droit sur Orbit > ☰ Plus) : le journal se remplit tout seul (focus terminés, cartes finies, déblocages, reprises), avec la série de jours d'affilée. Pas de compteur rouge ni de « en retard ».
  - *Le Brain Dump et la DopaList ont été retirés pour simplifier* : au premier lancement, leurs idées deviennent des notes et leurs actions des cartes (les routines deviennent des cartes qui se répètent). Rien n'est perdu.
  - Le découpage est fait **sur le PC**, avec les règles du fichier `unstick\rules.json` (les mêmes sur le téléphone, modifiables) : aucun service d'IA, rien ne sort du PC. Le PC et le téléphone donnent exactement les mêmes étapes (vérifié par les tests).
- **✋ Je m'interromps (savoir où tu t'es arrêté)** : quand on t'interrompt (collègue, appel, réunion), un clic suffit pour ne pas perdre le fil.
  - **Où cliquer** : le bouton rond **✋** à côté d'Orbit pendant un focus, clic droit sur Orbit > ✋ Je m'interromps, ou l'icône près de l'horloge. Pas de raccourci clavier.
  - **Ce qu'Orbit garde tout seul** :
    - la fenêtre sur laquelle tu travaillais, et les 3 précédentes (réglable) ;
    - l'**adresse de l'onglet** dans Edge, Chrome, Brave ou Opera (Firefox : au mieux) ;
    - le **dossier ouvert** dans l'Explorateur ;
    - le **fichier** Excel, Word ou PowerPoint ;
    - les cartes de ton focus ;
    - en option, une **petite capture d'écran**.
  - **Le post-it** : deux lignes facultatives, « J'étais en train de… » et « ➡ Prochaine étape exacte ». Si ta carte du focus a des sous-tâches, la prochaine non cochée est déjà proposée. Entrée enregistre ; cliquer ailleurs enregistre aussi (c'est le principe d'une interruption).
  - **Le focus se met en pause** pendant l'interruption.
  - **Au retour** (après 2 min sans clavier ni souris, ou en cliquant sur Orbit), Orbit te montre « ↩ Tu t'étais arrêté(e) il y a 25 min sur… », avec ce que tu faisais et la prochaine étape. Les boutons de cette bulle :
    - **▶ Reprendre** : remet les fenêtres devant, ou rouvre l'onglet, le dossier ou le document si tu les as fermés, relance le focus et te redit la prochaine étape ;
    - **⏰ Plus tard** ;
    - **🗂 En carte** : la prochaine étape devient le titre, le contexte la description ;
    - **✓ Déjà fait**.
  - **Onglet ↩ Reprises du carnet** (clic droit > ↩ Mes reprises) : toutes les interruptions en attente, avec titre, adresse, note, prochaine étape et capture, puis celles déjà reprises (14 jours).
  - **Partout ailleurs** : les reprises sont aussi dans la recherche 🔍 et dans le plan du matin (« Tu t'étais arrêté(e) hier sur… »).
  - **Réglages** (section ✋) :
    - le bouton ✋ (oui/non) ;
    - le nombre de fenêtres gardées (active seule, ou + 2, 3 ou 5 précédentes) ;
    - la capture d'écran (non par défaut) ;
    - le rappel si tu n'as pas repris (après 30 min par défaut, 3 fois au plus, jamais pendant un focus).
  - **Vie privée** :
    - les fenêtres de navigation privée (InPrivate, Incognito) ne sont jamais lues ;
    - la capture d'écran reste sur ce PC, n'est jamais exportée et s'efface dès que tu as repris ;
    - Orbit ne rouvre que des adresses web (http/https), des dossiers et des documents (Excel, Word, PDF…) qui existent, jamais un programme.
- **👀 « Tu attends quoi ? »** : si aucun focus n'a été lancé depuis **45 minutes** (réglable) alors que des cartes attendent, Orbit sort une bulle : « Tu as des tâches en cours, qu'est-ce que tu attends ? » avec **2 ou 3 cartes proposées** (les plus urgentes, avec la raison). Un clic sur une carte lance le focus dessus ; **⏰ Plus tard** le redemande dans 45 min ; **🌙 Pas aujourd'hui** le fait taire jusqu'au lendemain. Jamais pendant un focus ou une pause, jamais si tu n'es pas devant l'écran (il attend ton retour), jamais par-dessus une autre question, ni quand Orbit est caché ou réduit. Aussi sur le téléphone (quand l'appli est ouverte). Réglages : case « 👀 Sans focus depuis … min ».
- **☀️ Plan du matin** : à ta première apparition de la journée (à partir de 5 h), Orbit propose les 3 cartes les plus urgentes, tous tableaux confondus (en retard, à rendre aujourd'hui ou demain, rappel du jour, déjà commencées, puis priorité), avec la raison. « Go » les lie au focus et le lance ; « Choisir autre chose » ouvre la liste avec ces 3 cartes déjà cochées. À revoir quand tu veux : clic droit > ☀️ Plan du jour. Se désactive dans les réglages.
- **🔍 Recherche partout** (onglet 🔍 du carnet, Ctrl+F, ou clic droit > ☰ Plus > Rechercher partout) : cartes de tous les tableaux (titre, description, sous-tâches), notes, reprises (✋), cartes récurrentes à venir, copier-coller et favoris, archives. Plusieurs mots : ils doivent tous y être ; accents et majuscules ignorés. Clic sur une carte : elle s'ouvre dans son tableau ; clic sur un copier-coller : il est recopié.
- **📦 Changer de PC** (clic droit > ☰ Plus > 📦 Autre PC) : « Exporter » crée un seul fichier zip avec Orbit et tes données (réglages, tableaux, modèles, favoris, sons, image, sauvegardes). Sur l'autre PC, décompresse-le et double-clic sur `Orbit\Orbit.cmd` : tout est récupéré au premier lancement (les chemins de l'image et des sons sont adaptés). Si Orbit est déjà installé, « Importer un export… » fait la même chose et redémarre Orbit ; les données présentes sont gardées dans `avant-import-<date>`.
- **L'historique des copier-coller du jour** (clic droit > ☰ Plus > 📋 Mes copier-coller du jour) :
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
  - balades (oui/non et fréquence), sons (style, dossier « Mes sons » avec ＋ Ajouter / － Retirer / 📂 Dossier, volume, bouton ▶ pour écouter), lancement au démarrage de Windows.

## 📱 Orbit sur ton téléphone (Android, iPhone)

Le dossier `pwa\` contient Orbit en version « appli web installable » : elle s'ajoute à l'écran d'accueil, s'ouvre en plein écran, **fonctionne sans réseau** et garde tout sur le téléphone (rien n'est envoyé nulle part).

**Ce qu'il y a dedans** :
- Orbit et sa bulle, le Pomodoro (50/10, 25/5 ou perso) avec ses confirmations, les blagues et la culture G ;
- les tableaux Kanban, les notes, ✋ Je m'interromps, le plan du matin et la recherche ;
- 🚨 S.O.S / ⚡ Unstick Me, la 📝 note rapide (bouton rond) et le 🏆 journal des victoires ;
- sons doux et vibrations, écran maintenu allumé pendant un focus (option), bruit brun, dictée (🎙).

**Les petits plus du téléphone** :
- **Partager** une page depuis Chrome vers Orbit la garde comme « reprise », avec son lien.
- **Appui long sur l'icône** : 📝 Note rapide, 🚨 S.O.S, ✋ Je m'interromps, 🚀 Focus.

**PC ↔ téléphone** (☰ Plus > 💻) :
- *Recevoir* : lit directement le zip créé par Orbit PC (clic droit > ☰ Plus > 📦 Autre PC > Exporter).
- *Envoyer* : crée un zip qu'Orbit PC ouvre avec « Importer un export… ».
- Ce sont les mêmes fichiers des deux côtés : tableaux, notes, reprises, victoires.

**L'installer** : il faut que le dossier `pwa\` soit en ligne en HTTPS (obligatoire pour une appli installable). Au choix :
1. **GitHub Pages** : Settings > Pages > Source « GitHub Actions ». Le workflow « Version téléphone » publie alors l'appli à chaque mise à jour de `main`. Sur un dépôt **privé**, GitHub Pages demande un abonnement GitHub Pro (ou de rendre le dépôt public : le code ne contient aucune donnée personnelle).
2. **Netlify, Cloudflare Pages…** (gratuits) : le zip `orbit-telephone-site`, téléchargeable dans l'onglet Actions de GitHub après chaque test, se dépose tel quel.

Ensuite, sur le téléphone : ouvre l'adresse dans Chrome, puis ⋮ > « Installer l'application » (ou ☰ Plus > 📲 Installer).

**Limites honnêtes** :
- un téléphone endort les applis web : la fin d'un focus sonne si Orbit est ouvert (option « garder l'écran allumé ») et sinon au retour, avec une notification si tu les autorises ;
- la dictée 🎙 utilise le service vocal du téléphone (Google sur Android) ; le micro du clavier marche aussi.

**Tests** :
- `node tests/pwa/unit.mjs` : la logique et les attaques ;
- `node tests/pwa/static.mjs` : la sécurité du code ;
- `node tests/pwa/e2e.cjs` : un parcours complet sur un Pixel 7 simulé, avec le temps accéléré, le hors-ligne, le partage, le glissement du doigt, l'import et l'export ;
- `node tests/pwa/monkey.cjs 500 1` : le test « chaos » : 500 gestes au hasard (boutons, saisies, retour d'Android, temps qui passe, rechargements), sans aucune erreur permise ;
- `python tools/build_pwa.py` : régénère les blagues et la culture G du téléphone, et le cache hors ligne.

## Commandes

| Action | Effet |
|---|---|
| Clic gauche sur Orbit | Affiche le statut (temps restant, ou la question en attente) |
| Glisser Orbit | Le pose où tu veux, et il y reste |
| **Clic droit** | Un menu court : le chrono (seulement ce qui sert à cet instant : lancer un focus, prendre la pause, mettre en pause, couper), 📝 Note rapide, ✋ Je m'interromps, 🚨 S.O.S, 🗂 Mes tableaux, 📒 Mes notes, ↩ Mes reprises, puis **☰ Plus** (cartes du focus, plan du jour, rythme, rappels, recherche, copier-coller, victoires, culture G, apparence, silencieux, balades, réduire, masquer, démarrage de Windows, autre PC), ⚙ Réglages et Quitter. « 🏠 Revenir en bas à droite » apparaît quand tu as déplacé Orbit. |
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
| `sons\` | **tes sons** : tout fichier .wav, .mp3, .m4a ou .wma posé ici est joué, chacun son tour, au hasard |
| `stats.json`, `orbit.log` | statistiques et petit journal d'erreurs |

Attention : l'historique des copier-coller est stocké en clair dans ton profil. Si tu copies des données sensibles, utilise la case **Pause** ou le bouton **Tout effacer**.

## 🧠 Culture G

Pendant la pause, Orbit peut aussi te donner une **anecdote** (« 🧠 Le saviez-vous ? ») ou un **petit quiz** (la question, puis la réponse quelques secondes plus tard). Plus de **340 entrées** dans 10 thèmes : sciences, histoire, géographie, arts et littérature, nature et animaux, corps humain, langue française et expressions, espace, inventions, et travail/concentration (de quoi mieux profiter de tes pauses).

- **Réglages > Blagues et commentaires** : « Blagues et culture G en alternance » (par défaut), « Des blagues » ou « De la culture G ».
- Quand tu veux : clic droit sur Orbit (ou sur son icône) > **🧠 Le saviez-vous ?**
- Comme les blagues : ordre mélangé, mémorisé d'un lancement à l'autre, pas de répétition avant d'avoir tout vu.
- Pour en ajouter : un fichier `.txt` dans le dossier `culture`, une entrée par ligne. `Question ?|Réponse` pour un quiz, une phrase seule pour une anecdote ; les lignes qui commencent par `#` sont ignorées.

## Ajouter tes propres blagues

Les blagues sont dans le dossier `jokes\`, une par ligne, dans de simples fichiers texte (UTF-8) :

```
Quel est le comble pour un électricien ?|Ne pas être au courant.
Orbit a déjà terminé une to-do list. Les scientifiques étudient encore le phénomène.
```

- `question|réponse` : Orbit affiche la question, puis la réponse 4 secondes après ;
- une ligne sans `|` s'affiche d'un coup ;
- les lignes qui commencent par `#` sont ignorées ;
- tu peux créer ton propre fichier, par exemple `jokes\10-mes-blagues.txt` ;
- l'encodage n'a pas d'importance : un fichier enregistré en ANSI par un ancien Bloc-notes est lu correctement (pas de losange à la place des accents) ;
- évite les emoji composés (👩‍💻, 👍🏽, drapeaux, 8️⃣) : la bulle ne sait pas les assembler, Orbit n'en garde que le premier morceau.

Pour vérifier qu'il n'y a ni doublon ni erreur de format (facultatif, il faut Python) : `python tools\check_jokes.py`.

## Et sur un PC d'entreprise ?

Orbit n'installe rien, n'écrit que dans ton profil utilisateur et ne demande aucun droit administrateur. `-ExecutionPolicy Bypass` ne s'applique qu'à ce lancement de PowerShell : ça ne touche pas aux réglages du PC.

Il peut quand même être bloqué si ton service informatique a verrouillé PowerShell (stratégie de groupe qui impose la politique d'exécution, AppLocker/WDAC, ou *Constrained Language Mode*). Dans ce cas, le plus simple est de leur demander : c'est un script lisible de quelques centaines de lignes, sans accès réseau.

Si seule la compilation des fonctions natives est bloquée, Orbit fonctionne quand même, mais sans les commentaires liés à l'application survolée.

### Sécurité

- **Aucun accès réseau** : Orbit ne contacte aucun serveur, rien ne sort de ton PC (sauf si tu choisis toi-même un dossier OneDrive/réseau pour la copie des notes).
- **Aucun droit administrateur** : il n'écrit que dans ton profil (`%APPDATA%\Orbit`, ton dossier *Démarrage* si tu le demandes, et le réglage d'affichage de son icône dans ta partie du registre, HKCU).
- **Tes données ne sont jamais exécutées** : le texte des cartes, notes, copier-coller et les fichiers lus sur le disque sont traités comme du texte, jamais comme du code. Les identifiants lus dans les fichiers sont filtrés (un fichier trafiqué ne peut pas glisser une commande).
- **Import d'un export reçu de quelqu'un** : aucun fichier de code n'est copié (code compilé, état du chrono), et les réglages qui pointeraient hors du dossier d'Orbit (partage réseau pour la copie des notes, image ou sons distants) sont retirés. Les reprises (✋) importées perdent leurs chemins de fichiers et de dossiers : seuls le texte, les titres et les adresses web voyagent. Les archives zip « piégées » (fichiers qui essaient de sortir du dossier) sont refusées.
- **Je m'interromps** : Orbit lit les fenêtres ouvertes et la barre d'adresse des navigateurs uniquement quand tu cliques sur ✋, jamais en continu. La lecture se fait à part (un navigateur ou Excel qui ne répond pas ne bloque pas Orbit). À la reprise, il ne rouvre que des adresses http/https et des dossiers ou documents existants (jamais un .exe, un script ou un raccourci), toujours via l'Explorateur de Windows.
- **Copier-coller** : ce que les gestionnaires de mots de passe marquent « à ne pas enregistrer » est ignoré ; l'historique du jour n'est jamais inclus dans un export. Attention : un **favori** ⭐ que tu épingles, lui, est gardé et exporté.
- **Vérifié automatiquement à chaque modification** (`tests\security.ps1` + attaques simulées dans `tests\logic.ps1`, voir plus bas).
- Limite connue : quelqu'un qui a déjà accès à ta session Windows peut modifier les fichiers d'Orbit (comme n'importe quel programme ou document de ton profil).

### Léger et solide

- **Peu de processeur** : Orbit ne s'anime à pleine vitesse que quand il se déplace ou que ta souris bouge (ses yeux la suivent). Le reste du temps il tourne au ralenti, et il ne calcule plus rien quand il est caché. Son flottement est confié à Windows, qui le dessine sans effort.
- **Démarrage rapide** : les fonctions natives sont compilées une seule fois puis gardées dans `%APPDATA%\Orbit` (`native-….dll`). Si ton PC refuse de charger ce fichier, Orbit les recompile en mémoire comme avant.
- **Fichiers protégés** : réglages, statistiques et tableaux sont écrits à côté puis échangés d'un coup. Une coupure pendant l'enregistrement ne laisse jamais un fichier à moitié écrit.
- **Tableaux fluides** : quand tu ajoutes, déplaces ou modifies une carte, seules les colonnes concernées sont redessinées. Rien n'est dessiné tant que la fenêtre est fermée.
- **Fenêtres à la demande** : la fenêtre des réglages n'est construite qu'à sa première ouverture, et celle des tableaux 3 s après le démarrage (Orbit apparaît plus vite, l'ouverture reste instantanée).
- **Un seul dessin en mémoire** : seul le dessin affiché est construit ; changer d'apparence construit le nouveau et libère l'ancien.
- **Moins d'écritures disque** : l'historique des copier-coller est enregistré au plus tard 2,5 s après un Ctrl+C (au lieu de chaque fois), `todo.md` au plus tard 10 s après une modification, et tout ce qui attend est écrit à la fermeture. `kanban.json` reste enregistré immédiatement.
- **Mémoire rendue à Windows** : quand tu ne touches à rien depuis une minute (ou qu'Orbit est caché), il fait le ménage, au plus toutes les 10 minutes. Le journal indique la mémoire avant/après.
- **Texte des bulles propre** : avant d'afficher une bulle, Orbit enlève ce que la fenêtre ne sait pas dessiner et qui apparaissait en plein milieu des phrases (morceaux d'emoji composés, sélecteurs de variante, marques invisibles des titres de fenêtres, emoji absents des polices de Windows). Les textes raccourcis (cartes, notes, recherche, copier-coller, info-bulle de l'icône) ne coupent plus jamais un emoji en deux. Si les fichiers d'Orbit ont été réenregistrés sans BOM (copie, éditeur de texte), Orbit le remet tout seul au lancement : sinon PowerShell 5.1 affiche « Ã© » à la place des « é ».
- **Journal limité** : au-delà de 1 Mo, `orbit.log` devient `orbit.old.log` et repart de zéro.
- **Relance automatique** : une erreur imprévue est notée dans le journal sans faire tomber Orbit ; s'il plante quand même, il se relance tout seul (une fois toutes les 10 minutes au plus). Le cycle en cours (focus, pause, question en attente) est gardé dans `etat.json` : après un plantage ou un redémarrage forcé, Orbit reprend le chrono là où il en était (si c'était il y a moins de 4 h). « Quitter » efface cet état.
- **Testé sous Windows à chaque modification** : le dossier `tests` vérifie la syntaxe, la logique (tableaux, focus, sauvegardes, reprise), puis charge Orbit en entier (fenêtres, 7 dessins, code natif, sons) sur une machine Windows de GitHub, avec le même PowerShell 5.1 que ton PC. Tu peux aussi les lancer toi-même : `powershell -ExecutionPolicy Bypass -File tests\logic.ps1`.

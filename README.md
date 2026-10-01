# Orbit 🛰️

Un petit robot qui flotte au-dessus de toutes tes fenêtres, en bas à droite de l'écran où se trouve ta souris, et qui t'aide à rester concentré avec des cycles **50 min de focus / 10 min de pause**.

**Aucune installation, aucun droit administrateur** : Orbit n'utilise que PowerShell et WPF, deux composants déjà présents dans Windows 10 et 11.

## Démarrer

1. Télécharge le dossier (bouton *Code > Download ZIP*) et décompresse-le où tu veux, par exemple dans `Documents\Orbit`.
2. Double-clique sur **`Orbit.cmd`**.

Pour tester le cycle complet sans attendre 50 minutes, lance `Orbit.cmd -Demo` depuis un terminal (1 min de focus, 30 s de pause).

Tu peux aussi choisir d'autres durées : `Orbit.cmd -FocusMinutes 25 -BreakMinutes 5`.

## Ce qu'il fait

- **Il te suit** : il se place en bas à droite de l'écran où se trouve ta souris et change d'écran en même temps que toi.
- **Il se balade** : de temps en temps, il part faire un petit tour sur tes écrans, puis il revient. Ses yeux suivent ta souris.
- **Il reste au-dessus** de toutes les applications, sans te voler le focus. Le chrono s'affiche sous lui.
- **Cycle Pomodoro avec confirmation** :
  1. 🚀 50 min de focus, puis **il s'arrête et attend** que tu cliques sur « Je prends ma pause » (ou « On arrête là ») ;
  2. ☕ 10 min de pause, puis **il attend encore** que tu cliques sur « On repart ! » (ou « On arrête là »).
  Tant que tu n'as pas répondu, il te relance gentiment toutes les 4 min et son antenne clignote.
- **Des petits commentaires** : de la motivation pendant le focus (mi-parcours, 5 dernières minutes…) et des blagues selon l'application sous ta souris (Excel, Outlook, Teams, PowerPoint, VS Code…). Pendant le focus, il te taquine si tu passes sur YouTube, Netflix, Reddit…
- **Statistiques** : il compte tes sessions de focus du jour.

## Commandes

| Action | Effet |
|---|---|
| Clic gauche sur Orbit | Affiche le statut (temps restant, ou la question en attente) |
| Glisser Orbit | Le pose où tu veux, et il y reste |
| **Clic droit** | Menu : lancer un focus, prendre la pause, mettre le chrono en pause, **couper le chrono**, mode silencieux, balades on/off, **réduire**, revenir en bas à droite, **masquer**, lancer au démarrage de Windows, stats, quitter |
| Icône près de l'horloge | Double-clic pour faire réapparaître Orbit quand il est masqué ; clic droit pour le même menu en version courte |

- **Réduire** : Orbit devient tout petit et arrête de parler, mais il te prévient toujours à la fin d'une session.
- **Masquer** : Orbit disparaît de l'écran mais garde le chrono. Il revient tout seul à la fin d'une session, avec une notification Windows.
- **Lancer au démarrage de Windows** : crée un raccourci dans ton dossier *Démarrage* personnel. Pas besoin d'être administrateur.

## Personnaliser

Tout est dans `orbit.ps1` :
- les réglages (fréquence des commentaires, des balades, etc.) sont dans le bloc `$Config` en haut du fichier ;
- les phrases sont dans `$Lines`, `$AppLines` (par application) et `$TitleLines` (par mot-clé dans le titre de la fenêtre). Ajoute les tiennes !

Si tu modifies le fichier, garde l'encodage **UTF-8 avec BOM**, sinon les accents et les emojis s'afficheront mal.

Les statistiques et un petit journal d'erreurs sont enregistrés dans `%APPDATA%\Orbit\`.

## Et sur un PC d'entreprise ?

Orbit n'installe rien, n'écrit que dans ton profil utilisateur et ne demande aucun droit administrateur. `-ExecutionPolicy Bypass` ne s'applique qu'à ce lancement de PowerShell : ça ne touche pas aux réglages du PC.

Il peut quand même être bloqué si ton service informatique a verrouillé PowerShell (stratégie de groupe qui impose la politique d'exécution, AppLocker/WDAC, ou *Constrained Language Mode*). Dans ce cas, le plus simple est de leur demander : c'est un script lisible de quelques centaines de lignes, sans accès réseau.

Si seule la compilation des fonctions natives est bloquée, Orbit fonctionne quand même, mais sans les commentaires liés à l'application survolée.

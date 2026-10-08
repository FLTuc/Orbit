#!/bin/sh
# Installe Orbit (version Linux legere) pour l'utilisateur courant : sans droits administrateur.
#   sh linux/install.sh            installe et ajoute Orbit au menu des applications
#   sh linux/install.sh --autostart   ... et le lance a chaque ouverture de session
#   sh linux/install.sh --remove      desinstalle (tes donnees dans ~/.local/share/orbit sont gardees)
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
APP="${XDG_DATA_HOME:-$HOME/.local/share}/orbit-app"
MENU="${XDG_DATA_HOME:-$HOME/.local/share}/applications/orbit.desktop"
AUTO="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/orbit.desktop"

if [ "${1:-}" = "--remove" ]; then
    rm -rf "$APP" "$MENU" "$AUTO"
    echo "Orbit est désinstallé. Tes données sont gardées dans ${XDG_DATA_HOME:-$HOME/.local/share}/orbit"
    exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Il faut Python 3 :  sudo apt install python3 python3-tk"
    exit 1
fi
if ! python3 -c 'import tkinter' 2>/dev/null; then
    echo "Il manque Tkinter (l'affichage d'Orbit, environ 3 Mo) :"
    echo "    sudo apt install python3-tk"
    exit 1
fi

mkdir -p "$APP/unstick" "$(dirname "$MENU")"
cp "$HERE/orbit.py" "$HERE/orbit_core.py" "$HERE/orbit.png" "$APP/"
cp "$HERE/../unstick/rules.json" "$APP/unstick/"

cat > "$MENU" <<EOF
[Desktop Entry]
Type=Application
Name=Orbit
Comment=Compagnon de concentration (focus, tableaux, notes)
Exec=python3 "$APP/orbit.py"
Icon=$APP/orbit.png
Categories=Utility;
Terminal=false
EOF

if [ "${1:-}" = "--autostart" ]; then
    mkdir -p "$(dirname "$AUTO")"
    cp "$MENU" "$AUTO"
    echo "Orbit se lancera à chaque ouverture de session."
fi

echo "Orbit est installé. Lance-le depuis le menu des applications, ou :  python3 \"$APP/orbit.py\""
for tool in xdotool xprintidle; do
    command -v "$tool" >/dev/null 2>&1 || MISSING="${MISSING:-} $tool"
done
if [ -n "${MISSING:-}" ]; then
    echo "Facultatif :  sudo apt install${MISSING}"
    echo "  (xdotool : garder la fenêtre en cours avec ✋ ; xprintidle : pause auto quand tu t'absentes)"
fi

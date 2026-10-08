"""Prepare la version telephone d'Orbit (dossier pwa/) :
- data/unstick.json (regles du S.O.S, les memes que sur le PC) ;
- sw.js : numero de version du cache calcule a partir du contenu, et liste des fichiers
  a garder hors ligne.

Usage : python tools/build_pwa.py           (ecrit les fichiers)
        python tools/build_pwa.py --check   (echoue si les fichiers ne sont pas a jour)
"""
import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PWA = ROOT / "pwa"
# fichiers de l'appli gardes hors ligne (sw.js lui-meme n'en fait pas partie)
SHELL = ["./", "index.html", "manifest.webmanifest", "css/app.css", "js/app.js", "js/store.js",
         "js/zip.js", "js/orbit.js", "data/unstick.json",
         "icons/icon.svg", "icons/icon-192.png", "icons/icon-512.png", "icons/maskable-512.png"]


def build():
    out = {}
    rules = json.loads((ROOT / "unstick" / "rules.json").read_text(encoding="utf-8"))
    out["data/unstick.json"] = json.dumps(rules, ensure_ascii=False, indent=1) + "\n"
    h = hashlib.sha256()
    for name in SHELL:
        if name == "./":
            continue
        data = out[name].encode("utf-8") if name in out else (PWA / name).read_bytes()
        h.update(name.encode() + b"\0" + data)
    version = h.hexdigest()[:12]
    template = (PWA / "sw.template.js").read_text(encoding="utf-8")
    out["sw.js"] = (template.replace("__VERSION__", version)
                    .replace("__FILES__", json.dumps(SHELL)))
    return out


def main():
    check = "--check" in sys.argv
    stale = []
    for name, content in build().items():
        target = PWA / name
        old = target.read_text(encoding="utf-8") if target.exists() else None
        if old != content:
            stale.append(name)
            if not check:
                target.write_text(content, encoding="utf-8", newline="\n")
    if check and stale:
        print("A regenerer (python tools/build_pwa.py) :", ", ".join(stale))
        return 1
    print("pwa a jour" if not stale else "ecrit : " + ", ".join(stale))
    return 0


if __name__ == "__main__":
    sys.exit(main())

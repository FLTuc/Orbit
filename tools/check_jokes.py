"""Vérifie les fichiers texte d'Orbit (blagues, culture G) : compte, doublons et format.

Usage : python tools/check_jokes.py [--dir jokes] [--min 1000]
        python tools/check_jokes.py --dir culture --min 300
"""
import argparse
import pathlib
import re
import sys
import unicodedata


def norm(text):
    text = unicodedata.normalize("NFKD", text.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", " ", text).strip()


# Caractères que WPF (la bulle d'Orbit) n'assemble pas et affiche comme des carrés ou
# des symboles parasites : liants d'emoji, sélecteurs, touches, teintes, drapeaux, emoji
# trop récents pour la police, caractères de contrôle ou invalides.
def shown(c):
    cp = ord(c)
    if cp in (0x200D, 0xFE0E, 0xFE0F, 0x20E3, 0xFFFD, 0x200B, 0xFEFF):
        return False
    if 0x1F3FB <= cp <= 0x1F3FF or 0x1F1E6 <= cp <= 0x1F1FF or 0x1FA70 <= cp <= 0x1FAFF:
        return False
    return unicodedata.category(c) not in ("Cc", "Cs", "Co", "Cn")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--min", type=int, default=1000)
    parser.add_argument("--dir", default="jokes")
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parent.parent / args.dir
    seen = {}
    problems = []
    per_file = {}
    for path in sorted(root.glob("*.txt")):
        count = 0
        for n, raw in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            where = f"{path.name}:{n}"
            if line.count("|") > 1:
                problems.append(f"{where} : plus d'un séparateur '|'")
            parts = line.split("|")
            if any(not p.strip() for p in parts):
                problems.append(f"{where} : question ou réponse vide")
            bad = sorted({f"U+{ord(c):04X}" for c in line if not shown(c)})
            if bad:
                problems.append(f"{where} : caractère mal affiché par Orbit ({', '.join(bad)})")
            key = norm(line)
            if key in seen:
                problems.append(f"{where} : doublon de {seen[key]}")
                continue
            seen[key] = where
            count += 1
        per_file[path.name] = count

    for name, count in per_file.items():
        print(f"{count:5d}  {name}")
    print(f"{len(seen):5d}  entrées différentes au total ({args.dir})")
    for p in problems:
        print("ERREUR", p)
    if len(seen) < args.min:
        print(f"ERREUR il en faut au moins {args.min}")
    return 1 if problems or len(seen) < args.min else 0


if __name__ == "__main__":
    sys.exit(main())

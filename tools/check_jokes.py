"""Vérifie les blagues de jokes/*.txt : compte, doublons et format.

Usage : python tools/check_jokes.py [--min 1000]
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--min", type=int, default=1000)
    args = parser.parse_args()

    root = pathlib.Path(__file__).resolve().parent.parent / "jokes"
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
            key = norm(line)
            if key in seen:
                problems.append(f"{where} : doublon de {seen[key]}")
                continue
            seen[key] = where
            count += 1
        per_file[path.name] = count

    for name, count in per_file.items():
        print(f"{count:5d}  {name}")
    print(f"{len(seen):5d}  blagues différentes au total")
    for p in problems:
        print("ERREUR", p)
    if len(seen) < args.min:
        print(f"ERREUR il en faut au moins {args.min}")
    return 1 if problems or len(seen) < args.min else 0


if __name__ == "__main__":
    sys.exit(main())

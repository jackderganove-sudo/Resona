#!/usr/bin/env python3
"""Add Resona UI strings: English keys go into en.json (key == value unless
given), German translations into de.json. Usage: add_strings.py <json-file>
where the file maps English key -> German text (or [english, german])."""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANG = ROOT / "languages"


def main() -> None:
    additions = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    en = json.loads((LANG / "en.json").read_text(encoding="utf-8"))
    de_path = LANG / "de.json"
    de = json.loads(de_path.read_text(encoding="utf-8")) if de_path.exists() else {}
    for key, value in additions.items():
        english, german = (value if isinstance(value, list) else [key, value])
        en.setdefault(key, english)
        de[key] = german
    (LANG / "en.json").write_text(json.dumps(en, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    de_path.write_text(json.dumps(dict(sorted(de.items())), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"en: {len(en)} keys, de: {len(de)} keys")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Builds MealRoutine/Localizable.xcstrings from the Swift sources.

Turkish (`tr`) is the development language, so the app renders exactly the copy it had before
the catalog existed.

  - Keyed strings: every `L10n.text("key", "Türkçe")` / `L10n.format("key", "Türkçe %@", ...)` call
    (and `ShareL10n.text`, used by files the share extension compiles) becomes a `manual` entry whose `tr` value is the source text passed in code.
  - SwiftUI literals: plain `Text("…")`, `Button("…")`, `Label("…", …)` and similar literals without
    interpolation become entries keyed by their Turkish text (Xcode's own extraction format).
    Interpolated literals are added by Xcode's string extraction on the Mac build.

  python3 Tools/build_string_catalog.py          # rewrite the catalog
  python3 Tools/build_string_catalog.py --check  # fail if the catalog is stale or inconsistent
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "MealRoutine"
SHARE = ROOT / "ShareExtension"  # reads the app's catalog through `ShareL10n`
CATALOG = APP / "Localizable.xcstrings"
SOURCE_LANGUAGE = "tr"

STRING = r'"((?:[^"\\\n]|\\.)*)"'
KEYED = re.compile(r"L10n\.(?:text|format)\(\s*" + STRING + r"\s*,\s*" + STRING)
SWIFTUI = re.compile(
    r"\b(?:Text|Button|Label|Toggle|TextField|SecureField|Section|Picker|Stepper|LabeledContent|Link|Menu|"
    r"ContentUnavailableView|navigationTitle|alert|confirmationDialog)\(\s*" + STRING
)
KEY_SHAPE = re.compile(r"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9_]+)+$")


def unescape(literal: str) -> str:
    return re.sub(r"\\(.)", lambda match: {"n": "\n", "t": "\t", '"': '"', "\\": "\\", "'": "'"}.get(match.group(1), match.group(0)), literal)


def collect():
    keyed = {}
    literals = set()
    problems = []
    for file in sorted([*APP.rglob("*.swift"), *SHARE.rglob("*.swift")]):
        source = file.read_text()
        relative = file.relative_to(ROOT)
        for match in KEYED.finditer(source):
            key, text = unescape(match.group(1)), unescape(match.group(2))
            if not KEY_SHAPE.match(key):
                problems.append(f"{relative}: key {key!r} is not a dotted identifier")
            if key in keyed and keyed[key][0] != text:
                problems.append(f"{relative}: key {key} has two source texts: {keyed[key][0]!r} and {text!r} ({keyed[key][1]})")
            keyed.setdefault(key, (text, str(relative)))
        for match in SWIFTUI.finditer(source):
            literal = match.group(1)
            if "\\(" in literal or not literal.strip():
                continue
            literals.add(unescape(literal))
    return keyed, literals, problems


def build(keyed, literals):
    strings = {}
    for literal in sorted(literals):
        if literal in keyed:
            continue
        strings[literal] = {}
    for key, (text, _) in sorted(keyed.items()):
        strings[key] = {
            "extractionState": "manual",
            "localizations": {SOURCE_LANGUAGE: {"stringUnit": {"state": "translated", "value": text}}},
        }
    return {"sourceLanguage": SOURCE_LANGUAGE, "strings": dict(sorted(strings.items())), "version": "1.0"}


def main() -> int:
    keyed, literals, problems = collect()
    catalog = build(keyed, literals)
    rendered = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=False) + "\n"
    if "--check" in sys.argv:
        if not CATALOG.exists():
            problems.append("MealRoutine/Localizable.xcstrings is missing; run Tools/build_string_catalog.py")
        else:
            current = json.loads(CATALOG.read_text())
            if current.get("sourceLanguage") != SOURCE_LANGUAGE:
                problems.append("catalog source language is not tr")
            entries = current.get("strings", {})
            for key, (text, where) in keyed.items():
                value = entries.get(key, {}).get("localizations", {}).get(SOURCE_LANGUAGE, {}).get("stringUnit", {}).get("value")
                if value != text:
                    problems.append(f"catalog {key} is {value!r}, code ({where}) uses {text!r}")
            for literal in literals:
                if literal not in entries:
                    problems.append(f"catalog lacks SwiftUI literal {literal!r}")
        if problems:
            print("\n".join(problems))
            return 1
        print(f"string catalog OK ({len(keyed)} keyed, {len(literals)} SwiftUI literals)")
        return 0
    if problems:
        print("\n".join(problems))
        return 1
    CATALOG.write_text(rendered)
    print(f"wrote {CATALOG.relative_to(ROOT)} ({len(catalog['strings'])} entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

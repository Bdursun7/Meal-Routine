#!/usr/bin/env python3
"""Adds files to MealRoutine.xcodeproj without Xcode.

The project uses explicit groups (no folder references), so every new source or resource file
needs a PBXFileReference in its group and a PBXBuildFile in each target phase that builds it.

  python3 Tools/pbx_add_files.py --group <group id> --phase <phase id> [--phase ...] NAME [NAME ...]

NAME is the file name inside the group's folder. IDs are derived from the group and name, so a
second run is a no-op. `Tools/check_xcodeproj.py` verifies the result.
"""
import argparse
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PBX = ROOT / "MealRoutine.xcodeproj" / "project.pbxproj"

FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".json": "text.json",
    ".xcstrings": "text.json.xcstrings",
    ".strings": "text.plist.strings",
}


def make_id(*parts: str) -> str:
    return hashlib.sha1("/".join(parts).encode()).hexdigest()[:24].upper()


def phase_kind(text: str, phase: str) -> str:
    match = re.search(re.escape(phase) + r" /\* (\w+) \*/ = \{", text)
    if not match:
        sys.exit(f"phase {phase} not found")
    return match.group(1)


def insert_into_list(text: str, owner: str, key: str, line: str) -> str:
    pattern = re.compile(re.escape(owner) + r" /\*[^*]*\*/ = \{.*?" + key + r" = \(\n(.*?)\n(\t*)\);", re.S)
    match = pattern.search(text)
    if not match:
        sys.exit(f"{owner} has no {key} list")
    body = match.group(1)
    if line.strip() in body:
        return text
    entries = [row for row in body.split("\n") if row.strip()]
    indent = re.match(r"\t*", entries[0]).group(0) if entries else match.group(2) + "\t"
    entries.append(indent + line.strip())
    start, end = match.span(1)
    return text[:start] + "\n".join(entries) + text[end:]


def insert_section_row(text: str, section: str, row: str) -> str:
    marker = f"/* End {section} section */"
    if row.strip() in text:
        return text
    return text.replace(marker, f"\t\t{row}\n{marker}", 1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--group", required=True)
    parser.add_argument("--phase", action="append", default=[])
    parser.add_argument("names", nargs="+")
    args = parser.parse_args()
    text = PBX.read_text()
    for name in args.names:
        suffix = Path(name).suffix
        file_type = FILE_TYPES.get(suffix)
        if not file_type:
            sys.exit(f"unknown file type for {name}")
        ref = make_id("ref", args.group, name)
        text = insert_section_row(
            text,
            "PBXFileReference",
            f'{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {name}; sourceTree = "<group>"; }};',
        )
        text = insert_into_list(text, args.group, "children", f"{ref} /* {name} */,")
        for phase in args.phase:
            kind = phase_kind(text, phase)
            build = make_id("build", phase, args.group, name)
            text = insert_section_row(
                text,
                "PBXBuildFile",
                f"{build} /* {name} in {kind} */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};",
            )
            text = insert_into_list(text, phase, "files", f"{build} /* {name} in {kind} */,")
    PBX.write_text(text)


if __name__ == "__main__":
    main()

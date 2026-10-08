#!/usr/bin/env python3
"""Linux check that MealRoutine.xcodeproj matches the files on disk.

The project uses explicit groups, so a Swift file that exists on disk but is missing from its
target's Sources phase compiles nowhere and breaks the Mac build. This check fails when:
  - a .swift file under MealRoutine/, MealRoutineTests/, MealRoutineUITests/ or ShareExtension/
    is not built by the matching target (app, unit tests, UI tests, share extension);
  - a file reference points at a path that does not exist;
  - a required resource (recipe catalog, ingredient dictionary, string catalog) is not in the
    app's Resources phase;
  - a Swift file contains an Xcode placeholder (<#...#>);
  - two app Swift files declare the same top-level type name.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PBX = ROOT / "MealRoutine.xcodeproj" / "project.pbxproj"

TARGET_DIRS = {
    "MealRoutine": "MealRoutine",
    "MealRoutineTests": "MealRoutineTests",
    "MealRoutineUITests": "MealRoutineUITests",
    "ShareExtension": "MealRoutineShare",
}
REQUIRED_RESOURCES = [
    "MealRoutine/Recipes/recipes.v1.json",
    "MealRoutine/Recipes/ingredients.v2.json",
    "MealRoutine/Localizable.xcstrings",
]


def objects(text: str) -> dict:
    found = {}
    for match in re.finditer(r"^\t\t([0-9A-Za-z]{6,32})(?: /\*[^\n]*?\*/)? = \{\n(.*?)\n\t\t\};$", text, re.M | re.S):
        found[match.group(1)] = match.group(2)
    for match in re.finditer(r"^\t\t([0-9A-Za-z]{6,32}) (?:/\*[^\n]*?\*/ )?= (\{[^\n]*\});$", text, re.M):
        found[match.group(1)] = match.group(2)
    return found


def field(body: str, key: str):
    match = re.search(r"\b" + key + r' = ("(?:[^"\\]|\\.)*"|[^;]+);', body)
    if not match:
        return None
    value = match.group(1)
    return value[1:-1] if value.startswith('"') else value


def id_list(body: str, key: str):
    match = re.search(r"\b" + key + r" = \((.*?)\);", body, re.S)
    return re.findall(r"([0-9A-Za-z]{6,32}) /\*", match.group(1)) if match else []


def main() -> int:
    text = PBX.read_text()
    objs = objects(text)
    problems = []

    paths = {}

    def walk(group_id: str, base: Path):
        body = objs.get(group_id, "")
        path = field(body, "path")
        here = base / path if path and field(body, "sourceTree") == "<group>" else base
        for child in id_list(body, "children"):
            child_body = objs.get(child, "")
            if "isa = PBXGroup" in child_body or "isa = PBXVariantGroup" in child_body:
                walk(child, here)
            elif "isa = PBXFileReference" in child_body:
                child_path = field(child_body, "path")
                if child_path and field(child_body, "sourceTree") == "<group>":
                    paths[child] = here / child_path

    project = next(body for body in objs.values() if "isa = PBXProject" in body)
    walk(field(project, "mainGroup"), ROOT)

    for ref, path in paths.items():
        if not path.exists():
            problems.append(f"missing on disk: {path.relative_to(ROOT)}")

    targets = {}
    for body in objs.values():
        if "isa = PBXNativeTarget" not in body:
            continue
        name = field(body, "name")
        built = {}
        for phase in id_list(body, "buildPhases"):
            phase_body = objs.get(phase, "")
            kind = re.search(r"isa = (\w+)", phase_body).group(1)
            for build in id_list(phase_body, "files"):
                ref = field(objs.get(build, ""), "fileRef")
                ref = ref.split(" ")[0] if ref else None
                if ref in paths:
                    built.setdefault(kind, set()).add(paths[ref].resolve())
        targets[name] = built

    for directory, target in TARGET_DIRS.items():
        sources = targets.get(target, {}).get("PBXSourcesBuildPhase", set())
        for file in sorted((ROOT / directory).rglob("*.swift")):
            if file.resolve() not in sources:
                problems.append(f"{file.relative_to(ROOT)} is not in the {target} Sources phase")

    resources = targets.get("MealRoutine", {}).get("PBXResourcesBuildPhase", set())
    for required in REQUIRED_RESOURCES:
        if (ROOT / required).resolve() not in resources:
            problems.append(f"{required} is not in the MealRoutine Resources phase")

    declared = {}
    for file in sorted((ROOT / "MealRoutine").rglob("*.swift")):
        source = file.read_text()
        if "<#" in source:
            problems.append(f"{file.relative_to(ROOT)} contains an Xcode placeholder")
        for name in re.findall(r"^(?:public |private |fileprivate |internal |final )*(?:struct|class|enum|protocol|actor) (\w+)", source, re.M):
            declared.setdefault(name, []).append(str(file.relative_to(ROOT)))
    for name, files in declared.items():
        if len(files) > 1:
            problems.append(f"type {name} is declared in {', '.join(files)}")

    for file in sorted(list((ROOT / "MealRoutineTests").rglob("*.swift")) + list((ROOT / "MealRoutineUITests").rglob("*.swift"))):
        if "<#" in file.read_text():
            problems.append(f"{file.relative_to(ROOT)} contains an Xcode placeholder")

    if problems:
        print("\n".join(problems))
        return 1
    counts = ", ".join(f"{name}: {len(kinds.get('PBXSourcesBuildPhase', set()))} sources" for name, kinds in sorted(targets.items()))
    print(f"xcodeproj OK ({counts})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

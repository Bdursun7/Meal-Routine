#!/usr/bin/env python3
"""Linux check for catalog fingerprint equality and planned-meal orphan repair.

Mirrors MealRoutine/Services/Catalog/CatalogIntegrity.swift.
Run from anywhere:

    python3 Tools/catalog_integrity_check.py
"""

from __future__ import annotations

import pathlib

FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
MASK64 = 0xFFFFFFFFFFFFFFFF


def fnv1a64_hex(data: bytes) -> str:
    hash_value = FNV_OFFSET
    for byte in data:
        hash_value ^= byte
        hash_value = (hash_value * FNV_PRIME) & MASK64
    return f"{hash_value:016x}"


def token(schema_version: int, catalog_file_bytes: bytes) -> str:
    return f"{schema_version}:{fnv1a64_hex(catalog_file_bytes)}"


def should_skip_import(
    stored_fingerprint: str | None,
    current_fingerprint: str,
    existing_recipe_count: int,
    catalog_recipe_count: int,
) -> bool:
    if existing_recipe_count <= 0 or existing_recipe_count != catalog_recipe_count:
        return False
    if not stored_fingerprint:
        return False
    return stored_fingerprint == current_fingerprint


def orphaned_slugs(planned_slugs: list[str], live_recipe_slugs: set[str]) -> list[str]:
    seen: set[str] = set()
    orphans: list[str] = []
    for slug in planned_slugs:
        if slug in live_recipe_slugs or slug in seen:
            continue
        seen.add(slug)
        orphans.append(slug)
    return orphans


def decide(
    current_week_slugs: list[str],
    other_week_slugs: list[str],
    live_recipe_slugs: set[str],
    can_regenerate_current_week: bool,
) -> tuple[bool, list[str]]:
    current_orphans = orphaned_slugs(current_week_slugs, live_recipe_slugs)
    other_orphans = orphaned_slugs(other_week_slugs, live_recipe_slugs)
    if current_orphans and can_regenerate_current_week:
        return True, other_orphans
    leftovers = orphaned_slugs(current_week_slugs + other_week_slugs, live_recipe_slugs)
    return False, leftovers


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def main() -> None:
    expect(fnv1a64_hex(b"") == "cbf29ce484222325", "empty FNV-1a 64")
    expect(fnv1a64_hex(b"a") == "af63dc4c8601ec8c", "FNV-1a 64 of 'a'")
    expect(fnv1a64_hex(b"foobar") == "85944171f73967e8", "FNV-1a 64 of 'foobar'")

    same = token(1, b'{"schemaVersion":1,"recipes":[{"id":"a"}]}')
    edited = token(1, b'{"schemaVersion":1,"recipes":[{"id":"b"}]}')
    expect(same != edited, "same-sized payload edit changes the fingerprint")
    expect(token(1, b"x") != token(2, b"x"), "schemaVersion is part of the token")

    expect(
        should_skip_import(same, same, 125, 125) is True,
        "matching fingerprint and full catalog skips",
    )
    expect(
        should_skip_import(same, edited, 125, 125) is False,
        "same recipe count with a new fingerprint re-imports",
    )
    expect(
        should_skip_import(None, same, 125, 125) is False,
        "missing stored fingerprint re-imports",
    )
    expect(
        should_skip_import("", same, 125, 125) is False,
        "empty stored fingerprint re-imports",
    )
    expect(
        should_skip_import(same, same, 10, 125) is False,
        "short store re-imports even when the fingerprint matches",
    )
    expect(
        should_skip_import(same, same, 0, 0) is False,
        "empty catalog does not skip",
    )

    live = {"soup", "stew"}
    expect(orphaned_slugs(["soup", "gone", "gone", "stew"], live) == ["gone"], "orphan dedupe")
    expect(orphaned_slugs(["soup"], live) == [], "live slug is kept")

    regenerate, delete_slugs = decide(
        current_week_slugs=["soup", "missing"],
        other_week_slugs=["old-missing", "stew"],
        live_recipe_slugs=live,
        can_regenerate_current_week=True,
    )
    expect(regenerate is True, "current-week orphan regenerates the week")
    expect(delete_slugs == ["old-missing"], "other weeks still drop their orphans")

    regenerate, delete_slugs = decide(
        current_week_slugs=["soup", "missing"],
        other_week_slugs=["old-missing"],
        live_recipe_slugs=live,
        can_regenerate_current_week=False,
    )
    expect(regenerate is False, "without preferences, do not regenerate")
    expect(delete_slugs == ["missing", "old-missing"], "delete orphans in place")

    regenerate, delete_slugs = decide(
        current_week_slugs=["soup", "stew"],
        other_week_slugs=["old-missing"],
        live_recipe_slugs=live,
        can_regenerate_current_week=True,
    )
    expect(regenerate is False, "a coherent current week is left alone")
    expect(delete_slugs == ["old-missing"], "past-week orphans are removed")

    regenerate, delete_slugs = decide(
        current_week_slugs=["soup"],
        other_week_slugs=[],
        live_recipe_slugs=live,
        can_regenerate_current_week=True,
    )
    expect(regenerate is False and delete_slugs == [], "no orphans is a no-op")

    root = pathlib.Path(__file__).resolve().parents[1]
    integrity = (root / "MealRoutine/Services/Catalog/CatalogIntegrity.swift").read_text()
    seed = (root / "MealRoutine/Services/RecipeSeedService.swift").read_text()
    expect("0xcbf29ce484222325" in integrity, "Swift hash uses the FNV offset basis")
    expect("0x100000001b3" in integrity, "Swift hash uses the FNV prime")
    expect("storedFingerprint == currentFingerprint" in integrity, "skip compares fingerprints")
    expect("existingCount ==" not in seed, "seed no longer skips on count alone")
    expect("shouldSkipImport" in seed, "seed uses the fingerprint gate")
    expect("PlanIntegrityService.repair" in seed, "seed repairs orphaned meals")
    expect("GroceryListService.rebuild" in seed, "seed rebuilds the grocery list")

    catalog = (root / "MealRoutine/Recipes/recipes.v1.json").read_bytes()
    original = token(1, catalog)
    expect(token(1, catalog) == original, "catalog fingerprint is stable")
    mutated = bytearray(catalog)
    mutated[0] ^= 0x01
    expect(token(1, bytes(mutated)) != original, "a catalog byte change re-imports")

    print("ok")


if __name__ == "__main__":
    main()

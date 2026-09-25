#!/usr/bin/env python3
"""Fill catalog `tags` from a deterministic ruleset.

Axes are style, format, starch, and heat. Cuisine, country, and protein family
are already scored by MealRecommender, so those words are not tags. Course
(`soup`, `salad`, `main`, `breakfast`) is already `unitoolsCategory`, so it is
not repeated here either.

Re-run from the repo root after a catalog refresh:

    python3 Tools/recipe_tags.py --write

Without `--write` the script prints the tags it would assign and exits 0.
The allowlist below is the vocabulary. Tools/catalog_integrity_check.py and
Tools/meal_recommender_checks.swift both refuse tags outside it.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

# Canonical order is the order written into JSON.
ALLOWLIST = (
    "quick",
    "slow",
    "spicy",
    "cold",
    "pasta",
    "noodle",
    "dumpling",
    "rice",
    "potato",
    "bread",
    "bulgur",
    "one-pan",
    "grill",
    "fry",
    "stir-fry",
    "bake",
    "stew",
    "curry",
    "steam",
    "pie",
    "stuffed",
)

MAX_TAGS = 5
MIN_TAGS = 1

# Drop these first when a dish matches more than MAX_TAGS.
# Common starches and time flags move the week, but a second shared format
# tag is the signal we most want to keep.
DROP_FIRST = (
    "potato",
    "rice",
    "bulgur",
    "bread",
    "quick",
    "slow",
    "cold",
    "spicy",
    "steam",
    "stew",
    "curry",
    "bake",
    "fry",
    "grill",
    "stir-fry",
    "one-pan",
    "pie",
    "stuffed",
    "dumpling",
    "noodle",
    "pasta",
)

# Heat that changes the plate. Sweet paprika and bell pepper are absent on purpose.
# Kashmiri chilli is colour more than burn; rogan josh says so in the summary,
# and the id is left out here so that sentence is not the only guard.
SPICY_IDS = frozenset(
    {
        "aji",
        "ajiamarillo",
        "ancho",
        "berbere",
        "biber",
        "chili",
        "chilli",
        "chillies",
        "chilipaste",
        "chilipowder",
        "chillipowder",
        "driedchili",
        "driedchilli",
        "doubanjiang",
        "gochujang",
        "greenchili",
        "greenchilli",
        "guajillo",
        "harissa",
        "mitmita",
        "pepperflakes",
        "piripiri",
        "sambal",
        "scotchbonnet",
        "zhug",
    }
)

PASTA_IDS = frozenset({"spaghetti", "bucatini", "macaroni"})
NOODLE_IDS = frozenset({"ricenoodles", "noodles"})
# Bread that is the plate, not a thickener or a slice on the side.
BREAD_IDS = frozenset(
    {
        "bagel",
        "baguette",
        "bun",
        "fatir",
        "flatbread",
        "injera",
        "naan",
        "pide",
        "pita",
        "roti",
        "somun",
        "tortillas",
    }
)
# Dough dishes whose flour never shows up as a bread ingredient id.
BREAD_SLUGS = frozenset({
    "fondue-moitie-moitie",
    "lahmacun",
    "pizza-margherita",
    # Turkish flatbreads whose dough is flour, not a bread ingredient id.
    "kiymali-pide",
    "kusbasili-pide",
    "kasarli-pide",
    "peynirli-gozleme",
    "kiymali-gozleme",
    "patatesli-gozleme",
    # Lavash or bread is the plate; the dough is not a separate bread id on döner.
    "ev-usulu-tavuk-doner",
})

# Single skillet or pot, where the summary never says "one pan".
# Stir-fries, risotto, paella, khichuri, and the two Italian pan pastas are rules.
# Long stews stay on `stew` so they do not also pay `one-pan`.
ONE_PAN_SLUGS = frozenset(
    {
        "beef-stroganoff",
        "bhuna-khichuri",
        "galayet-bandora",
        "kottu-roti",
        "mapo-tofu",
        "menemen",
        "palak-paneer",
        "tortilla-espanola",
    }
)
PAN_PASTA_SLUGS = frozenset({"bucatini-all-amatriciana", "spaghetti-carbonara"})

# Summaries that never say the format. Each one is the dish, not a step verb.
STIR_FRY_SLUGS = frozenset(
    {
        "char-kway-teow",
        "gong-bao-chicken",
        "lok-lak",
        "lomo-saltado",
        "nasi-goreng",
        "pad-krapow-moo",
        "pad-thai",
        "yangzhou-fried-rice",
    }
)
DUMPLING_SLUGS = frozenset(
    {
        "bryndzove-halusky",
        "khinkali",
        "manti-turkish",
        "pierogi-ruskie",
    }
)

# Rules over-fire here. Documented so a refresh does not put them back.
REMOVE = {
    # Curry is an ingredient in the griddle chop, not the format.
    "kottu-roti": frozenset({"curry"}),
    # "Fried before the water goes in" is a temper, and one-pan already marks the pot.
    "bhuna-khichuri": frozenset({"fry"}),
    # "Not fried" describes the potato. The negation guard covers the summary;
    # this stays so a step that says "fried" cannot leak back in.
    "tortilla-espanola": frozenset({"fry"}),
}

# Rules miss the diner-facing format. Keep these few and specific.
ADD = {
    # Baked on taboon; the summary only mentions the bread.
    "musakhan": frozenset({"bake"}),
    # Pan-fried meatballs. The summary jumps to the cream sauce.
    "koettbullar": frozenset({"fry"}),
    # Butter chicken is a curry; the summary says "tomato and cream sauce".
    "murgh-makhani": frozenset({"curry"}),
    # Paneer in a spiced spinach gravy. Same gap as butter chicken.
    "palak-paneer": frozenset({"curry"}),
    # Yoghurt-sauce braise. Summary never says curry, and Kashmiri chilli is colour.
    "rogan-josh": frozenset({"curry"}),
    # Pancakes dipped in a pot of gravy. The summary says gravy, not stew.
    "machanka": frozenset({"stew"}),
}


def _blob(recipe: dict) -> str:
    name = (recipe.get("name") or {}).get("en") or ""
    summary = (recipe.get("summary") or {}).get("en") or ""
    native = recipe.get("nativeName") or ""
    return f"{recipe.get('id', '')} {name} {native} {summary}".lower()


def _ids(recipe: dict) -> list[str]:
    found = []
    for ingredient in recipe.get("ingredients") or []:
        ingredient_id = ingredient.get("id")
        if isinstance(ingredient_id, str) and ingredient_id.strip():
            found.append(ingredient_id.strip().lower())
    return found


def _search(pattern: str, blob: str) -> bool:
    return re.search(pattern, blob) is not None


def _cap(tags: set[str]) -> list[str]:
    ordered = [tag for tag in ALLOWLIST if tag in tags]
    if len(ordered) <= MAX_TAGS:
        return ordered
    kept = set(ordered)
    for tag in DROP_FIRST:
        if len(kept) <= MAX_TAGS:
            break
        kept.discard(tag)
    return [tag for tag in ALLOWLIST if tag in kept]


def assign_tags(recipe: dict) -> list[str]:
    """Return 1–5 allowlisted tags for one catalog recipe."""
    slug = str(recipe.get("id") or "")
    blob = _blob(recipe)
    ingredient_ids = _ids(recipe)
    id_set = set(ingredient_ids)
    total = int(recipe.get("totalMinutes") or 0)
    cook = int(recipe.get("cookMinutes") or 0)
    tags: set[str] = set()

    if total <= 30:
        tags.add("quick")
    elif total >= 90:
        tags.add("slow")

    if id_set & SPICY_IDS and not _search(r"rather than from heat", blob):
        tags.add("spicy")

    # "Cold watermelon", "raw onion", and "ice-cold batter" are not cold plates.
    if (
        cook == 0
        or _search(r"\ba cold\b", blob)
        or _search(r"\braw (?:beef|lamb|fish|kibbeh)\b", blob)
    ):
        tags.add("cold")

    if (
        id_set & PASTA_IDS
        or "spaetzle" in slug
        or _search(r"\b(pastas?|spaetzle|spätzle)\b", blob)
    ):
        tags.add("pasta")
    if (id_set & NOODLE_IDS or _search(r"\bnoodles?\b", blob)) and "pasta" not in tags:
        tags.add("noodle")

    if slug in DUMPLING_SLUGS or _search(r"\bdumplings?\b", blob):
        tags.add("dumpling")

    if "rice" in id_set:
        tags.add("rice")

    potato_named = _search(r"\b(potatoes|potato|chips|rösti|rosti)\b", blob)
    potato_leads = any(ingredient in {"potato", "potatoes"} for ingredient in ingredient_ids[:2])
    # Fries are the plate's potato. A buried soup potato (mercimek) is not.
    if "fries" in id_set or (
        ("potato" in id_set or "potatoes" in id_set) and (potato_named or potato_leads)
    ):
        tags.add("potato")

    if "bulgur" in id_set:
        tags.add("bulgur")

    if id_set & BREAD_IDS or slug in BREAD_SLUGS:
        tags.add("bread")

    if "filo" in id_set or _search(r"\bpies?\b", blob):
        tags.add("pie")
        tags.add("bake")

    if _search(r"\b(grills?|grilled|grilling|skewers?|coals|barbie)\b", blob):
        tags.add("grill")

    stir = slug in STIR_FRY_SLUGS or _search(r"\b(stir-fry|stir fry|fried rice|wok)\b", blob)
    if stir or slug.startswith("pad-"):
        tags.add("stir-fry")

    fried = blob
    fried = re.sub(r"\bnot fried\b", " ", fried)
    fried = re.sub(r"\bfried onions?\b", " ", fried)
    fried = re.sub(r"\bfried pieces of flatbread\b", " ", fried)
    fried = re.sub(r"\bfried eggs?\b", " ", fried)
    fried = re.sub(r"\bfried mantou\b", " ", fried)
    if "stir-fry" not in tags and (
        _search(r"\b(schnitzel|tempura|breaded|crumbed|patties)\b", blob)
        or _search(r"\bfried\b", fried)
    ):
        tags.add("fry")

    if _search(r"\b(bake|baked|baking|oven)\b", blob) or "pie" in tags or slug.startswith("pizza"):
        tags.add("bake")

    if _search(r"\bcurry\b", blob) or id_set & {"curry", "currypowder", "currysauce"}:
        tags.add("curry")
    else:
        stew_blob = re.sub(r"\b(?:must )?not(?: be)? stewed\b", " ", blob)
        if (
            _search(r"\b(stews?|stewed|stewing|braised|braising)\b", stew_blob)
            or slug.startswith("dal-")
            or _search(r"\bwat\b", slug)
        ):
            tags.add("stew")

    # Hot soups eat like a pot stew. Cold and quick soups stay off this tag so
    # gazpacho does not share it with dal. Course is still scored separately.
    if (
        recipe.get("unitoolsCategory") == "soup"
        and "cold" not in tags
        and "quick" not in tags
        and "curry" not in tags
    ):
        tags.add("stew")

    if _search(r"\bsteam(?:ed|ing)?\b", blob):
        tags.add("steam")

    if _search(r"\bstuffed\b", blob):
        tags.add("stuffed")

    one_pan = (
        slug in ONE_PAN_SLUGS
        or slug in PAN_PASTA_SLUGS
        or "stir-fry" in tags
        or _search(r"\b(risotto|paella|khichuri|one[- ]pan|skillet)\b", blob)
    )
    if one_pan:
        tags.add("one-pan")

    tags |= ADD.get(slug, frozenset())
    tags -= REMOVE.get(slug, frozenset())

    # A pie that is also marked fry from "fried onion" should stay a pie.
    if "pie" in tags:
        tags.discard("fry")

    chosen = _cap(tags)
    if len(chosen) < MIN_TAGS:
        raise ValueError(f"{slug or '?'} produced no tags")
    unknown = [tag for tag in chosen if tag not in ALLOWLIST]
    if unknown:
        raise ValueError(f"{slug} has tags outside the allowlist: {unknown}")
    return chosen


def load_catalog(path: pathlib.Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def assign_catalog(catalog: dict) -> dict[str, list[str]]:
    recipes = catalog.get("recipes")
    if not isinstance(recipes, list):
        raise SystemExit("catalog has no recipes array")
    assigned: dict[str, list[str]] = {}
    for recipe in recipes:
        slug = recipe.get("id")
        if not isinstance(slug, str) or not slug:
            raise SystemExit("recipe missing id")
        if slug in assigned:
            raise SystemExit(f"duplicate recipe id {slug}")
        assigned[slug] = assign_tags(recipe)
    return assigned


def write_tags(path: pathlib.Path, assigned: dict[str, list[str]]) -> None:
    """Replace each recipe `tags` array in file order. Safe to re-run."""
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(r'"tags": \[[^\]]*\]')
    matches = list(pattern.finditer(text))
    if len(matches) != len(assigned):
        raise SystemExit(f"expected {len(assigned)} tags arrays, found {len(matches)}")
    for match, tags in zip(reversed(matches), reversed(list(assigned.values()))):
        rendered = '"tags": ' + json.dumps(tags, ensure_ascii=False)
        text = text[: match.start()] + rendered + text[match.end() :]
    path.write_text(text, encoding="utf-8")


def main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(description="Assign MealRoutine recipe tags.")
    parser.add_argument(
        "--catalog",
        type=pathlib.Path,
        default=pathlib.Path("MealRoutine/Recipes/recipes.v1.json"),
    )
    parser.add_argument("--write", action="store_true", help="write the ruleset into every recipe tags array")
    args = parser.parse_args(argv)
    catalog = load_catalog(args.catalog)
    assigned = assign_catalog(catalog)
    if args.write:
        write_tags(args.catalog, assigned)
    else:
        for slug, tags in assigned.items():
            print(f"{slug}\t{','.join(tags)}")
    from collections import Counter

    counts: Counter[str] = Counter()
    widths: Counter[int] = Counter()
    for tags in assigned.values():
        widths[len(tags)] += 1
        counts.update(tags)
    print(f"# recipes {len(assigned)}", file=sys.stderr)
    print(f"# tags per recipe {dict(sorted(widths.items()))}", file=sys.stderr)
    for tag, count in counts.most_common():
        print(f"# {count:3} {tag}", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1:])

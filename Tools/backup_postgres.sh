#!/usr/bin/env bash
# Daily Postgres dump for the Mac that hosts MealRoutine. Keeps 7 newest files.
# Not run by the repo. launchd calls it; see Tools/launchd and docs/testflight-mac-runbook.md.
set -euo pipefail

dest="${MEALROUTINE_BACKUP_DIR:-$HOME/Backups/mealroutine}"
mkdir -p "$dest"
stamp="$(date +%Y%m%d-%H%M%S)"
pg_dump -h localhost -p 5433 -Fc -d mealroutine -f "$dest/mealroutine-$stamp.dump"

count=0
while IFS= read -r file; do
  count=$((count + 1))
  if [[ "$count" -gt 7 ]]; then
    rm -f "$file"
  fi
done < <(ls -1t "$dest"/mealroutine-*.dump 2>/dev/null || true)
echo "Wrote $dest/mealroutine-$stamp.dump"

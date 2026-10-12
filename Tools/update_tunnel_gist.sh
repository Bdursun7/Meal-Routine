#!/usr/bin/env bash
# Reads the newest trycloudflare URL from the cloudflared log and writes it
# into a public gist file as {"apiBaseURL":"https://….trycloudflare.com"}.
# Run on the Mac that hosts the tunnel. Requires `gh auth status` to succeed.
#
#   MEALROUTINE_GIST_ID=abc123 Tools/update_tunnel_gist.sh
#
# Optional:
#   MEALROUTINE_TUNNEL_LOG  default ~/Library/Logs/mealroutine-tunnel.log
#   MEALROUTINE_GIST_FILE   default server.json (the name inside the gist)
set -euo pipefail

LOG="${MEALROUTINE_TUNNEL_LOG:-$HOME/Library/Logs/mealroutine-tunnel.log}"
GIST_ID="${MEALROUTINE_GIST_ID:-}"
FILE="${MEALROUTINE_GIST_FILE:-server.json}"

if [[ -z "$GIST_ID" ]]; then
  echo "MEALROUTINE_GIST_ID is required. Create the gist first; see docs/testflight-mac-runbook.md." >&2
  exit 1
fi
if [[ ! -f "$LOG" ]]; then
  echo "Tunnel log not found: $LOG" >&2
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "gh is not on PATH." >&2
  exit 1
fi

URL="$(grep -oE 'https://[A-Za-z0-9-]+\.trycloudflare\.com' "$LOG" | tail -n 1 || true)"
if [[ -z "$URL" ]]; then
  echo "No trycloudflare URL in $LOG" >&2
  exit 1
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
printf '{"apiBaseURL":"%s"}\n' "$URL" > "$workdir/$FILE"
gh gist edit "$GIST_ID" -f "$FILE" "$workdir/$FILE"
echo "Updated gist $GIST_ID ($FILE) to $URL"

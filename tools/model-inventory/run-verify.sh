#!/usr/bin/env bash
#
# What the model-inventory timer actually runs.
#
# A scheduled pass that only writes a log file has not told anybody anything. Two outcomes here need the
# operator and neither reaches him on its own:
#
#   1. THE PASS FAILED. A non-zero exit, or a run that finished but wrote no report block, means the inventory
#      was not verified this cycle. Silence looks identical to success.
#   2. THE PASS FOUND DRIFT AND COMMITTED IT TO A BRANCH. This is the more dangerous one. The run "succeeded",
#      the log says so, and a branch nobody knows about sits in agent-tooling for ever. A silent branch is the
#      same failure class as a silent failure.
#
# Both become a CANDIDATE work item in Orbital, which the operator triages or lets age out. The quiet third
# outcome — the pass ran, nothing drifted — surfaces nothing; the log is the record.
#
# If the POST itself fails, that goes in the log and this script exits non-zero, so systemd marks the unit
# failed and the journal is the fallback signal. A surfacing mechanism that can fail silently is worthless.

set -euo pipefail

# systemd --user runs with a minimal PATH that does NOT include ~/.local/bin, which is where `claude`, `node`
# and `jq` actually live on this machine. Without this the unit dies with "claude: command not found" and the
# only clue is the journal. The unit sets PATH too; this is the belt to its braces, and makes the script work
# the same way when a human runs it by hand.
export PATH="$HOME/.local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPT="$SCRIPT_DIR/verify-models.prompt.md"

ORBITAL_URL="${ORBITAL_URL:-https://orbital.20east.io}"
LOG_DIR="${MODEL_INVENTORY_LOG_DIR:-$HOME/.local/share/model-inventory}"
DATE="$(date +%F)"
LOG="$LOG_DIR/verify-$DATE.log"

DRY_RUN=0
FAKE_EXIT=0
FAKE_DRIFT=0

usage() {
  cat <<'USAGE'
run-verify.sh [--dry-run [exit-code] [drift]]

  (no arguments)   Run the verification pass and surface the outcome in Orbital.
  --dry-run        Do NOT call claude and do NOT POST. Print the decision and the exact curl that would be
                   sent, with the Cloudflare Access credentials redacted.
                   exit-code   integer to pretend claude exited with (default 0)
                   drift       the literal word `drift`, to pretend a chore/model-inventory-<date> branch
                               was created with a report block showing drift
USAGE
}

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then FAKE_EXIT="$1"; shift; fi
  if [[ "${1:-}" == "drift" ]]; then FAKE_DRIFT=1; shift; fi
elif [[ $# -gt 0 ]]; then
  usage >&2
  exit 2
fi

mkdir -p "$LOG_DIR"

log() { printf '%s %s\n' "$(date -Is)" "$*" >> "$LOG"; }

# ── Run the pass ──────────────────────────────────────────────────────────────────────────────────────────
#
# `--dangerously-skip-permissions` is operator-approved for this unit (2026-09-08): there is no human awake to
# answer a permission prompt at 05:00, and the pass's scope is held by the prompt's own do-not list (read-only
# subagents, no push, no PR, no merge) rather than by the harness.

REPORT_MARKER='MODEL-INVENTORY-REPORT'

if [[ "$DRY_RUN" == 1 ]]; then
  EXIT_CODE="$FAKE_EXIT"
  if [[ "$FAKE_EXIT" == 0 && "$FAKE_DRIFT" == 1 ]]; then
    REPORT_BODY=$'MODEL-INVENTORY-REPORT\nconfirmed: 38\ndrifted: 2\nnew-sites: 1\nretired: 1\nbranch: chore/model-inventory-'"$DATE"$'\ncommit: 4f1a9c2'
    BRANCH_PRESENT=1
  elif [[ "$FAKE_EXIT" == 0 ]]; then
    REPORT_BODY=$'MODEL-INVENTORY-REPORT\nconfirmed: 41\ndrifted: 0\nnew-sites: 0\nretired: 0\nbranch: none\ncommit: none'
    BRANCH_PRESENT=0
  else
    REPORT_BODY=''
    BRANCH_PRESENT=0
  fi
  echo "[dry-run] would run: cat $PROMPT | claude -p --model sonnet --dangerously-skip-permissions --output-format text"
  echo "[dry-run] log would be: $LOG"
  echo "[dry-run] simulated claude exit code: $EXIT_CODE"
else
  log "starting model inventory verification pass (repo $REPO_ROOT)"
  EXIT_CODE=0
  cd "$REPO_ROOT"
  # `|| EXIT_CODE=$?` rather than a bare pipeline: `set -e` would abort here and the failure would never be
  # surfaced, which is the exact outcome this script exists to prevent.
  cat "$PROMPT" | claude -p --model sonnet --dangerously-skip-permissions --output-format text \
    >> "$LOG" 2>&1 || EXIT_CODE=$?
  log "claude exited $EXIT_CODE"
  REPORT_BODY="$(sed -n "/^$REPORT_MARKER\$/,\$p" "$LOG" || true)"
  BRANCH_PRESENT=0
  if git -C "$REPO_ROOT" rev-parse --verify --quiet "chore/model-inventory-$DATE" >/dev/null 2>&1; then
    BRANCH_PRESENT=1
  fi
fi

field() { printf '%s\n' "$REPORT_BODY" | sed -n "s/^$1: *//p" | head -1; }

# ── Decide what the operator is shown ─────────────────────────────────────────────────────────────────────

SURFACE=none
SOURCE_ID=''
TITLE=''
SUMMARY=''
DETAIL=''

if [[ "$EXIT_CODE" != 0 || -z "$REPORT_BODY" ]]; then
  SURFACE=failed
  SOURCE_ID="model-inventory-verify:$DATE"
  TITLE="Model inventory verification failed on $DATE"
  REASON="exit code $EXIT_CODE"
  [[ -n "$REPORT_BODY" ]] || REASON="$REASON, no $REPORT_MARKER block in the log"
  SUMMARY="The every-14-days model inventory pass did not verify the inventory this cycle ($REASON). MODELS.md is now unverified until someone runs it again. The last 20 lines of the log are below; the whole log is at $LOG."
  if [[ "$DRY_RUN" == 1 ]]; then
    DETAIL=$'(dry run: the last 20 lines of '"$LOG"$' would be quoted here)'
  else
    DETAIL="$(tail -20 "$LOG" 2>/dev/null || echo '(the log could not be read)')"
  fi
elif [[ "$BRANCH_PRESENT" == 1 ]]; then
  SURFACE=drift
  # A DIFFERENT sourceId from the failure case, deliberately. Orbital's mint is idempotent on
  # (source, sourceId), so reusing one key would mean a morning failure silently swallowed an afternoon
  # re-run's drift report — the row would already exist and the drift would never be seen.
  SOURCE_ID="model-inventory-drift:$DATE"
  TITLE="Model inventory drift found $DATE — review branch chore/model-inventory-$DATE"
  SUMMARY="The model inventory pass found drift and committed it to chore/model-inventory-$DATE in agent-tooling: $(field drifted) drifted, $(field new-sites) new site(s), $(field retired) moved to retired, $(field confirmed) confirmed. The branch is unpushed and unmerged and waits for review. Log: $LOG."
  DETAIL="$REPORT_BODY"
fi

if [[ "$SURFACE" == none ]]; then
  MSG="pass completed, nothing drifted — nothing surfaced in Orbital"
  if [[ "$DRY_RUN" == 1 ]]; then echo "[dry-run] decision: $MSG"; else log "$MSG"; fi
  exit 0
fi

# ── Surface it ────────────────────────────────────────────────────────────────────────────────────────────

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
SOURCE_ID="$SOURCE_ID" TITLE="$TITLE" SUMMARY="$SUMMARY" DETAIL="$DETAIL" \
  python3 -c 'import json, os, sys
json.dump({
    "source": "timer_report",
    "sourceId": os.environ["SOURCE_ID"],
    "title": os.environ["TITLE"][:400],
    "summary": os.environ["SUMMARY"][:2000],
    "detail": (os.environ["DETAIL"] or None) and os.environ["DETAIL"][:8000],
    "projectRef": "Workspace Operations",
}, sys.stdout)' > "$BODY_FILE"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "[dry-run] decision: surface a '$SURFACE' item in Orbital"
  echo "[dry-run] curl it would send:"
  echo "  curl --silent --show-error --request POST \\"
  echo "       --url $ORBITAL_URL/api/items/report \\"
  echo "       --header 'CF-Access-Client-Id: <redacted>' \\"
  echo "       --header 'CF-Access-Client-Secret: <redacted>' \\"
  echo "       --header 'Content-Type: application/json' \\"
  echo "       --data @- <<'JSON'"
  python3 -m json.tool < "$BODY_FILE"
  echo "JSON"
  exit 0
fi

# `~/.env` carries the Cloudflare Access service token. Sourced, never echoed; passed to curl through a config
# file on stdin rather than argv, so the credentials never appear in the process table.
# shellcheck disable=SC1091
set +u; . "$HOME/.env"; set -u
if [[ -z "${TWENTYEAST_CF_CLIENT_ID:-}" || -z "${TWENTYEAST_CF_CLIENT_SECRET:-}" ]]; then
  log "FATAL: TWENTYEAST_CF_CLIENT_ID/SECRET are not set in ~/.env — cannot surface the $SURFACE item"
  exit 1
fi

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$RESPONSE_FILE"' EXIT
HTTP_CODE=0
HTTP_CODE="$(curl --silent --show-error --request POST \
  --output "$RESPONSE_FILE" --write-out '%{http_code}' --config - <<CURLCFG || true
url = "$ORBITAL_URL/api/items/report"
header = "CF-Access-Client-Id: $TWENTYEAST_CF_CLIENT_ID"
header = "CF-Access-Client-Secret: $TWENTYEAST_CF_CLIENT_SECRET"
header = "Content-Type: application/json"
data = "@$BODY_FILE"
CURLCFG
)"

case "$HTTP_CODE" in
  200|201)
    log "surfaced $SURFACE item in Orbital (HTTP $HTTP_CODE): $(head -c 200 "$RESPONSE_FILE")"
    ;;
  *)
    # The whole point of this script is that a bad outcome is visible. If the visibility mechanism is the thing
    # that broke, fail the unit so the journal carries it.
    log "FATAL: could not surface the $SURFACE item in Orbital (HTTP $HTTP_CODE): $(head -c 500 "$RESPONSE_FILE")"
    log "the item that could not be sent was titled: $TITLE"
    exit 1
    ;;
esac

# A failed pass stays a failed unit even once the item is safely on the operator's list — the journal and the
# item should agree about what happened.
if [[ "$SURFACE" == failed ]]; then exit 1; fi
exit 0

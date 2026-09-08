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
#      the log says so, and a branch nobody knows about sits in the site-inventory repo for ever. A silent
#      branch is the same failure class as a silent failure.
#
# Both become a CANDIDATE work item in the work tracker, which the operator triages or lets age out. The quiet
# third outcome — the pass ran, nothing drifted — surfaces nothing; the log is the record.
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

# ── Private configuration ─────────────────────────────────────────────────────────────────────────────────
#
# This repo is public. The tracker's base URL, the project items are filed under, the repo holding the private
# site inventory, and the NAMES of the credential variables are all deployment facts, so they live in a
# private config file rather than in this script. No secret is copied there — it names which variables to
# read, and ~/.env still holds the values.
CONFIG_FILE="${MODEL_INVENTORY_CONFIG:-$HOME/.config/model-inventory/config.env}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  set +u; . "$CONFIG_FILE"; set -u
fi

TRACKER_URL="${MODEL_INVENTORY_TRACKER_URL:-}"
PROJECT_REF="${MODEL_INVENTORY_PROJECT_REF:-}"
CF_ID_VAR="${MODEL_INVENTORY_CF_ID_VAR:-}"
CF_SECRET_VAR="${MODEL_INVENTORY_CF_SECRET_VAR:-}"
# Where the pass commits the updated site inventory. Falls back to this repo so a missing config degrades to
# "look here" rather than to a crash.
SITES_REPO="${MODEL_INVENTORY_SITES_REPO:-$REPO_ROOT}"

LOG_DIR="${MODEL_INVENTORY_LOG_DIR:-$HOME/.local/share/model-inventory}"
DATE="$(date +%F)"
LOG="$LOG_DIR/verify-$DATE.log"

DRY_RUN=0
FAKE_EXIT=0
FAKE_DRIFT=0

usage() {
  cat <<'USAGE'
run-verify.sh [--dry-run [exit-code] [drift]]

  (no arguments)   Run the verification pass and surface the outcome in the work tracker.
  --dry-run        Do NOT call claude and do NOT POST. Print the decision and the exact curl that would be
                   sent, with the Access credentials redacted.
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
    REPORT_BODY=$'MODEL-INVENTORY-REPORT\nconfirmed: 38\ndrifted: 2\ndiverged: 9\nnew-sites: 1\nretired: 1\nbranch: chore/model-inventory-'"$DATE"$'\ncommit: 4f1a9c2'
    BRANCH_PRESENT=1
  elif [[ "$FAKE_EXIT" == 0 ]]; then
    REPORT_BODY=$'MODEL-INVENTORY-REPORT\nconfirmed: 43\ndrifted: 0\ndiverged: 9\nnew-sites: 0\nretired: 0\nbranch: none\ncommit: none'
    BRANCH_PRESENT=0
  else
    REPORT_BODY=''
    BRANCH_PRESENT=0
  fi
  echo "[dry-run] would run: cat $PROMPT | claude -p --model sonnet --dangerously-skip-permissions --output-format text"
  echo "[dry-run] log would be: $LOG"
  echo "[dry-run] site inventory repo: $SITES_REPO"
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
  # The branch is created wherever the private site inventory lives, not in this repo — the pass never
  # commits to the public one.
  if git -C "$SITES_REPO" rev-parse --verify --quiet "chore/model-inventory-$DATE" >/dev/null 2>&1; then
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
  SUMMARY="The every-14-days model inventory pass did not verify the inventory this cycle ($REASON). The site inventory is now unverified until someone runs it again. The last 20 lines of the log are below; the whole log is at $LOG."
  if [[ "$DRY_RUN" == 1 ]]; then
    DETAIL=$'(dry run: the last 20 lines of '"$LOG"$' would be quoted here)'
  else
    DETAIL="$(tail -20 "$LOG" 2>/dev/null || echo '(the log could not be read)')"
  fi
elif [[ "$BRANCH_PRESENT" == 1 ]]; then
  SURFACE=drift
  # A DIFFERENT sourceId from the failure case, deliberately. The tracker's mint is idempotent on
  # (source, sourceId), so reusing one key would mean a morning failure silently swallowed an afternoon
  # re-run's drift report — the row would already exist and the drift would never be seen.
  SOURCE_ID="model-inventory-drift:$DATE"
  TITLE="Model inventory drift found $DATE — review branch chore/model-inventory-$DATE"
  # `diverged` is reported whether or not anything drifted: a site can match what was recorded last cycle and
  # still be running a model its use case no longer recommends. That gap is the reason the inventory was split
  # into a public use-case map and a private site list, so it belongs in the summary the operator reads.
  SUMMARY="The model inventory pass found drift and committed it to chore/model-inventory-$DATE in the site-inventory repo: $(field drifted) drifted, $(field new-sites) new site(s), $(field retired) moved to retired, $(field confirmed) confirmed. It also found $(field diverged) site(s) whose pinned model no longer matches their use case's current recommendation. The branch is unpushed and unmerged and waits for review. Log: $LOG."
  DETAIL="$REPORT_BODY"
fi

if [[ "$SURFACE" == none ]]; then
  MSG="pass completed, nothing drifted — nothing surfaced ($(field diverged) site(s) diverged from their use case's recommendation)"
  if [[ "$DRY_RUN" == 1 ]]; then echo "[dry-run] decision: $MSG"; else log "$MSG"; fi
  exit 0
fi

# ── Surface it ────────────────────────────────────────────────────────────────────────────────────────────

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
SOURCE_ID="$SOURCE_ID" TITLE="$TITLE" SUMMARY="$SUMMARY" DETAIL="$DETAIL" PROJECT_REF="$PROJECT_REF" \
  python3 -c 'import json, os, sys
json.dump({
    "source": "timer_report",
    "sourceId": os.environ["SOURCE_ID"],
    "title": os.environ["TITLE"][:400],
    "summary": os.environ["SUMMARY"][:2000],
    "detail": (os.environ["DETAIL"] or None) and os.environ["DETAIL"][:8000],
    "projectRef": os.environ["PROJECT_REF"] or None,
}, sys.stdout)' > "$BODY_FILE"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "[dry-run] decision: surface a '$SURFACE' item in the work tracker"
  echo "[dry-run] curl it would send:"
  echo "  curl --silent --show-error --request POST \\"
  echo "       --url ${TRACKER_URL:-<unset: see \$MODEL_INVENTORY_CONFIG>}/api/items/report \\"
  echo "       --header 'CF-Access-Client-Id: <redacted>' \\"
  echo "       --header 'CF-Access-Client-Secret: <redacted>' \\"
  echo "       --header 'Content-Type: application/json' \\"
  echo "       --data @- <<'JSON'"
  python3 -m json.tool < "$BODY_FILE"
  echo "JSON"
  exit 0
fi

if [[ -z "$TRACKER_URL" || -z "$CF_ID_VAR" || -z "$CF_SECRET_VAR" ]]; then
  log "FATAL: $CONFIG_FILE is missing or incomplete (need MODEL_INVENTORY_TRACKER_URL, MODEL_INVENTORY_CF_ID_VAR, MODEL_INVENTORY_CF_SECRET_VAR) — cannot surface the $SURFACE item"
  exit 1
fi

# `~/.env` carries the Access service token. Sourced, never echoed; passed to curl through a config file on
# stdin rather than argv, so the credentials never appear in the process table. Which variables to read comes
# from the private config, so this public script names no account.
# shellcheck disable=SC1091
set +u; . "$HOME/.env"; set -u
CF_ID="${!CF_ID_VAR:-}"
CF_SECRET="${!CF_SECRET_VAR:-}"
if [[ -z "$CF_ID" || -z "$CF_SECRET" ]]; then
  log "FATAL: \$$CF_ID_VAR/\$$CF_SECRET_VAR are not set in ~/.env — cannot surface the $SURFACE item"
  exit 1
fi

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$RESPONSE_FILE"' EXIT
HTTP_CODE=0
HTTP_CODE="$(curl --silent --show-error --request POST \
  --output "$RESPONSE_FILE" --write-out '%{http_code}' --config - <<CURLCFG || true
url = "$TRACKER_URL/api/items/report"
header = "CF-Access-Client-Id: $CF_ID"
header = "CF-Access-Client-Secret: $CF_SECRET"
header = "Content-Type: application/json"
data = "@$BODY_FILE"
CURLCFG
)"

case "$HTTP_CODE" in
  200|201)
    log "surfaced $SURFACE item in the work tracker (HTTP $HTTP_CODE): $(head -c 200 "$RESPONSE_FILE")"
    ;;
  *)
    # The whole point of this script is that a bad outcome is visible. If the visibility mechanism is the thing
    # that broke, fail the unit so the journal carries it.
    log "FATAL: could not surface the $SURFACE item (HTTP $HTTP_CODE): $(head -c 500 "$RESPONSE_FILE")"
    log "the item that could not be sent was titled: $TITLE"
    exit 1
    ;;
esac

# A failed pass stays a failed unit even once the item is safely on the operator's list — the journal and the
# item should agree about what happened.
if [[ "$SURFACE" == failed ]]; then exit 1; fi
exit 0

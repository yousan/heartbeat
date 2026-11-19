#!/usr/bin/env bash
# GitHub side of the dead man's switch.
# Compares LAST_BEAT with now, sends one DM on ok -> stale and one on
# stale -> ok, and records the state in $STATE_FILE (committed by the workflow).
#
# Environment:
#   LAST_BEAT      unix seconds of the last host beat (repository variable)
#   STATE_FILE     default state/status.json
#   STALE_AFTER    seconds without a beat before it counts as stale (1200)
#   REFRESH_AFTER  rewrite the state file at least this often, so the
#                  repository stays active (604800 = 7 days)
#   NOTIFY         command that sends one DM (default: notify.sh next to this)
#   NOW            override the current time (tests)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="${STATE_FILE:-state/status.json}"
STALE_AFTER="${STALE_AFTER:-1200}"
REFRESH_AFTER="${REFRESH_AFTER:-604800}"
NOTIFY="${NOTIFY:-$here/notify.sh}"
NOW="${NOW:-$(date +%s)}"

jst() { TZ=Asia/Tokyo date -d "@$1" '+%Y-%m-%d %H:%M JST'; }

last="${LAST_BEAT:-}"
[[ "$last" =~ ^[0-9]+$ ]] || last=""

prev_status="ok"
prev_since=0
refreshed=0
if [[ -f "$STATE_FILE" ]]; then
  prev_status="$(jq -r '.status // "ok"' "$STATE_FILE")"
  prev_since="$(jq -r '.since // 0' "$STATE_FILE")"
  refreshed="$(jq -r '.refreshed // 0' "$STATE_FILE")"
fi

if [[ -z "$last" ]]; then
  status="stale"
  stale_at="$NOW"
  echo "check: LAST_BEAT is missing or not a number"
else
  age=$((NOW - last))
  stale_at=$((last + STALE_AFTER))
  if ((age > STALE_AFTER)); then status="stale"; else status="ok"; fi
  echo "check: last beat $(jst "$last"), ${age}s ago"
fi
echo "check: previous=$prev_status current=$status"

write_state() { # status since
  mkdir -p "$(dirname "$STATE_FILE")"
  jq -n --arg s "$1" --argjson since "$2" --argjson r "$NOW" \
    '{status: $s, since: $since, refreshed: $r}' > "$STATE_FILE"
}

if [[ "$status" == "stale" && "$prev_status" != "stale" ]]; then
  "$NOTIFY" "🔴 ハートビート途絶: $(jst "$stale_at") から応答がありません / Heartbeat stale since $(jst "$stale_at")"
  write_state stale "$stale_at"
  echo "check: went stale, DM sent"
elif [[ "$status" == "ok" && "$prev_status" == "stale" ]]; then
  "$NOTIFY" "🟢 ハートビート復旧: $(jst "$prev_since") からの途絶が回復しました / Heartbeat is back (stale since $(jst "$prev_since"))"
  write_state ok "$last"
  echo "check: recovered, DM sent"
elif ((NOW - refreshed >= REFRESH_AFTER)); then
  write_state "$prev_status" "$prev_since"
  echo "check: no change, state file refreshed"
else
  echo "check: no change"
fi

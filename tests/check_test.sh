#!/usr/bin/env bash
# Tests for .github/scripts/check.sh state transitions. No network.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
check="$root/.github/scripts/check.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cat > "$work/notify" <<'EOF'
#!/usr/bin/env bash
[[ -n "${NOTIFY_FAIL:-}" ]] && exit 1
echo "$1" >> "$DM_LOG"
EOF
chmod +x "$work/notify"

export STATE_FILE="$work/state.json" NOTIFY="$work/notify" DM_LOG="$work/dms"
fails=0
t0=1800000000

run() { # now last_beat
  NOW="$1" LAST_BEAT="$2" "$check" > /dev/null
}
dms() { [[ -f "$DM_LOG" ]] && wc -l < "$DM_LOG" | tr -d ' ' || echo 0; }
status() { jq -r .status "$STATE_FILE"; }
holds() { if "$@"; then echo yes; else echo no; fi; }
expect() { # description actual expected
  if [[ "$2" == "$3" ]]; then echo "ok   - $1"; else echo "FAIL - $1 (got '$2', want '$3')"; fails=$((fails + 1)); fi
}

run $t0 $((t0 - 60))
expect "fresh beat, no state file: no DM" "$(dms)" 0

run $((t0 + 1200)) $t0
expect "exactly 20 min old is not stale" "$(dms)" 0

run $((t0 + 1260)) $t0
expect "older than 20 min: one DM" "$(dms)" 1
expect "state is stale" "$(status)" stale
expect "since is last beat + 20 min" "$(jq -r .since "$STATE_FILE")" $((t0 + 1200))
expect "stale DM is Japanese and English" "$(holds grep -q "ハートビート途絶.*Heartbeat stale since" "$DM_LOG")" yes

run $((t0 + 1860)) $t0
run $((t0 + 7200)) $t0
expect "still stale: no further DM" "$(dms)" 1

run $((t0 + 7500)) $((t0 + 7450))
expect "beat returns: one recovery DM" "$(dms)" 2
expect "state is ok" "$(status)" ok
expect "recovery DM text" "$(holds grep -q "ハートビート復旧.*Heartbeat is back" "$DM_LOG")" yes

run $((t0 + 7800)) $((t0 + 7750))
expect "ok again: no DM" "$(dms)" 2

run $((t0 + 7800 + 604800)) $((t0 + 7800 + 604700))
expect "weekly refresh rewrites the state file" "$(jq -r .refreshed "$STATE_FILE")" $((t0 + 7800 + 604800))
expect "refresh sends no DM" "$(dms)" 2

cp "$STATE_FILE" "$work/before.json"
if NOTIFY_FAIL=1 NOW=$((t0 + 700000)) LAST_BEAT=$t0 "$check" > /dev/null 2>&1; then rc=0; else rc=1; fi
expect "failed DM makes the check fail" "$rc" 1
expect "failed DM leaves the state unchanged (retried next run)" "$(holds cmp -s "$STATE_FILE" "$work/before.json")" yes

rm -f "$STATE_FILE"
run $t0 ""
expect "missing LAST_BEAT counts as stale" "$(status)" stale

if ((fails > 0)); then echo "$fails test(s) failed"; exit 1; fi
echo "all tests passed"

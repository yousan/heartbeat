#!/usr/bin/env bash
# Send one Discord direct message: notify.sh "<message>"
# Needs DISCORD_BOT_TOKEN and DISCORD_USER_ID in the environment.
# Never prints the token, the user id, or the DM channel id.
set -euo pipefail

msg="${1:?usage: notify.sh <message>}"
: "${DISCORD_BOT_TOKEN:?DISCORD_BOT_TOKEN is not set}"
: "${DISCORD_USER_ID:?DISCORD_USER_ID is not set}"

api="https://discord.com/api/v10"
ua="DiscordBot (https://github.com/yousan/heartbeat, 1.0)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
chmod 700 "$work"

# Keep the token off the command line by passing headers through a file.
printf 'Authorization: Bot %s\nContent-Type: application/json\nUser-Agent: %s\n' \
  "$DISCORD_BOT_TOKEN" "$ua" > "$work/headers"

# post <path> <json-body>  -> prints HTTP status, response body in $work/resp
post() {
  curl -sS --retry 3 --retry-delay 5 --max-time 20 \
    -o "$work/resp" -w '%{http_code}' \
    -H @"$work/headers" -X POST --data "$2" "$api$1"
}

fail() {
  local detail
  detail="$(jq -r '[.message // empty, (.code // empty | tostring)] | join(" / ")' "$work/resp" 2>/dev/null || true)"
  echo "notify: $1 failed (HTTP $2${detail:+: $detail})" >&2
  exit 1
}

code="$(post /users/@me/channels "$(jq -nc --arg r "$DISCORD_USER_ID" '{recipient_id: $r}')")"
[[ "$code" == 2* ]] || fail "opening the DM channel" "$code"
channel="$(jq -r '.id // empty' "$work/resp")"
[[ -n "$channel" ]] || fail "opening the DM channel (no channel id)" "$code"

code="$(post "/channels/$channel/messages" \
  "$(jq -nc --arg c "$msg" '{content: $c, allowed_mentions: {parse: []}}')")"
[[ "$code" == 2* ]] || fail "posting the message" "$code"

echo "notify: DM sent"

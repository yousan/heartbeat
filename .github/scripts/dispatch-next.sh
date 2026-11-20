#!/usr/bin/env bash
# Queue the next run of check.yml (test=false) with GITHUB_TOKEN.
# Writes dispatched=true|false to $GITHUB_OUTPUT. With --strict, a failure
# fails the step; otherwise it only warns (a later step retries).
set -uo pipefail

: "${GH_TOKEN:?}" "${REF:?}" "${GITHUB_REPOSITORY:?}"
out="${GITHUB_OUTPUT:-/dev/null}"

for attempt in 1 2 3; do
  if gh workflow run check.yml -R "$GITHUB_REPOSITORY" --ref "$REF" -f test=false; then
    echo "dispatch: next check queued"
    echo "dispatched=true" >> "$out"
    exit 0
  fi
  echo "dispatch: attempt $attempt failed" >&2
  sleep 10
done

echo "dispatched=false" >> "$out"
if [[ "${1:-}" == "--strict" ]]; then
  echo "::error::could not dispatch the next check; the schedule will have to restart the chain"
  exit 1
fi
echo "::warning::could not dispatch the next check; retrying at the end of this run"

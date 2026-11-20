# heartbeat

A dead man's switch for a home server. If the host goes down, or its OpenClaw
gateway stops answering, the maintainer gets **one Discord direct message**,
sent from GitHub Actions — that is, from outside the host. When the heartbeat
comes back, one more DM says so. Nothing is sent in between.

## How it works

```
host (every 5 min)                         GitHub Actions (about every 5 min)
──────────────────                         ─────────────────────────────
curl gateway ── ok ──> gh variable set     read LAST_BEAT
     │                  LAST_BEAT=<now>    older than 20 min?  ── stale
     └─ fails ──> no beat                  compare with state/status.json
                                           ok → stale : DM "stale since …"
                                           stale → ok : DM "back"
                                           commit state/status.json
```

- **Host side** (`deploy/`): a systemd user timer runs `heartbeat-beat` every
  5 minutes. It updates the repository variable `LAST_BEAT` (unix seconds)
  only when the gateway health URL (default `http://127.0.0.1:18789/`)
  answers within 5 seconds.
- **GitHub side** (`.github/workflows/check.yml`): a chain of short runs.
  Each run queues the next one with `workflow_dispatch` (allowed with
  `GITHUB_TOKEN`, no personal access token), checks `LAST_BEAT`, then waits
  about 5 minutes before it ends, so a check happens roughly every 5–6
  minutes. A concurrency group keeps exactly one chain (one run in progress,
  at most one pending). The 10-minute `schedule` is only a backup that
  restarts the chain if it ever breaks: GitHub's schedule is best-effort and
  can be hours late or skipped. `LAST_BEAT` older than 20 minutes counts as
  stale. The last known status is kept in `state/status.json`, committed with
  `GITHUB_TOKEN`. The file is also rewritten at least once a week, so the
  repository never goes 60 days without activity (GitHub disables schedules
  in public repositories after that).
- **The DM**: the bot opens a DM channel with the maintainer and posts one
  short line in Japanese and English with the time the heartbeat went stale.
  Logs never contain the bot token, the user id, the DM channel id, or a host
  name.

Expected delay: the alert fires 20–27 minutes after the last beat. GitHub
fixes `vars.LAST_BEAT` when a run is queued, not when it starts, so each run
sees the value from about 5 minutes earlier; this never delays the stale
alert (a stale beat stays stale), and recovery is noticed one run later. The run
list shows one `workflow_dispatch` run by `github-actions[bot]` about every
5–6 minutes; a `schedule` run that arrives while the chain is going shows up
as cancelled or simply continues the chain, which is expected.

To pause the checks: `gh workflow disable check.yml`. To start the chain
again: `gh workflow enable check.yml` and
`gh workflow run check.yml -f test=false` (or wait for a `schedule` run).

### Repository settings

| Kind     | Name                | Value                                          |
| -------- | ------------------- | ---------------------------------------------- |
| secret   | `DISCORD_BOT_TOKEN` | token of a bot that shares a server with you   |
| secret   | `DISCORD_USER_ID`   | your Discord user id (the DM recipient)        |
| variable | `LAST_BEAT`         | written by the host; unix seconds              |

### Manual runs

- **Actions → heartbeat check → Run workflow** with `test` checked sends one
  test DM and changes nothing else.
- With `test` unchecked it joins the chain: it runs as soon as the current
  run ends and takes over from the pending one.

```sh
gh workflow run check.yml -R yousan/heartbeat -f test=true
```

## Install the host side

Requirements: `curl`, and `gh` logged in with an account that can write
repository variables of this repository (`gh auth status`).

```sh
git clone https://github.com/yousan/heartbeat.git
cd heartbeat

install -Dm755 deploy/heartbeat-beat    ~/.local/bin/heartbeat-beat
install -Dm644 deploy/heartbeat.service ~/.config/systemd/user/heartbeat.service
install -Dm644 deploy/heartbeat.timer   ~/.config/systemd/user/heartbeat.timer

# Keep user timers running without an open login session.
sudo loginctl enable-linger "$USER"

systemctl --user daemon-reload
systemctl --user enable --now heartbeat.timer
```

Check it:

```sh
systemctl --user start heartbeat.service      # one beat right now
journalctl --user -u heartbeat.service -n 20
gh variable list -R yousan/heartbeat          # LAST_BEAT should be fresh
systemctl --user list-timers heartbeat.timer
```

Optional overrides go in `~/.config/heartbeat/env`:

```sh
HEARTBEAT_REPO=owner/repo
HEARTBEAT_GATEWAY_URL=http://127.0.0.1:18789/
# If gh keeps its token in a keyring that systemd user services cannot reach:
# GH_TOKEN=...   (chmod 600 this file)
```

If the gateway does not answer, the service exits with an error and no beat is
sent; that is expected and is what eventually triggers the DM.

## Retire it

1. Stop the checks first, or you will get one last "stale" DM:

   ```sh
   gh workflow disable check.yml -R yousan/heartbeat
   ```

2. Stop the host side:

   ```sh
   systemctl --user disable --now heartbeat.timer
   rm ~/.config/systemd/user/heartbeat.{service,timer} ~/.local/bin/heartbeat-beat
   rm -rf ~/.config/heartbeat
   systemctl --user daemon-reload
   ```

3. Clean up: delete the `DISCORD_BOT_TOKEN` and `DISCORD_USER_ID` secrets and
   the `LAST_BEAT` variable, and archive the repository if it is no longer
   needed. Remove the bot from the shared server or reset its token if it was
   created only for this.

## Development

```sh
tests/check_test.sh     # state transitions, no network
```

CI runs shellcheck, actionlint and the tests on every pull request.

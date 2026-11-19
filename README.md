# heartbeat

A dead man's switch for a home server. If the host goes down, or its OpenClaw
gateway stops answering, the maintainer gets **one Discord direct message**,
sent from GitHub Actions — that is, from outside the host. When the heartbeat
comes back, one more DM says so. Nothing is sent in between.

## How it works

```
host (every 5 min)                         GitHub Actions (every 10 min)
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
- **GitHub side** (`.github/workflows/check.yml`): runs on a 10-minute
  schedule. `LAST_BEAT` older than 20 minutes counts as stale. The last known
  status is kept in `state/status.json`, committed with the workflow's own
  `GITHUB_TOKEN` (no personal access token). The file is also rewritten at
  least once a week, so the repository never goes 60 days without activity
  (GitHub disables schedules in public repositories after that).
- **The DM**: the bot opens a DM channel with the maintainer and posts one
  short line in Japanese and English with the time the heartbeat went stale.
  Logs never contain the bot token, the user id, the DM channel id, or a host
  name.

Expected delay: the alert fires 20–30 minutes after the last beat, plus
however late GitHub starts the scheduled run (usually a few minutes, more at
busy times).

### Repository settings

| Kind     | Name                | Value                                          |
| -------- | ------------------- | ---------------------------------------------- |
| secret   | `DISCORD_BOT_TOKEN` | token of a bot that shares a server with you   |
| secret   | `DISCORD_USER_ID`   | your Discord user id (the DM recipient)        |
| variable | `LAST_BEAT`         | written by the host; unix seconds              |

### Manual runs

- **Actions → heartbeat check → Run workflow** with `test` checked sends one
  test DM and changes nothing else.
- With `test` unchecked it runs the normal check immediately.

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

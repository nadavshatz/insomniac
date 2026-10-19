# Architecture

```
                    user (no privileges)                       │         root
 ┌──────────────────────────────────────────────────────────┐ │ ┌─────────────────────────────┐
 │ Alfred ─▶ status_filter.sh ──reads──▶ state file          │ │ │ insomniac-helper (root-owned │
 │                     │      ──reads──▶ pmset -g /assertions │ │ │ copy in PrivilegedHelperTools)
 │                     │      ──reads──▶ guardian.pid, .last  │ │ │   enable │ disable │ status  │
 │                     ▼ arg                                  │ │ │          ▼                  │
 │            toggle_engine.sh ──spawns──▶ caffeinate -i [-d] [-t N] │ guard loop (detached)   │
 │                     │                                      │ │ │  timer · battery · thermal  │
 │                     └─ sudo -n (opt.) / osascript admin ───┼─┼─▶│  · TERM/HUP trap → pmset 0 │
 └──────────────────────────────────────────────────────────┘ │ └─────────────────────────────┘
                                                              │  LaunchDaemon bootguard:
                                                              │  /usr/bin/pmset -a disablesleep 0 @ boot
```

## Files

| Path | Runs as | Role |
| --- | --- | --- |
| `workflow/status_filter.sh` | user | Script Filter: reconciles state, emits JSON |
| `workflow/toggle_engine.sh` | user | Backend: start/stop/extend, privilege escalation |
| `workflow/menubar.js` | user | Menu bar indicator (JXA + Cocoa bridge), started and stopped by the engine |
| `workflow/lib/common.zsh` | user | Shared paths, state I/O, probes, duration parser, formatting |
| `workflow/helper/insomniac-helper.sh` | **root** (installed copy) | `pmset` + guardian |
| `workflow/helper/*.bootguard.plist` | **root** (launchd) | Boot-time reset |

## State

`$alfred_workflow_data/state` holds plain `KEY=VALUE` lines. It's written atomically (temp file + `mv`) and *parsed* with a whitelist of keys, never `source`d.

```
MODE=lid            # idle | lid
STARTED=1792395000  # epoch
SECS=3600           # requested duration, 0 = indefinite
EXPIRES=1792398600  # epoch, 0 = indefinite
CAF_PID=81234       # caffeinate
DISPLAY=1           # 1 = caffeinate -d (display kept on), 0 = display may sleep
GUARD_PID=81201     # root guardian (informational; truth is /var/run/…guardian.pid)
```

Root-written, world-readable files in `/var/run` (cleared at boot):
- `io.github.nadavshatz.insomniac.guardian.pid`: the live guardian
- `io.github.nadavshatz.insomniac.last`: `<reason> <epoch>` for the last guardian exit (`timer`, `battery`, `thermal`, `stopped`, `signal`, `external`)

## Reconciliation (every Script Filter run)

The state file is a claim. The filter checks it against reality:

| Recorded | Reality | Shown |
| --- | --- | --- |
| idle | caffeinate PID alive | **active** |
| idle | PID gone (timer ended, killed) | state cleared → menu |
| lid | `SleepDisabled 1` and guardian alive | **active** |
| lid | `SleepDisabled 1`, guardian gone | **degraded**: ⚠ restore |
| lid | `SleepDisabled 0` | state cleared → menu (+ "last session ended…" note) |
| none | `SleepDisabled 1` | **orphan**: ⚠ restore |

PIDs are checked with `ps -p PID -o command=` against an expected pattern. That avoids trusting a recycled PID, and it works for root-owned processes, where `kill -0` would fail with EPERM.

## Timing engine

- **Idle mode:** `caffeinate -i [-d] -t N` expires on its own. No watcher is needed, and nothing system-wide changes, so a crash leaves nothing behind.
- **Closed-lid mode:** the helper's `enable` command sets `disablesleep 1`, then starts `helper guard <expires> <floor> <thermal>` detached (`&!`, stdio closed, reparented to launchd). The guardian polls every 15 s, or less when the expiry is closer. It uses `sleep N & wait` so signal traps fire immediately. Expiry compares wall-clock epochs, so it's correct even if the machine was suspended.
  The guardian runs as root deliberately. When the timer ends the lid may be closed, and an authorization prompt then could never be answered.
- A user-level `caffeinate` also runs in closed-lid mode, so behaviour with the lid *open* matches idle mode (display option included).
- **Switching** lid→lid replaces the guardian within one privileged call. The old guardian is stopped and waited for before `disablesleep 1` is set again, so its exit trap can't race the new setting.

## Menu bar indicator

`toggle_engine.sh` starts `osascript -l JavaScript menubar.js <data_dir> <engine>` after a successful start, unless one is already running (tracked in `$alfred_workflow_data/menubar.pid` and verified with `ps`). It stops the indicator on `stop`/`uninstall`, or when the `menubar` setting is off.

The indicator keeps no state of its own:
- Every second it re-reads the state file and redraws the title (`42m`, `1h 05m`, `∞`), using an SF Symbol (`cup.and.saucer.fill`, `laptopcomputer`, or a warning triangle when degraded).
- Every 5 seconds it runs `toggle_engine.sh reconcile`. If the session is gone, it posts a notification explaining why (timer, battery, heat) and quits.
- Menu actions (*Extend +15m / +1h*, *Stop*) call the engine with `INSOMNIAC_FROM_MENUBAR=1`, so the engine doesn't kill the caller mid-call.

The indicator inherits the engine's environment, so Alfred's workflow settings apply to actions taken from its menu too.

## Updates (GitHub build only)

`lib/update.zsh` exists only in the GitHub build. `scripts/build.sh --gallery` removes it, along with its setting and icon, because Gallery workflows must not update themselves. Every caller checks whether the file exists first.

- **Check:** `curl -fsSI …/releases/latest`, then read the `Location: …/releases/tag/vX.Y.Z` redirect. No API token, no JSON parsing. The Script Filter starts this in the background at most once every 24h, and writes the cache timestamp first so the 1-second reruns don't pile up. The result is cached in `$alfred_workflow_cache/update`.
- **Install:** download the release's `.alfredworkflow` and `.sha256`, verify the checksum, the bundle ID and the version, then `open` the file. Alfred's own import dialog does the actual update and keeps the user's configuration.
- The update verbs run outside the engine's state lock, so a slow network can't delay start or stop.

## Privilege escalation

1. If a sudoers rule permits the helper (`sudo -n -l <helper>`), the engine uses `sudo -n` and no prompt appears.
2. Otherwise it calls `osascript` with `do shell script … with administrator privileges`. The command is passed through `argv` rather than spliced into AppleScript source, and every word is single-quoted with zsh `${(qq)…}`, so paths with spaces or quotes can't break out.
3. If the installed helper or boot guard is missing or differs from the shipped copy, the same prompt also runs `install -o root -g wheel`.
4. Cancelling the dialog (error `-128`) is reported as "Cancelled — nothing was changed".

## Testing

`tests/run_tests.sh` mocks `pmset`, `caffeinate`, `osascript` and `sudo` (`tests/mocks/`), and redirects every system path through `INSOMNIAC_PREFIX`. The helper honours these overrides **only when not running as root**, so a root invocation can't be redirected.

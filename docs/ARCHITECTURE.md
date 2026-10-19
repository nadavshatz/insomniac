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

## Privilege escalation

1. If a sudoers rule permits the helper (`sudo -n -l <helper>`), the engine uses `sudo -n` and no prompt appears.
2. Otherwise it calls `osascript` with `do shell script … with administrator privileges`. The command is passed through `argv` rather than spliced into AppleScript source, and every word is single-quoted with zsh `${(qq)…}`, so paths with spaces or quotes can't break out.
3. If the installed helper or boot guard is missing or differs from the shipped copy, the same prompt also runs `install -o root -g wheel`.
4. Cancelling the dialog (error `-128`) is reported as "Cancelled — nothing was changed".

## Testing

`tests/run_tests.sh` mocks `pmset`, `caffeinate`, `osascript` and `sudo` (`tests/mocks/`), and redirects every system path through `INSOMNIAC_PREFIX`. The helper honours these overrides **only when not running as root**, so a root invocation can't be redirected.

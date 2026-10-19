# Closed-Lid Mode

Use it to keep a MacBook running with the lid shut: long downloads, renders, backups, an SSH session, or a headless server. External display, keyboard and power aren't required.

## Why it needs an admin password

`caffeinate` (idle-only mode) creates *power assertions*, and any app may create those. But macOS ignores them when you **close the lid**. The only supported way to override lid sleep is the system-wide setting `SleepDisabled`:

```sh
pmset -a disablesleep 1   # never sleep, even with the lid closed
pmset -a disablesleep 0   # back to normal
```

`pmset -a` changes system power settings, so it requires administrator rights.

## What gets installed

The first time you use closed-lid mode, one standard macOS authorization dialog installs:

| File | Purpose |
| --- | --- |
| `/Library/PrivilegedHelperTools/io.github.nadavshatz.insomniac.helper` | A root-owned copy of the small helper script. It can only do four things: `enable`, `disable`, `status`, `uninstall` |
| `/Library/LaunchDaemons/io.github.nadavshatz.insomniac.bootguard.plist` | Runs `/usr/bin/pmset -a disablesleep 0` once at every startup. That's all it does |

Root never runs a file you could edit: the helper is a root-owned copy, and the boot guard calls `pmset` directly. When you update the workflow, the helper is refreshed within the same password prompt. To remove both, run `awake uninstall`.

## How normal sleep comes back

While a closed-lid session runs, a small root **guardian** process watches it. It's root on purpose: when your timer ends, the lid is probably shut, so nobody could answer a password prompt.

| What happens | What restores sleep |
| --- | --- |
| You press Stop (Alfred or the menu bar) | The helper stops the guardian and runs `disablesleep 0` |
| Timer runs out | Guardian, no prompt |
| Battery at or below the [floor](Settings#battery-floor), on battery | Guardian |
| macOS reports a [thermal warning](Settings#thermal-guard) | Guardian |
| The guardian is told to quit | Its exit handler runs `disablesleep 0` |
| The guardian is force-killed | Alfred and the menu bar show **⚠ System sleep is disabled**, and ↩ restores |
| Alfred quits or crashes | Nothing changes: the guardian doesn't depend on Alfred |
| Crash, kernel panic, forced shutdown, restart | The **boot guard** at next startup |
| Something else sets `disablesleep 1` | Alfred flags it as *orphaned* and offers to restore |

Each automatic restore is logged. See it with:

```sh
log show --last 1d --predicate 'eventMessage CONTAINS "insomniac"' --info
```

## Tips

- **Prefer timed sessions** (`awake lid 2h`). Indefinite sessions only end when you stop them, or when the battery or thermal guard steps in.
- Keep the **battery floor** and **thermal guard** on when running on battery.
- A closed MacBook gets warm. Leave it on a hard surface, not in a bag, during long sessions.
- Wi-Fi and network access keep working with the lid closed.

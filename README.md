<p align="center"><img src="workflow/icon.png" width="128" alt="Insomniac icon"></p>

# Insomniac: an Alfred 5 workflow that keeps your Mac awake

Insomniac keeps your Mac awake from Alfred. It shows a live countdown, supports timers, and has a **closed-lid mode** that works on Apple Silicon. Restoring normal sleep is built into the design: a timer ending, a low battery, a hot Mac, a crash or a reboot all bring sleep back.

- **No dependencies.** It's pure `/bin/zsh` plus tools that ship with macOS (`caffeinate`, `pmset`, `osascript`). It needs no Python, Homebrew or pip.
- **Live status.** Alfred shows `Active (Closed-Lid): 42m 07s remaining`, updated every second.
- **Two modes:**
  - **Idle Only** uses `caffeinate`. The Mac won't idle-sleep, but closing the lid still sleeps it. No admin rights needed.
  - **Closed-Lid** uses `pmset -a disablesleep 1`. The Mac stays awake with the lid shut, for downloads, renders, SSH sessions or a headless server. It needs an admin password.
- **Timers:** presets, plus any duration you type (`45m`, `3h`, `1h30m`, `2:30`, `until 17:30`).
- **Failsafes:** a timer, a battery floor, a thermal guard, signal traps and a boot-time reset.
- **Visibility:** it lists the other apps holding sleep assertions (Zoom, Xcode, other `caffeinate`s).

Targets macOS 14 Sonoma, 15 Sequoia and later. Works on Apple Silicon and Intel. Requires Alfred 5 with the Powerpack.

---

## Installation

1. Download `Insomniac-x.y.z.alfredworkflow` from [Releases](https://github.com/nadavshatz/insomniac/releases), or build it yourself:
   ```sh
   git clone https://github.com/nadavshatz/insomniac.git
   cd insomniac && zsh scripts/build.sh     # → dist/Insomniac-1.0.0.alfredworkflow
   ```
2. Double-click the file to import it into Alfred.
3. In the configuration sheet, choose your keyword. The default is **`awake`**. If you prefer `sleep`, it works, but Alfred's built-in *Sleep* system command will appear next to it.

## Usage

| You type | What happens |
| --- | --- |
| `awake` | Shows status when a session is active, otherwise the menu |
| `awake` → *Keep Awake Indefinitely* | `caffeinate -i -d` until you stop it |
| `awake` → *Keep Awake with Closed Lid* | `pmset -a disablesleep 1` until you stop it |
| `awake 45m`, `awake 1h30m`, `awake 2:30`, `awake 90` (minutes) | Timed idle-only session |
| `awake lid 2h` | Timed closed-lid session |
| `awake until 17:30`, `awake @6pm` | Session ends at that wall-clock time |
| **⌘↩** on any start item | Same duration in the *other* mode |
| **⌥↩** on any start item | Same session with the opposite display choice. With the default setting, that means the display sleeps but the Mac stays awake |
| ↩ on the status row | Stops everything and restores the default power settings |
| `awake uninstall` | Removes the privileged helper and the boot guard |

While a session runs, the menu also offers **Extend +15m / +1h** and **Switch mode** (the timer carries over).

## Configuration

Open Alfred Preferences → Workflows → Insomniac → *Configure Workflow…*

| Variable | Default | Meaning |
| --- | --- | --- |
| `keyword` | `awake` | Alfred keyword |
| `presets` | `15m,30m,1h,2h` | Preset durations shown in the menu |
| `prevent_display_sleep` | on | Default display choice. On adds `-d` to `caffeinate`. Off lets the display sleep while the Mac stays awake (`-i` only). ⌥↩ flips it for one session |
| `battery_floor` | `10` | On battery, closed-lid mode ends at this % (0 = off) |
| `thermal_guard` | on | Closed-lid mode ends if macOS reports a thermal warning |

---

## Security transparency

### Why closed-lid mode needs admin rights

`caffeinate` creates *power assertions*, and any user may create those. But macOS always honours **lid-close sleep** regardless of assertions, unless an external display, keyboard and power are attached ("clamshell mode"). The only supported switch that overrides lid sleep is the system-wide power setting `SleepDisabled`, set with:

```sh
pmset -a disablesleep 1   # never sleep, including with the lid closed
pmset -a disablesleep 0   # restore normal behaviour
```

`pmset -a` writes system power settings and therefore requires root. Idle-only mode never asks for a password.

### Exactly what runs as root

The first time you use closed-lid mode, a single native macOS authorization dialog installs two small files:

| File | Owner | Purpose |
| --- | --- | --- |
| `/Library/PrivilegedHelperTools/io.github.nadavshatz.insomniac.helper` | `root:wheel 0755` | A copy of [`workflow/helper/insomniac-helper.sh`](workflow/helper/insomniac-helper.sh). Its commands: `enable`, `disable`, `status`, `uninstall`. |
| `/Library/LaunchDaemons/io.github.nadavshatz.insomniac.bootguard.plist` | `root:wheel 0644` | Runs `/usr/bin/pmset -a disablesleep 0` once at every boot. That's all it does. |

Design choices:

- **Root never executes a user-writable file.** The helper is *copied* into a root-owned directory and executed from there. The boot guard calls `/usr/bin/pmset` directly, not a script.
- The helper is self-contained. It runs with `zsh -f` (no rc files), uses a fixed `PATH`, and strictly validates every argument (numbers only).
- The workflow compares the shipped helper with the installed copy (`cmp`) on each privileged call. If you update the workflow, the new helper is reinstalled within the same prompt.
- It doesn't run as a background daemon. The only root process is the guardian, which runs while a closed-lid session is active and exits when the session ends. It logs to the unified log: `log show --predicate 'process == "logger"' --info | grep insomniac`.
- `awake uninstall` removes both files.

### Optional: no password prompts

If you use closed-lid mode often, you can let *only the helper* run without a password. Run `sudo visudo -f /etc/sudoers.d/insomniac` and add (replace `you` with your short username):

```
you ALL=(root) NOPASSWD: /Library/PrivilegedHelperTools/io.github.nadavshatz.insomniac.helper
```

Insomniac detects the rule (`sudo -n -l`) and uses it automatically. The trade-off: any process running as your user can then turn sleep prevention on or off without asking you. The workflow never touches sudoers itself.

---

## How sleep gets restored

| Event | What restores sleep |
| --- | --- |
| You stop the session | `helper disable`: kills the guardian, then `pmset -a disablesleep 0` |
| Timer ends | The root **guardian** (no prompt needed, even with the lid shut) |
| Battery ≤ floor while on battery | Guardian |
| `pmset -g therm` reports a thermal warning | Guardian (best effort) |
| Guardian receives TERM/HUP/INT/QUIT | Its trap runs `disablesleep 0` |
| Guardian is SIGKILLed | Alfred shows **⚠ System sleep is disabled**, ↩ restores |
| Alfred crashes or quits | Nothing changes: the guardian doesn't depend on Alfred |
| Crash, panic, forced shutdown, reboot | The **boot guard** LaunchDaemon at next boot |
| Something else sets `disablesleep 1` | Alfred flags it as *orphaned* and offers a restore |

> ⚠️ **Heat.** A closed MacBook in a bag with sleep disabled can get hot and drain its battery. Keep the battery floor and thermal guard on, and prefer timed sessions.

## Uninstall

1. `awake uninstall` (removes the root helper and the boot guard, and restores sleep)
2. Delete the workflow in Alfred Preferences.

To clean up manually:
```sh
sudo pmset -a disablesleep 0
sudo rm -f /Library/PrivilegedHelperTools/io.github.nadavshatz.insomniac.helper \
           /Library/LaunchDaemons/io.github.nadavshatz.insomniac.bootguard.plist
```

## Development

```sh
zsh tests/run_tests.sh       # 70 tests; pmset/caffeinate/osascript are mocked
zsh tests/build_test.sh      # packaging test
zsh scripts/build.sh [X.Y.Z] # package dist/*.alfredworkflow
python3 scripts/make_plist.py   # regenerate info.plist   (dev only, stdlib)
python3 scripts/make_icons.py   # regenerate icons        (dev only, Pillow)
```

### Releases

CI (`.github/workflows/ci.yml`) runs the test suite on macOS and Linux for every push and pull request. To publish a release, push a version tag:

```sh
git tag v1.2.0 && git push origin v1.2.0
```

The `release` job reruns the tests, builds `Insomniac-1.2.0.alfredworkflow` with the version stamped from the tag, and attaches it to a new [GitHub Release](https://github.com/nadavshatz/insomniac/releases) with generated notes.

Run the tests as a normal user, not root. They never change your real power settings. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the internals and [docs/SETUP.md](docs/SETUP.md) to wire the workflow by hand in Alfred's editor.

## License

[MIT](LICENSE) © 2026 Nadav Shatz. You may use, copy, modify, merge, publish, distribute, sublicense and sell copies of this software. Keep the copyright and permission notice. It's provided *as is*, without warranty.

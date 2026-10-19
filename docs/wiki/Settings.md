# Settings

Open **Alfred Preferences → Workflows → Insomniac → Configure Workflow…** (the [≡] button at the top right of the workflow canvas). Changes apply to the **next** session you start.

| Setting | Variable | Default |
| --- | --- | --- |
| [Keyword](#keyword) | `keyword` | `awake` |
| [Preset durations](#preset-durations) | `presets` | `15m,30m,1h,2h,6h,12h` |
| [Prevent display sleep](#prevent-display-sleep) | `prevent_display_sleep` | ✔ on |
| [Menu bar](#menu-bar) | `menubar` | ✔ on |
| [Updates](#updates) | `update_mode` | Tell me in Alfred |
| [Battery floor](#battery-floor) | `battery_floor` | `10` |
| [Thermal guard](#thermal-guard) | `thermal_guard` | ✔ on |

---

## Keyword

The word that opens Insomniac in Alfred.

- Default: **`awake`**.
- `sleep` works too. But Alfred has a built-in **Sleep** system command, so both will appear and you'll need to pick the right one.
- Other good choices: `caf`, `coffee`, `insomnia`.

## Preset durations

A comma-separated list of durations shown in the menu, in that order. Each entry uses the [same syntax you can type](Usage#typing-a-duration):

```
15m,30m,1h,2h,6h,12h        ← default
10m,45m,1h30m,3h            ← custom example
```

Notes:
- Invalid entries are skipped silently.
- If one of the presets matches your [last used](Usage#the-menu) session, it's shown only once, at the top.
- After a closed-lid session, the presets start closed-lid sessions by default. Use ⌘↩ for idle-only.

## Prevent display sleep

Decides what happens to the **screen** during a session. **The Mac itself stays awake either way.**

| | Checked (default) | Unchecked |
| --- | --- | --- |
| `caffeinate` flags | `-i -d` | `-i` |
| Display | stays on | turns off on your normal Lock Screen timer |
| Background work (downloads, builds, SSH, music) | keeps running | keeps running |

- You can flip this for a single session with **⌥↩** on any start item. The choice is remembered for *Extend*, *Switch mode* and the *last used* suggestion.
- If macOS asks for a password after the display turns off, the screen locks when it sleeps. Your work keeps running behind the lock.
- In closed-lid mode the display is always off while the lid is shut. This setting only matters while the lid is open.

## Menu bar

Shows the [menu bar indicator](Usage#menu-bar-indicator) while a session runs, with the time left, *Extend* and *Stop*. Turn it off if you'd rather keep the menu bar clean. Alfred still shows the full status. Turning it off also closes an indicator that's already showing, the next time you start or stop a session.

## Updates

How Insomniac handles new versions published on [GitHub Releases](https://github.com/nadavshatz/insomniac/releases). It checks at most once every 24 hours, in the background, the first time you open the menu that day.

| Choice | What happens when a new version exists |
| --- | --- |
| **Tell me in Alfred** (default) | The menu shows *Update available: Insomniac X.Y.Z*. ↩ installs it |
| **Download and open automatically** | Downloads, verifies, and opens Alfred's update prompt by itself. You still click *Update* in Alfred |
| **Never check** | No network requests at all. You can still run `awake update` by hand |

Every download is checked against the release's `.sha256` file, and its bundle ID and version must match before Alfred is asked to install it. If you installed Insomniac from the **Alfred Gallery**, this setting doesn't exist: Alfred updates Gallery workflows itself.

## Battery floor

**Closed-lid mode only.** While the Mac runs on battery, Insomniac restores normal sleep once the charge drops to this percentage or below. That way a MacBook in a bag can't run itself flat.

- Default: `10`. Set `0` to turn it off. It never triggers on AC power.
- The guardian checks every 15 seconds.
- Idle-only mode doesn't need this: macOS still sleeps the Mac when the battery is critically low.

## Thermal guard

**Closed-lid mode only.** Restores normal sleep if `pmset -g therm` reports a thermal warning, or (on Intel) heavy CPU speed limiting. This is a safety net against a closed laptop overheating in a bag or sleeve. It's best effort: macOS doesn't report every kind of thermal pressure.

---

## Passwordless closed-lid mode

Closed-lid mode changes a system setting (`pmset -a disablesleep`), so macOS asks for an admin password to start it and to stop it early. A timer running out never needs a password. If you use it often, you can let **only Insomniac's helper** run without a password:

```sh
sudo visudo -f /etc/sudoers.d/insomniac
```

Add this line, replacing `you` with your short username (run `whoami` to check):

```
you ALL=(root) NOPASSWD: /Library/PrivilegedHelperTools/io.github.nadavshatz.insomniac.helper
```

Insomniac detects the rule automatically. The trade-off: any app running as you could then turn sleep prevention on or off without asking. To undo it, run `sudo rm /etc/sudoers.d/insomniac`.

## Settings for scripts and other launchers

The engine also works outside Alfred, and reads the same variables from the environment:

```sh
cd ~/Library/Application\ Support/Alfred/Alfred.alfredpreferences/workflows/<insomniac-folder>
prevent_display_sleep=0 ./toggle_engine.sh start_idle 3600       # 1h, display may sleep
./toggle_engine.sh start_closed_lid 7200 display=1               # 2h closed-lid, display on
./toggle_engine.sh extend 900
./toggle_engine.sh stop
```

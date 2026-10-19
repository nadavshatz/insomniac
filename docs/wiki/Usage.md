# Usage

All examples use the default keyword **`awake`**. You can change it in [Settings](Settings).

## The menu

Type `awake` with nothing after it.

**When nothing is running**, you see, in order:

1. **Your last session**, marked `· last used`. It has the same length, mode and display choice as last time, so repeating it is just ↩.
2. **Keep Awake Indefinitely**: idle-only, until you stop it.
3. **Keep Awake with Closed Lid**: see [Closed-Lid Mode](Closed-Lid-Mode).
4. **Presets**: 15m, 30m, 1h, 2h, 6h, 12h by default ([configurable](Settings#preset-durations)).
5. Information rows, when relevant:
   - *Also preventing sleep: zoom.us, Xcode*: other apps holding sleep assertions (from `pmset -g assertions`).
   - *Last closed-lid session ended at 14:02*: why sleep was restored automatically (timer, battery, heat).

**While a session runs**, the top row shows a live countdown, refreshed every second:

```
Active (Idle Only): 42m 07s remaining
Ends 15:42 · display stays on · ↩ Stop and restore normal sleep
```

Below it are **Extend +15m**, **Extend +1h**, and **Switch to Closed-Lid / Idle-Only mode** (the remaining time carries over).

## Typing a duration

| You type | Result |
| --- | --- |
| `awake 45m` | 45 minutes |
| `awake 3h` | 3 hours |
| `awake 1h30m`, `awake 1.5h`, `awake 2:30` | Combined units, decimals, `h:mm` |
| `awake 90s`, `awake 2d` | Seconds and days (maximum 7 days) |
| `awake 10 mins`, `awake 2 hours` | Long unit names work too |
| `awake 3` | **A bare number shows both readings: 3h and 3m.** For 1–12, hours come first; for bigger numbers, minutes come first (`awake 45` → 45m, then 45h) |
| `awake until 17:30`, `awake @6pm`, `awake until 9:15am` | Until a clock time (tomorrow if that time has passed today) |

## Choosing the mode in the query

Add `lid` (or `closed` / `clamshell`) for closed-lid mode, and `idle` to force idle-only:

```
awake lid           → Keep Awake with Closed Lid (indefinitely) first
awake lid 2h        → closed-lid for 2 hours
awake lid until 7am → closed-lid until 07:00
awake idle 3        → idle-only, 3h or 3m
```

## Keyboard modifiers

On any **start** item:

| Key | Does |
| --- | --- |
| ↩ | Start as shown |
| ⌘↩ | Same duration in the **other mode** (idle-only ⇄ closed-lid) |
| ⌥↩ | Same session with the **opposite display choice**. With the default settings, that means the display sleeps while the Mac stays awake |

Alfred shows what each modifier will do in the subtitle while you hold the key.

## Menu bar indicator

While a session runs, an icon appears in the menu bar:

- ☕ **cup**: idle-only session
- 💻 **laptop**: closed-lid session
- ⚠ **triangle**: sleep is disabled but the safety guardian isn't running (choose *Stop* to fix)

The title shows the time left (`42m`, `1h 05m`, or `∞` for indefinite). Click it for:

- the mode, end time and display choice
- **Extend +15 Minutes** / **Extend +1 Hour** (timed sessions only)
- **Stop & Restore Normal Sleep**

The icon removes itself when the session ends. If the session ended on its own (timer, low battery, heat), you get a notification saying why. To hide the icon, turn off [Menu bar](Settings#menu-bar) in Settings.

## Stopping

Any of these ends the session and restores normal sleep:
- `awake` → ↩ on the top row
- menu bar icon → **Stop & Restore Normal Sleep**
- the timer running out

Closed-lid mode asks for your admin password when you stop it early, unless you set up the [sudoers rule](Settings#passwordless-closed-lid-mode).

## Updating

Type `awake update`:
- **Check for updates now** asks GitHub for the latest release.
- **Install Insomniac X.Y.Z** appears when a newer version is available. It downloads the release, verifies its checksum, bundle ID and version, then opens it, and Alfred asks you to confirm the update. Your settings are kept.

You don't need to check by hand: once a day the menu shows **Update available: Insomniac X.Y.Z** at the bottom when there is one. See [Updates](Settings#updates) to make it automatic or turn it off. Copies installed from the Alfred Gallery are updated by Alfred instead.

## Uninstalling

Type `awake uninstall` and press ↩. This removes the root helper and the boot guard (see [Closed-Lid Mode](Closed-Lid-Mode)). Then delete the workflow in Alfred Preferences.

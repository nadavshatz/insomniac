# Wiring Insomniac in the Alfred 5 Workflow Editor

The release `.alfredworkflow` comes fully wired. This guide is for building it by hand, or for understanding what `info.plist` contains.

## 1. Create the workflow

1. Open Alfred Preferences → **Workflows** → **+** → *Blank Workflow*.
2. Fill in **Name** `Insomniac`, **Bundle Id** `io.github.nadavshatz.insomniac`, **Created By** and **Website**. Drag `workflow/icon.png` onto the icon well.
3. Right-click the workflow → *Open in Finder*. Copy everything from this repo's `workflow/` folder into that folder: `status_filter.sh`, `toggle_engine.sh`, `lib/`, `helper/` and `icons/`.
4. Make the scripts executable:
   ```sh
   chmod 755 status_filter.sh toggle_engine.sh helper/insomniac-helper.sh
   ```

## 2. User configuration (*Configure Workflow…* → [≡] button)

| Type | Variable | Default | Label |
| --- | --- | --- | --- |
| Text Field | `keyword` | `awake` | Keyword |
| Text Field | `presets` | `15m,30m,1h,2h,6h,12h` | Preset durations |
| Checkbox | `prevent_display_sleep` | ✔ | Prevent display sleep |
| Text Field | `battery_floor` | `10` | Battery floor (%) |
| Checkbox | `thermal_guard` | ✔ | Thermal guard |

Alfred exports these to both scripts as environment variables. The scripts also read `alfred_workflow_data`, which Alfred sets automatically. State is stored at `~/Library/Application Support/Alfred/Workflow Data/io.github.nadavshatz.insomniac/state`.

## 3. Blocks

```
┌────────────────────┐   ┌──────────────────┐   ┌────────────────────┐
│ Script Filter      │──▶│ Run Script       │──▶│ Post Notification  │
│ {var:keyword}      │   │ toggle_engine.sh │   │ Title: Insomniac   │
│ status_filter.sh   │   │                  │   │ Text:  {query}     │
└────────────────────┘   └──────────────────┘   └────────────────────┘
```

### Script Filter (Inputs → Script Filter)
| Setting | Value |
| --- | --- |
| Keyword | `{var:keyword}` · *Argument Optional* · ✔ with space |
| Title / Subtext | `Insomniac — keep your Mac awake` / `Status, timers and closed-lid mode` |
| Language | **External Script**, Script File `status_filter.sh` (the `#!/bin/zsh -f` shebang is used) |
| with input as | `argv` |
| Run behaviour | *Terminate previous script*, *Immediately after each character* |
| Alfred filters results | **off** (the script parses the query itself) |

The script returns `"rerun": 1` while a session is active, so Alfred refreshes the countdown every second. It also sets `"skipknowledge": true` to keep the item order fixed.

### Run Script (Actions → Run Script)
| Setting | Value |
| --- | --- |
| Language | **External Script**, Script File `toggle_engine.sh` |
| with input as | `argv` |
| Run behaviour | **Sequentially** (the engine also takes a file lock) |

The engine receives the item's `arg`, for example `start_idle 900`, `start_idle 900 display=0`, `start_closed_lid 0`, `extend 3600`, `stop`, `restore` or `uninstall`. It prints a one-line result.

### Post Notification (Outputs → Post Notification)
Title `Insomniac`, Text `{query}`, ✔ *Only show if passed in argument has content*.

Connect the three blocks left to right. Leave the modifier on the connection empty: the ⌘↩ (other mode) and ⌥↩ (other display choice) alternatives come from the `mods` key in the Script Filter JSON.

## 4. Icons

| File | Used for |
| --- | --- |
| `icon.png` | Workflow icon (coffee cup) |
| `icons/active.png` | Status row, idle-only session active |
| `icons/lid.png` | Status row and items for closed-lid mode |
| `icons/idle.png` | *Keep Awake Indefinitely* |
| `icons/timer.png` | Presets, custom durations, Extend |
| `icons/warning.png` | Orphaned/degraded `disablesleep`, bad input |
| `icons/info.png` | Other apps' assertions, last-session explanation |
| `icons/custom.png` | *Custom duration…* hint |
| `icons/stop.png` | Uninstall |

`scripts/make_icons.py` regenerates them. To use system glyphs instead, point the items at SF-Symbols exports or at `/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/*.icns`.

## 5. Optional extras

- **Hotkey:** add *Triggers → Hotkey* → connect to the Script Filter to open the status view with one keystroke.
- **External Trigger:** add *Triggers → External Trigger* (id `toggle`) → connect to the Run Script with argument `stop`. Then `osascript -e 'tell application id "com.runningwithcrayons.Alfred" to run trigger "toggle" in workflow "io.github.nadavshatz.insomniac" with argument "stop"'` works from Shortcuts and cron.
- **Terminal use:** the engine also works without Alfred, e.g. `./toggle_engine.sh start_closed_lid 3600`.

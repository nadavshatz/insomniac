# Insomniac

**Insomniac** is an Alfred 5 workflow that keeps your Mac awake. It has timers, a live countdown, a menu bar indicator, and a closed-lid mode that works on Apple Silicon. Normal sleep always comes back on its own, even after a crash or reboot.

It's pure `zsh` plus tools that ship with macOS. It needs no Python, Homebrew or other installs.

## Quick start

1. Download `Insomniac-x.y.z.alfredworkflow` from [Releases](https://github.com/nadavshatz/insomniac/releases) and double-click it.
2. Open Alfred and type **`awake`**.
3. Pick **Keep Awake Indefinitely**, a preset like **1h**, or type your own time: `awake 45m`.
4. To stop, type `awake` again and press ↩ on the top row. You can also use the menu bar icon → **Stop**.

## Pages

| Page | What's there |
| --- | --- |
| [Usage](Usage) | Everything you can type, keyboard modifiers, the menu bar icon |
| [Settings](Settings) | Every option in *Configure Workflow…*, with recommendations |
| [Closed-Lid Mode](Closed-Lid-Mode) | How lid-closed operation works, the admin prompt, safety failsafes |
| [Troubleshooting](Troubleshooting) | Common questions and fixes |

## The two modes at a glance

| | **Idle Only** (default) | **Closed-Lid** |
| --- | --- | --- |
| Mechanism | `caffeinate -i` | `pmset -a disablesleep 1` |
| Stops idle sleep | ✅ | ✅ |
| Works with the lid closed | ❌ (closing the lid sleeps the Mac) | ✅ |
| Needs an admin password | Never | Yes, once per start/stop (or never, with the [optional sudoers rule](Settings#passwordless-closed-lid-mode)) |
| Leaves anything behind on a crash | No | No: a boot guard resets it |

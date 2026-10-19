<!-- Post in https://www.alfredforum.com/forum/3-share-your-workflows/ -->

**Title:** Insomniac: keep your Mac awake with timers, a menu bar countdown and real closed-lid support

**Body:**

Hi all, I'm sharing **Insomniac**, a workflow for keeping your Mac awake.

**Download:** https://github.com/nadavshatz/insomniac/releases/latest
**Source & docs:** https://github.com/nadavshatz/insomniac · [wiki](https://github.com/nadavshatz/insomniac/wiki)

**What it does**
- `awake` shows a menu: your last-used session on top, then *Keep Awake Indefinitely*, *Keep Awake with Closed Lid*, and presets (15m to 12h).
- Type any duration: `45m`, `1h30m`, `2:30`, `until 17:30`. A bare number like `awake 3` offers both 3h and 3m.
- While a session runs, the top result is a live countdown (`Active (Idle Only): 42m 07s remaining`), with *Extend* and *Switch mode* below it. A menu bar icon shows the time left too.
- ⌘↩ switches mode (idle-only or closed-lid); ⌥↩ lets the display sleep while the Mac stays awake.

**Closed-lid mode** uses `pmset -a disablesleep 1`, the only supported way to override lid sleep on Apple Silicon. It asks for an admin password. A small root-owned helper restores normal sleep:
- when the timer ends (no password needed with the lid shut);
- on low battery;
- on a thermal warning;
- if the helper is killed.

A boot-time LaunchDaemon also resets it after a crash or restart. The README explains exactly what runs as root and why.

**No dependencies:** it's pure zsh plus tools that ship with macOS, with no Python, Homebrew or compiled binaries. MIT licensed, with a CI-tested suite (mocked `pmset`/`caffeinate`) on every change.

Feedback and bug reports are very welcome, either here or as [GitHub issues](https://github.com/nadavshatz/insomniac/issues).

## Usage

Keep your Mac awake via the `awake` keyword. Pick a preset, repeat your last session, or type a duration such as `45m`, `1h30m`, `3` (offers 3h and 3m) or `until 17:30`.

![Starting a session](images/menu.png)

* <kbd>↩</kbd> Keep awake for the chosen time. Idle sleep is prevented, and the Mac still sleeps when you close the lid.
* <kbd>⌘</kbd><kbd>↩</kbd> Same duration in Closed-Lid mode: the Mac stays awake with the lid shut.
* <kbd>⌥</kbd><kbd>↩</kbd> Same session with the opposite display choice. For example, let the screen sleep while the Mac stays awake.

While a session runs, the first result shows a live countdown. Press <kbd>↩</kbd> on it to stop and restore normal sleep, or pick *Extend* or *Switch mode*. A menu bar icon shows the time left, with the same actions.

![Active session](images/active.png)

Add `lid` to a query (`awake lid 2h`) to start in Closed-Lid mode.

Closed-Lid mode changes the system setting `pmset -a disablesleep`, so macOS asks for an administrator password. Normal sleep is restored automatically when the timer ends, when the battery runs low, when the Mac gets hot, and at the next startup after a crash.

Configure the keyword, presets, display behaviour, menu bar icon and safety limits in the [Workflow’s Configuration](https://www.alfredapp.com/help/workflows/user-configuration/).

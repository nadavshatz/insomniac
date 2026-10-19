# Troubleshooting

### Typing `awake` shows nothing / the wrong results
Make sure the keyword in [Settings](Settings#keyword) matches what you type, and that the workflow is enabled in Alfred Preferences.

### The Mac still went to sleep in idle-only mode
- Closing the lid always sleeps the Mac in idle-only mode. Use [Closed-Lid Mode](Closed-Lid-Mode).
- The timer may have ended. Type `awake` and check the status row.

### The display turned off but I wanted it on
Check that [Prevent display sleep](Settings#prevent-display-sleep) is ticked, and that you didn't start the session with ⌥↩, which flips it. The status row and menu bar menu show `display stays on` or `display can sleep`.

### Closed-lid mode keeps asking for my password
macOS requires it to change system sleep settings: once to start, and once to stop early. A timer running out never prompts. To skip the prompts, see [passwordless closed-lid mode](Settings#passwordless-closed-lid-mode).

### "Cancelled — nothing was changed"
You dismissed the authorization dialog. Nothing was changed, so try again.

### "⚠ System sleep is disabled (pmset disablesleep 1)"
Sleep is disabled, but no Insomniac session is guarding it. Usually the guardian was force-quit, or another tool set it. Press ↩ on that row to restore. Manually: `sudo pmset -a disablesleep 0`.

### The menu bar icon doesn't appear
- Check that [Menu bar](Settings#menu-bar) is ticked, then start a new session.
- On recent macOS versions, check *System Settings → Menu Bar* in case the item is hidden. Menu bar managers (Bartender, Ice) can hide it too.
- The icon only shows while a session is running.

### I get no notifications
Allow notifications for **Alfred**. Menu bar notifications come from `osascript`, which macOS usually lists as **Script Editor**, so allow that too in *System Settings → Notifications*.

### Another app is also keeping the Mac awake
The menu lists them in *Also preventing sleep: …*. Insomniac doesn't control those apps. See details with `pmset -g assertions`.

### How do I check what Insomniac is doing?
```sh
pmset -g | grep SleepDisabled            # 1 while closed-lid mode is active
pmset -g assertions | grep caffeinate    # idle-only sessions
cat ~/Library/Application\ Support/Alfred/Workflow\ Data/io.github.nadavshatz.insomniac/state
```

### "Update not installed: checksum mismatch" (or wrong bundle id / version mismatch)
The download didn't match what the release says it should be, so it was deleted and nothing was installed. Try again later, or download the release by hand from [Releases](https://github.com/nadavshatz/insomniac/releases). If it keeps happening, please open an issue.

### "Could not reach GitHub to check for updates"
You're offline, or a firewall or VPN blocks github.com. Insomniac works normally regardless. Only the update check is skipped.

### Completely remove everything
Run `awake uninstall`, then delete the workflow. Manual fallback:
```sh
sudo pmset -a disablesleep 0
sudo rm -f /Library/PrivilegedHelperTools/io.github.nadavshatz.insomniac.helper \
           /Library/LaunchDaemons/io.github.nadavshatz.insomniac.bootguard.plist
```

### Reporting a bug
Open an [issue](https://github.com/nadavshatz/insomniac/issues) with your macOS version, Mac model, what you typed, and the output of the commands above.

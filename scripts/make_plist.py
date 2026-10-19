#!/usr/bin/env python3
"""Regenerate workflow/info.plist (dev-only, stdlib only).

Object graph:  Script Filter ──▶ Run Script ──▶ Post Notification
"""
import plistlib
from pathlib import Path

VERSION = "1.1.0"
SF, RS, PN = ("A1F0C0FE-0001-4000-8000-000000000001",
              "A1F0C0FE-0002-4000-8000-000000000002",
              "A1F0C0FE-0003-4000-8000-000000000003")

README = """Insomniac — keep your Mac awake, with a live countdown and true closed-lid support.

Type the keyword (default: awake) to see status or pick a mode:
  awake                 menu / live status
  awake 45m | 1h30m     timed idle-only session (⌘↩ = closed-lid)
  awake lid 2h          timed closed-lid session
  ⌥↩ on a start item    same, with the opposite display choice
  awake until 17:30     until a wall-clock time
  awake uninstall       remove the privileged helper

Closed-lid mode uses `pmset -a disablesleep 1` and asks for an administrator
password once per change. A root-owned guardian restores normal sleep when the
timer ends, the battery runs low, or the Mac gets hot; a boot guard restores it
after any crash or restart.

Source & docs: https://github.com/nadavshatz/insomniac"""


def conn(dest):
    return [{"destinationuid": dest, "modifiers": 0, "modifiersubtext": "", "vitoclose": False}]


info = {
    "bundleid": "io.github.nadavshatz.insomniac",
    "name": "Insomniac",
    "description": "Keep your Mac awake — timers, live countdown, closed-lid mode",
    "category": "Tools",
    "createdby": "Nadav Shatz",
    "webaddress": "https://github.com/nadavshatz/insomniac",
    "version": VERSION,
    "readme": README,
    "disabled": False,
    "connections": {SF: conn(RS), RS: conn(PN)},
    "objects": [
        {
            "uid": SF, "type": "alfred.workflow.input.scriptfilter", "version": 3,
            "config": {
                "keyword": "{var:keyword}",
                "withspace": True,
                "argumenttype": 1,            # argument optional
                "argumenttrimmode": 0,
                "argumenttreatemptyqueryasnil": True,
                "alfredfiltersresults": False,
                "alfredfiltersresultsmatchmode": 0,
                "queuemode": 1,               # terminate previous run
                "queuedelaymode": 0,
                "queuedelaycustom": 3,
                "queuedelayimmediatelyinitially": True,
                "title": "Insomniac — keep your Mac awake",
                "subtext": "Status, timers and closed-lid mode",
                "runningsubtext": "Checking power state…",
                "type": 8,                    # external script (uses shebang)
                "scriptfile": "status_filter.sh",
                "script": "",
                "scriptargtype": 1,           # pass query as argv
                "escaping": 102,
            },
        },
        {
            "uid": RS, "type": "alfred.workflow.action.script", "version": 2,
            "config": {
                "type": 8, "scriptfile": "toggle_engine.sh", "script": "",
                "scriptargtype": 1, "escaping": 102, "concurrently": False,
            },
        },
        {
            "uid": PN, "type": "alfred.workflow.output.notification", "version": 1,
            "config": {
                "title": "Insomniac", "text": "{query}",
                "onlyshowifquerypopulated": True,
                "lastpathcomponent": False, "removeextension": False,
            },
        },
    ],
    "uidata": {
        SF: {"xpos": 40.0, "ypos": 40.0, "note": "Status + menu. Re-runs every second while active."},
        RS: {"xpos": 260.0, "ypos": 40.0, "note": "Backend: caffeinate / pmset / root guardian."},
        PN: {"xpos": 470.0, "ypos": 40.0},
    },
    "userconfigurationconfig": [
        {"variable": "keyword", "type": "textfield", "label": "Keyword",
         "description": "Avoid 'sleep': it collides with Alfred's built-in Sleep system command.",
         "config": {"default": "awake", "placeholder": "awake", "required": True, "trim": True}},
        {"variable": "presets", "type": "textfield", "label": "Preset durations",
         "description": "Comma-separated, e.g. 15m,30m,1h,2h,6h,12h",
         "config": {"default": "15m,30m,1h,2h,6h,12h", "placeholder": "15m,30m,1h,2h,6h,12h", "required": False, "trim": True}},
        {"variable": "prevent_display_sleep", "type": "checkbox", "label": "Display",
         "description": "Default for new sessions. Unchecked: the display sleeps, the Mac stays awake. ⌥↩ flips it for one session.",
         "config": {"default": True, "required": False, "text": "Prevent display sleep"}},
        {"variable": "menubar", "type": "checkbox", "label": "Menu bar",
         "description": "While a session runs, show a menu bar icon with the time left, Extend and Stop.",
         "config": {"default": True, "required": False, "text": "Show menu bar indicator"}},
        {"variable": "battery_floor", "type": "textfield", "label": "Battery floor (%)",
         "description": "Closed-lid mode ends automatically on battery at or below this level. 0 disables.",
         "config": {"default": "10", "placeholder": "10", "required": False, "trim": True}},
        {"variable": "thermal_guard", "type": "checkbox", "label": "Thermal guard",
         "description": "End closed-lid mode when macOS reports a thermal warning.",
         "config": {"default": True, "required": False, "text": "Restore sleep when the Mac runs hot"}},
    ],
    "variablesdontexport": [],
}

if __name__ == "__main__":
    out = Path(__file__).resolve().parent.parent / "workflow" / "info.plist"
    with open(out, "wb") as f:
        plistlib.dump(info, f, sort_keys=True)
    print("wrote", out)

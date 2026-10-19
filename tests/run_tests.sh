#!/bin/zsh -f
# Insomniac test-suite. Runs on macOS or Linux with zsh; never touches real
# power settings: pmset/caffeinate/osascript/sudo are mocked and all system
# paths are redirected into a temporary sandbox via INSOMNIAC_PREFIX.
#
#   zsh tests/run_tests.sh

setopt extended_glob no_unset
(( EUID != 0 )) || { print -u2 "Run the tests as a normal user: as root the helper deliberately ignores test overrides."; exit 2 }
zmodload zsh/datetime
ROOT=${0:A:h:h}
WF=$ROOT/workflow
SANDBOX=$(mktemp -d)
trap 'pkill -f "$SANDBOX" 2>/dev/null; pkill -f "insomniac.*guard" 2>/dev/null; rm -rf $SANDBOX' EXIT

export MOCK_DIR=$SANDBOX/mock INSOMNIAC_PREFIX=$SANDBOX/root
export INSOMNIAC_PMSET=$ROOT/tests/mocks/pmset
export INSOMNIAC_CAFFEINATE=$ROOT/tests/mocks/caffeinate
export INSOMNIAC_OSASCRIPT=$ROOT/tests/mocks/osascript
export INSOMNIAC_POLL=1
export alfred_workflow_data=$SANDBOX/data
export PATH=$ROOT/tests/mocks:$PATH
mkdir -p $MOCK_DIR $INSOMNIAC_PREFIX/var/run

integer pass=0 fail=0
ok()   { print -P "%F{green}✔%f $1"; (( ++pass )) }
bad()  { print -P "%F{red}✘ $1%f"; [[ -n ${2:-} ]] && print -r -- "   $2"; (( ++fail )) }
check() { local d=$1; shift; if "$@"; then ok $d; else bad $d; fi }

engine() { $WF/toggle_engine.sh "$*" }
filter() { $WF/status_filter.sh "${1:-}" }
titles() { filter "${1:-}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join(i["title"] for i in d["items"]))' }
sd() { cat $MOCK_DIR/sleepdisabled 2>/dev/null || print 0 }
statefile() { cat $alfred_workflow_data/state 2>/dev/null }
alive() { [[ $(ps -p $1 -o stat= 2>/dev/null) == [^Z]* ]] }  # zombies count as dead
wait_for() { integer i; for (( i = 0; i < 60; i++ )); do eval "$1" && return 0; sleep 0.1; done; return 1 }

# --- unit: duration parsing ---------------------------------------------------
source $WF/lib/common.zsh
for spec in 45:2700 45m:2700 3h:10800 1h30m:5400 1.5h:5400 90s:90 2:30:9000 "2 hours":7200 \
            "10 mins":600 1d:86400; do
  in=${spec%:*} want=${spec##*:}
  parse_duration "$in"; [[ $REPLY == $want ]] && ok "parse_duration '$in' = $want" || bad "parse_duration '$in' got '$REPLY' want $want"
done
for in in "" abc 0 "8d" "5x"; do
  parse_duration "$in" && bad "parse_duration '$in' should fail" || ok "parse_duration rejects '$in'"
done
parse_clock 23:59 && (( REPLY > 0 && REPLY <= 86400 )) && ok "parse_clock 23:59" || bad "parse_clock 23:59 ($REPLY)"
parse_clock 5pm && ok "parse_clock 5pm" || bad "parse_clock 5pm"
parse_clock 25:00 && bad "parse_clock 25:00 should fail" || ok "parse_clock rejects 25:00"
[[ $(fmt_remaining 2527) == "42m 07s" ]] && ok "fmt_remaining" || bad "fmt_remaining $(fmt_remaining 2527)"
[[ $(fmt_dur 5400) == "1h 30m" ]] && ok "fmt_dur" || bad "fmt_dur $(fmt_dur 5400)"

# --- inactive menu -------------------------------------------------------------
out=$(filter)
print -r -- $out | python3 -c 'import json,sys; json.load(sys.stdin)' && ok "filter emits valid JSON" || bad "invalid JSON" "$out"
t=$(titles)
check "inactive menu lists indefinite + closed-lid + presets" \
  eval '[[ $t == *"Keep Awake Indefinitely"* && $t == *"Keep Awake with Closed Lid"* && $t == *"Keep Awake for 2h"* ]]'
check "foreign assertion owners are listed (powerd ignored)" eval '[[ $t == *"Also preventing sleep: zoom.us"* && $t != *powerd* ]]'
check "custom query '45m'" eval '[[ $(titles 45m) == "Keep Awake for 45m"* ]]'
check "custom query 'lid 3h' prefers closed-lid" eval '[[ $(titles "lid 3h") == "Keep Awake with Closed Lid for 3h"* ]]'
check "garbage query is flagged" eval '[[ $(titles banana) == "Unrecognised duration"* ]]'
check "inactive filter does not rerun" eval '[[ $(filter) != *rerun* ]]'

# --- idle mode -----------------------------------------------------------------
msg=$(engine start_idle 600)
check "start_idle message" eval '[[ $msg == "Keeping your Mac awake for 10m"* ]]'
check "state records idle" eval '[[ $(statefile) == *MODE=idle* ]]'
check "status shows idle countdown" eval '[[ $(titles) == "Active (Idle Only): "<9-10>m* ]]'
check "active filter reruns" eval '[[ $(filter) == *'"'"'"rerun":1'"'"'* ]]'
check "idle mode never asked for admin" eval '[[ ! -e $MOCK_DIR/osascript.log ]]'
cpid=${${(M)${(f)"$(statefile)"}:#CAF_PID=*}#CAF_PID=}
msg=$(engine stop)
check "stop kills caffeinate" eval '! alive $cpid'
check "stop clears state" eval '[[ -z $(statefile) && $msg == "Normal sleep restored" ]]'

engine start_idle 1 >/dev/null; sleep 1.6
check "expired idle session self-heals to inactive" eval '[[ $(titles) == *"Keep Awake Indefinitely"* && $(titles) != Active* && -z $(statefile) ]]'

# --- closed-lid mode with timer ----------------------------------------------
msg=$(engine start_closed_lid 3)
check "closed-lid message" eval '[[ $msg == "Closed-lid mode on for 3s"* ]]'
check "helper + boot guard installed" eval '[[ -x $INSOMNIAC_PREFIX/Library/PrivilegedHelperTools/$IN_LABEL.helper && -f $INSOMNIAC_PREFIX/Library/LaunchDaemons/$IN_LABEL.bootguard.plist ]]'
check "disablesleep=1" eval '[[ $(sd) == 1 ]]'
check "status shows Closed-Lid" eval '[[ $(titles) == "Active (Closed-Lid): "* ]]'
check "timer expiry restores disablesleep=0" wait_for '[[ $(sd) == 0 ]]'
sleep 0.3
check "guardian recorded reason=timer" eval '[[ $(cat $IN_LAST_REASON) == timer* ]]'
check "filter explains automatic restore" eval '[[ $(titles) == *"Last closed-lid session ended"* ]]'

# --- second session must not reinstall the helper ------------------------------
: > $MOCK_DIR/osascript.log
engine start_closed_lid 0 >/dev/null
check "helper not reinstalled when unchanged" eval '[[ $(<$MOCK_DIR/osascript.log) != *install* ]]'
check "indefinite closed-lid status" eval '[[ $(titles) == "Active (Closed-Lid): Indefinite"* ]]'
gpid=$(cat $IN_GUARD_PIDFILE)
engine stop >/dev/null
check "stop restores disablesleep=0" eval '[[ $(sd) == 0 ]]'
check "stop terminates guardian" wait_for '! alive $gpid'
check "reason=stopped" eval '[[ $(cat $IN_LAST_REASON) == stopped* ]]'

# --- failsafes ---------------------------------------------------------------
engine start_closed_lid 0 >/dev/null
print "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t7%; discharging; 0:20 remaining present: true" > $MOCK_DIR/batt
check "low battery restores sleep" wait_for '[[ $(sd) == 0 ]]'
sleep 0.3
check "reason=battery" eval '[[ $(cat $IN_LAST_REASON) == battery* ]]'
rm $MOCK_DIR/batt

engine start_closed_lid 0 >/dev/null
print "Thermal Warning Level = 2" > $MOCK_DIR/therm
check "thermal warning restores sleep" wait_for '[[ $(sd) == 0 ]]'
rm $MOCK_DIR/therm

engine start_closed_lid 0 >/dev/null
kill -HUP $(cat $IN_GUARD_PIDFILE)
check "killed guardian restores sleep" wait_for '[[ $(sd) == 0 ]]'
engine stop >/dev/null

engine start_closed_lid 0 >/dev/null
kill -KILL $(cat $IN_GUARD_PIDFILE); sleep 0.2
check "SIGKILLed guardian → degraded warning" eval '[[ $(titles) == "⚠ System sleep is disabled"* ]]'
engine stop >/dev/null
check "restore from degraded" eval '[[ $(sd) == 0 ]]'

print -n 1 > $MOCK_DIR/sleepdisabled
check "orphaned disablesleep is detected" eval '[[ $(titles) == "⚠ System sleep is disabled"* ]]'
engine restore >/dev/null
check "orphan restored" eval '[[ $(sd) == 0 ]]'

# --- cancelled authorization ---------------------------------------------------
touch $MOCK_DIR/cancel
msg=$(engine start_closed_lid 600)
check "cancel leaves system untouched" eval '[[ $msg == Cancelled* && $(sd) == 0 && -z $(statefile) ]]'
rm $MOCK_DIR/cancel

# --- extend / switch -----------------------------------------------------------
engine start_idle 600 >/dev/null
engine extend 3600 >/dev/null
check "extend adds time" eval '[[ $(titles) == "Active (Idle Only): 1h "(09|10)m* ]]'
engine start_closed_lid 600 >/dev/null
check "switch idle → closed-lid" eval '[[ $(titles) == "Active (Closed-Lid): "* && $(sd) == 1 ]]'
engine start_idle 600 >/dev/null
check "switch closed-lid → idle restores pmset" eval '[[ $(titles) == "Active (Idle Only): "* && $(sd) == 0 ]]'
engine stop >/dev/null

# --- per-session display choice (⌥↩) -----------------------------------------
check "start items offer ⌥↩ with the opposite display choice" \
  eval '[[ $(filter 45m) == *'"'"'"alt":{"arg":"start_idle 2700 display=0"'"'"'* ]]'
msg=$(engine start_idle 600)
check "default keeps display awake (-d)" eval '[[ $(<$MOCK_DIR/caffeinate.args) == *-d* && $(statefile) == *DISPLAY=1* ]]'
msg=$(engine start_idle 600 display=0)
check "display=0 drops -d, Mac stays awake (-i)" eval '[[ $(<$MOCK_DIR/caffeinate.args) == "-i -t 600" && $(statefile) == *DISPLAY=0* ]]'
check "notification mentions display can sleep" eval '[[ $msg == *"display can sleep"* ]]'
check "status row shows display choice" eval '[[ $(filter) == *"display can sleep · ↩ Stop"* ]]'
engine extend 900 >/dev/null
check "extend keeps the session's display choice" eval '[[ $(<$MOCK_DIR/caffeinate.args) != *-d* && $(statefile) == *DISPLAY=0* ]]'
check "switch item carries display choice" eval '[[ $(filter) == *"start_closed_lid "<->" display=0"* ]]'
engine start_closed_lid 600 display=0 >/dev/null
check "closed-lid honours display=0" eval '[[ $(<$MOCK_DIR/caffeinate.args) != *-d* && $(sd) == 1 ]]'
prevent_display_sleep=0 engine start_idle 600 >/dev/null
check "setting off → display sleeps by default" eval '[[ $(<$MOCK_DIR/caffeinate.args) != *-d* ]]'
check "setting off → ⌥↩ keeps display on" eval '[[ $(prevent_display_sleep=0 filter 45m) == *"start_idle 2700 display=1"* ]]'
engine stop >/dev/null

# --- presets, bare numbers, last used ------------------------------------------
rm -f $alfred_workflow_data/last
t=$(titles)
check "6h and 12h presets are offered" eval '[[ $t == *"Keep Awake for 6h"* && $t == *"Keep Awake for 12h"* ]]'
check "bare small number: hours first, then minutes" eval '[[ $(titles 3 | head -2 | tr "\n" "|") == "Keep Awake for 3h|Keep Awake for 3m|" ]]'
check "bare large number: minutes first" eval '[[ $(titles 45) == "Keep Awake for 45m"$'"'"'\n'"'"'"Keep Awake for 1d 21h"* ]]'
check "bare number too big for hours: minutes only" eval '[[ $(titles 200) == "Keep Awake for 3h 20m"* && $(titles 200) != *"8d"* ]]'
check "lid + bare number" eval '[[ $(titles "lid 2") == "Keep Awake with Closed Lid for 2h"* ]]'
check "bare zero is rejected" eval '[[ $(titles 0) == "Unrecognised duration"* ]]'
check "units still work (3m)" eval '[[ $(titles 3m) == "Keep Awake for 3m"* && $(titles 3m) != *"for 3h"* ]]'

engine start_idle 2700 >/dev/null; engine stop >/dev/null
check "last used is the top suggestion" eval '[[ $(titles) == "Keep Awake for 45m · last used"* ]]'
check "last used is not repeated in the presets" eval '(( $(titles | grep -c "^Keep Awake for 45m") == 1 ))'
check "last used survives with indefinite still offered" eval '[[ $(titles) == *"Keep Awake Indefinitely"* ]]'
engine start_idle 600 display=0 >/dev/null; engine stop >/dev/null
check "last used remembers display choice" eval '[[ $(filter) == *'"'"'"arg":"start_idle 600 display=0"'"'"'* ]]'
engine start_closed_lid 7200 >/dev/null; engine stop >/dev/null
check "last used closed-lid comes first" eval '[[ $(titles) == "Keep Awake with Closed Lid for 2h · last used"* ]]'
check "after closed-lid, presets default to closed-lid" eval '[[ $(titles) == *"Keep Awake with Closed Lid for 6h"* ]]'
check "typing idle hides a closed-lid last-used" eval '[[ $(titles idle) != *"last used"* ]]'
engine start_idle 600 >/dev/null; engine extend 900 >/dev/null
check "extend does not overwrite last used" eval '[[ $(<$alfred_workflow_data/last) == "idle 600 1" ]]'
engine start_closed_lid 300 display=1 nolast >/dev/null
check "switch (nolast) does not overwrite last used" eval '[[ $(<$alfred_workflow_data/last) == "idle 600 1" ]]'
engine stop >/dev/null
check "unknown engine option is rejected" eval '[[ $(engine start_idle 60 bogus) == "Unknown option: bogus" ]]'
print -n "lid 99999999 1" > $alfred_workflow_data/last
check "corrupt last-used file is ignored" eval '[[ $(titles) != *"last used"* && $(titles) == "Keep Awake Indefinitely"* ]]'
rm -f $alfred_workflow_data/last

# --- reconcile -------------------------------------------------------------------
engine start_closed_lid 0 >/dev/null
cpid=${${(M)${(f)"$(statefile)"}:#CAF_PID=*}#CAF_PID=}
check "reconcile reports active" eval '[[ $(engine reconcile) == active ]]'
print "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t5%; discharging; 0:10 remaining present: true" > $MOCK_DIR/batt
wait_for '[[ $(sd) == 0 ]]'; rm $MOCK_DIR/batt
check "reconcile reports inactive after guardian ended it" eval '[[ $(engine reconcile) == inactive ]]'
check "reconcile stops the companion caffeinate" wait_for '! alive $cpid'

# --- uninstall -----------------------------------------------------------------
engine uninstall >/dev/null
check "uninstall removes helper and boot guard" eval '[[ ! -e $INSOMNIAC_PREFIX/Library/PrivilegedHelperTools/$IN_LABEL.helper && ! -e $INSOMNIAC_PREFIX/Library/LaunchDaemons/$IN_LABEL.bootguard.plist ]]'

print "\n$pass passed, $fail failed"
(( fail == 0 ))

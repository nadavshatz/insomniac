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
export INSOMNIAC_JXA=$ROOT/tests/mocks/jxa
export INSOMNIAC_CURL=$ROOT/tests/mocks/curl INSOMNIAC_OPEN=$ROOT/tests/mocks/open
export INSOMNIAC_POLL=1
export alfred_workflow_data=$SANDBOX/data alfred_workflow_cache=$SANDBOX/cache
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

# --- menu bar indicator lifecycle --------------------------------------------------
mbpid() { cat $alfred_workflow_data/menubar.pid 2>/dev/null }
engine start_idle 600 >/dev/null
m1=$(mbpid)
check "start launches the menu bar indicator" eval '[[ -n $m1 ]] && alive $m1'
check "indicator gets data dir and engine path" eval '[[ $(tail -1 $MOCK_DIR/jxa.log) == "-l JavaScript $WF/menubar.js $alfred_workflow_data $WF/toggle_engine.sh" ]]'
engine extend 900 >/dev/null
check "extend keeps the same indicator (no duplicates)" eval '[[ $(mbpid) == $m1 ]] && alive $m1'
engine start_closed_lid 600 >/dev/null
check "mode switch keeps the same indicator" eval '[[ $(mbpid) == $m1 ]] && alive $m1'
INSOMNIAC_FROM_MENUBAR=1 engine stop >/dev/null
check "stop from the indicator's own menu leaves it to quit itself" eval 'alive $m1 && [[ $(sd) == 0 ]]'
kill $m1 2>/dev/null
engine start_idle 600 >/dev/null
m2=$(mbpid)
engine stop >/dev/null
check "stop from Alfred closes the indicator" wait_for '! alive $m2'
check "stop removes the indicator pid file" eval '[[ -z $(mbpid) ]]'
menubar=0 engine start_idle 600 >/dev/null
check "menubar=0 does not launch it" eval '[[ -z $(mbpid) ]]'
engine stop >/dev/null
engine start_idle 600 >/dev/null; m3=$(mbpid)
menubar=0 engine start_idle 300 >/dev/null
check "turning the setting off closes a running indicator" wait_for '! alive $m3'
engine stop >/dev/null
sleep 300 &; decoy=$!
print -n $decoy > $alfred_workflow_data/menubar.pid      # recycled PID, not ours
engine start_idle 600 >/dev/null
check "stale pid file: a fresh indicator is launched" eval '[[ $(mbpid) != $decoy ]] && alive $(mbpid)'
print -n $decoy > $alfred_workflow_data/menubar.pid
engine stop >/dev/null
check "stale pid file: an unrelated process is never killed" eval 'alive $decoy'
kill $decoy; pkill -f jxa-mock 2>/dev/null

# --- updates (GitHub build) -----------------------------------------------------
source $WF/lib/update.zsh
for spec in "1.2.0 1.1.0" "1.10.0 1.9.9" "2.0.0 1.99.99" "1.2.0 1.2.0-beta" "v1.2.0 1.1.9" "1.1.1 1.1"; do
  version_gt ${=spec} && ok "version_gt ${spec/ / > }" || bad "version_gt ${spec/ / > }"
done
for spec in "1.1.0 1.1.0" "1.0.9 1.1.0" "1.2.0-beta 1.2.0" "0.9 1.0.0"; do
  version_gt ${=spec} && bad "version_gt ${spec/ / > } should be false" || ok "not version_gt ${spec/ / > }"
done
CUR=$(current_version)
check "current version read from info.plist" eval '[[ $CUR == <->.<->.<-> ]]'
UPD=$alfred_workflow_cache/update
mkpkg() {  # version → a fake GitHub release containing a real build
  zsh $ROOT/scripts/build.sh $1 >/dev/null
  mkdir -p $MOCK_DIR/releases/v$1
  mv -f $ROOT/dist/Insomniac-$1.alfredworkflow $ROOT/dist/Insomniac-$1.alfredworkflow.sha256 $MOCK_DIR/releases/v$1/
}
heads() { grep -c -- '-fsSI' $MOCK_DIR/curl.log 2>/dev/null || print 0 }
mkpkg 9.0.0
print 9.0.0 > $MOCK_DIR/latest
rm -f $UPD $MOCK_DIR/curl.log
filter >/dev/null
check "first menu open starts a background update check" wait_for '[[ $(cat $UPD 2>/dev/null) == "9.0.0 "* ]]'
check "newer release is announced in the menu" eval '[[ $(titles) == *"Update available: Insomniac 9.0.0"* ]]'
check "announce item installs that version" eval '[[ $(filter) == *'"'"'"arg":"update_install 9.0.0"'"'"'* ]]'
n=$(heads); filter >/dev/null; filter >/dev/null; sleep 0.3
check "checks at most once a day" eval '[[ $(heads) == $n ]]'
print -r -- "9.0.0 $(( EPOCHSECONDS - 90000 ))" > $UPD
filter >/dev/null
check "rechecks after 24h" wait_for '(( $(heads) > n ))'
check "update_mode=off hides the notice" eval '[[ $(update_mode=off titles) != *"Update available"* ]]'
bg_done() { wait_for '! pgrep -f "toggle_engine.sh update_check" >/dev/null' }
bg_done; rm -f $UPD; update_mode=off filter >/dev/null; sleep 0.3
check "update_mode=off never checks" eval '[[ ! -e $UPD ]]'
print -r -- "9.0.0 $EPOCHSECONDS" > $UPD
t=$(titles update)
check "'update' query offers install + check now" eval '[[ $t == "Install Insomniac 9.0.0"*"Check for updates now"* ]]'
print $CUR > $MOCK_DIR/latest
check "manual check: up to date" eval '[[ $(engine update_check now) == "Insomniac $CUR is up to date" ]]'
check "no notice when current" eval '[[ $(titles) != *"Update available"* ]]'
check "install refuses when already current" eval '[[ $(engine update_install) == "Insomniac $CUR is up to date" ]]'
touch $MOCK_DIR/offline
check "manual check offline reports it" eval '[[ $(engine update_check now) == "Could not reach GitHub to check for updates" ]]'
rm $MOCK_DIR/offline
print 9.0.0 > $MOCK_DIR/latest
check "manual check: newer available" eval '[[ $(engine update_check now) == "Insomniac 9.0.0 is available"* ]]'
rm -f $MOCK_DIR/open.log
msg=$(engine update_install 9.0.0)
check "install downloads, verifies and opens in Alfred" eval '[[ $msg == "Opening Insomniac 9.0.0. Confirm the update in Alfred" && $(<$MOCK_DIR/open.log) == $alfred_workflow_cache/Insomniac-9.0.0.alfredworkflow ]]'
cp $MOCK_DIR/releases/v9.0.0/Insomniac-9.0.0.alfredworkflow.sha256 $SANDBOX/good.sha
print "0000000000000000000000000000000000000000000000000000000000000000  x" > $MOCK_DIR/releases/v9.0.0/Insomniac-9.0.0.alfredworkflow.sha256
rm -f $MOCK_DIR/open.log
check "tampered download is rejected" eval '[[ $(engine update_install 9.0.0) == "Update not installed: checksum mismatch" && ! -e $MOCK_DIR/open.log ]]'
check "rejected download is deleted" eval '[[ ! -e $alfred_workflow_cache/Insomniac-9.0.0.alfredworkflow ]]'
cp $SANDBOX/good.sha $MOCK_DIR/releases/v9.0.0/Insomniac-9.0.0.alfredworkflow.sha256
mkdir -p $MOCK_DIR/releases/v9.1.0
cp $MOCK_DIR/releases/v9.0.0/Insomniac-9.0.0.alfredworkflow $MOCK_DIR/releases/v9.1.0/Insomniac-9.1.0.alfredworkflow
(cd $MOCK_DIR/releases/v9.1.0 && sha256sum Insomniac-9.1.0.alfredworkflow > Insomniac-9.1.0.alfredworkflow.sha256)
check "package whose version differs from the tag is rejected" eval '[[ $(engine update_install 9.1.0) == "Update not installed: version mismatch" ]]'
X=$SANDBOX/evil; mkdir -p $X/pkg $MOCK_DIR/releases/v9.2.0
(cd $X/pkg && unzip -q $MOCK_DIR/releases/v9.0.0/Insomniac-9.0.0.alfredworkflow \
  && sed -i.bak "s/$IN_LABEL/com.example.evil/; s/<string>9.0.0</<string>9.2.0</" info.plist && rm info.plist.bak \
  && zip -q -r $MOCK_DIR/releases/v9.2.0/Insomniac-9.2.0.alfredworkflow .)
(cd $MOCK_DIR/releases/v9.2.0 && sha256sum Insomniac-9.2.0.alfredworkflow > Insomniac-9.2.0.alfredworkflow.sha256)
check "package with another bundle id is rejected" eval '[[ $(engine update_install 9.2.0) == "Update not installed: wrong bundle id" ]]'
mkdir -p $MOCK_DIR/releases/v9.3.0
cp $MOCK_DIR/releases/v9.0.0/Insomniac-9.0.0.alfredworkflow $MOCK_DIR/releases/v9.3.0/Insomniac-9.3.0.alfredworkflow
check "release without a checksum is rejected" eval '[[ $(engine update_install 9.3.0) == "Update not installed: checksum missing" ]]'
check "missing release asset is reported" eval '[[ $(engine update_install 9.9.9) == "Update not installed: download failed" ]]'
check "invalid version argument is rejected" eval '[[ $(engine update_install "1.x") == "Invalid version: 1.x" ]]'
rm -f $UPD $MOCK_DIR/open.log
update_mode=auto engine update_check >/dev/null
check "update_mode=auto downloads and opens on its own" eval '[[ $(<$MOCK_DIR/open.log) == *Insomniac-9.0.0.alfredworkflow ]]'
rm -f $MOCK_DIR/open.log
engine update_check >/dev/null
check "update_mode=notify never opens anything by itself" eval '[[ ! -e $MOCK_DIR/open.log ]]'

# --- Gallery build has no updater --------------------------------------------------
zsh $ROOT/scripts/build.sh --gallery 9.0.0 >/dev/null
G=$SANDBOX/gallery; mkdir -p $G && (cd $G && unzip -q $ROOT/dist/Insomniac-9.0.0-gallery.alfredworkflow)
rm -f $ROOT/dist/Insomniac-9.0.0-gallery.alfredworkflow*
gtitles() { $G/status_filter.sh "${1:-}" | python3 -c 'import json,sys; print("\n".join(i["title"] for i in json.load(sys.stdin)["items"]))' }
bg_done; rm -f $UPD; gtitles >/dev/null; sleep 0.3
check "gallery build never checks for updates" eval '[[ ! -e $UPD ]]'
print -r -- "9.9.9 $EPOCHSECONDS" > $UPD
check "gallery build never shows update notices" eval '[[ $(gtitles) != *"Update available"* ]]'
check "gallery build: 'update' explains Alfred handles it" eval '[[ $(gtitles update) == "Insomniac"* && $($G/status_filter.sh update) == *"Alfred Gallery"* ]]'
check "gallery build: engine refuses to self-update" eval '[[ $($G/toggle_engine.sh update_install 9.9.9) == "Updates for this copy are handled by Alfred" ]]'
rm -f $UPD

# --- uninstall -----------------------------------------------------------------
engine uninstall >/dev/null
check "uninstall leaves no indicator running" eval '[[ -z $(mbpid) ]]'
check "uninstall removes helper and boot guard" eval '[[ ! -e $INSOMNIAC_PREFIX/Library/PrivilegedHelperTools/$IN_LABEL.helper && ! -e $INSOMNIAC_PREFIX/Library/LaunchDaemons/$IN_LABEL.bootguard.plist ]]'

print "\n$pass passed, $fail failed"
(( fail == 0 ))

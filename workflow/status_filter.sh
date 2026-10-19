#!/bin/zsh -f
# status_filter.sh — Insomniac Script Filter.
#
# Reads the real system state (state file, caffeinate PID, `pmset -g`,
# `pmset -g assertions`, guardian PID) and emits Alfred Script Filter JSON.
# While a session is active it asks Alfred to re-run it every second
# ("rerun": 1) so the countdown is live.

source "${0:A:h}/lib/common.zsh"

# ---------------------------------------------------------------------------
# Alfred JSON
# ---------------------------------------------------------------------------
typeset -a ITEMS
typeset -i RERUN=0

js() {  # JSON string literal
  local s=${1-}
  s=${s//\\/\\\\}; s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}; s=${s//$'\t'/\\t}; s=${s//[[:cntrl:]]/}
  print -rn -- "\"$s\""
}

# item TITLE SUBTITLE ARG VALID ICON [CMD_ARG CMD_SUB] [ALT_ARG ALT_SUB]
item() {
  local t=$1 sub=$2 arg=$3 valid=$4 icon=$5
  local j="{\"title\":$(js "$t"),\"subtitle\":$(js "$sub"),\"arg\":$(js "$arg"),\"valid\":$valid"
  j+=",\"icon\":{\"path\":$(js "icons/$icon.png")}"
  local -a mods=()
  [[ -n ${6:-} ]] && mods+=("\"cmd\":{\"arg\":$(js "$6"),\"subtitle\":$(js "$7"),\"valid\":true}")
  [[ -n ${8:-} ]] && mods+=("\"alt\":{\"arg\":$(js "$8"),\"subtitle\":$(js "$9"),\"valid\":true}")
  (( $#mods )) && j+=",\"mods\":{${(j:,:)mods}}"
  ITEMS+=("$j}")
}

emit() {
  local out="{\"skipknowledge\":true"
  (( RERUN )) && out+=",\"rerun\":1"
  print -r -- "$out,\"items\":[${(j:,:)ITEMS}]}"
}

# ---------------------------------------------------------------------------
# Query parsing:  [lid|idle] [<duration> | until <time> | @<time>]
# Sets Q_MODE (idle|lid|""), Q_SECS (0 = none), Q_BAD (1 = unparseable)
# ---------------------------------------------------------------------------
typeset Q_MODE= Q_RAW=${(L)${1:-}}
typeset -i Q_SECS=0 Q_BAD=0 Q_UNTIL=0
parse_query() {
  local -a words rest
  local w
  words=(${(z)Q_RAW})
  for w in $words; do
    case $w in
      lid|closed|clamshell|lidclosed|-l) Q_MODE=lid ;;
      idle|awake|-i)                     Q_MODE=idle ;;
      until|at)                          Q_UNTIL=1 ;;
      @*)                                Q_UNTIL=1; [[ -n ${w#@} ]] && rest+=(${w#@}) ;;
      *)                                 rest+=($w) ;;
    esac
  done
  (( $#rest )) || return 0
  if (( Q_UNTIL )); then parse_clock "${(j::)rest}"; else parse_duration "${(j::)rest}"; fi \
    && Q_SECS=$REPLY || Q_BAD=1
}
parse_query

integer DEF_DISP=0; is_true $CFG_DISPLAY && DEF_DISP=1
disp_note() { (( $1 )) && print "display stays on" || print "display can sleep" }

# Offer a timed (or indefinite) pair: primary mode on ↩, the other on ⌘↩.
offer() {  # secs prefer_mode title_prefix
  integer s=$1
  local idle_t="Keep Awake Indefinitely" lid_t="Keep Awake with Closed Lid" tail= icon=idle
  if (( s )); then
    idle_t="Keep Awake for $(fmt_dur $s)" lid_t+=" for $(fmt_dur $s)" icon=timer
    tail="Until $(fmt_clock $(( EPOCHSECONDS + s ))) · "
  fi
  local note=$(disp_note $DEF_DISP)
  local idle_sub="${tail}Prevents idle sleep (caffeinate), $note · ⌘↩ closed-lid · ⌥↩ display"
  local lid_sub="${tail}Disables all system sleep (pmset), $note · needs admin · ⌘↩ idle-only · ⌥↩ display"
  # ⌥↩: same session with the opposite display choice.
  integer alt=$(( !DEF_DISP ))
  local alt_sub="${tail}Same, but the $(disp_note $alt) for this session"
  (( alt )) || alt_sub="${tail}Same, but let the display sleep this time (Mac stays awake)"
  if [[ $2 == lid ]]; then
    item "$3$lid_t" "$lid_sub" "start_closed_lid $s" true lid "start_idle $s" "$idle_sub" \
         "start_closed_lid $s display=$alt" "$alt_sub"
  else
    item "$3$idle_t" "$idle_sub" "start_idle $s" true $icon "start_closed_lid $s" "$lid_sub" \
         "start_idle $s display=$alt" "$alt_sub"
  fi
}

# ---------------------------------------------------------------------------
# Reconcile recorded state with reality
# ---------------------------------------------------------------------------
state_read
integer SD=$(sleep_disabled)
GPID=$(guard_pid)
STATUS=inactive        # inactive | active | degraded | orphan

case ${ST[MODE]:-} in
  idle)
    if caf_alive "${ST[CAF_PID]:-}"; then STATUS=active; else state_clear; ST=(); fi ;;
  lid)
    if (( SD )) && guard_alive "${GPID:-${ST[GUARD_PID]:-}}"; then STATUS=active
    elif (( SD )); then STATUS=degraded
    else state_clear; ST=(); fi ;;
esac
[[ $STATUS == inactive ]] && (( SD )) && STATUS=orphan

# ---------------------------------------------------------------------------
# Build the menu
# ---------------------------------------------------------------------------
if [[ $Q_RAW == (#s)[[:space:]]#uninstall[[:space:]]#(#e) ]]; then
  item "Uninstall Insomniac's privileged helper" \
       "Stops any session, restores sleep, removes the root helper and boot guard" \
       uninstall true stop
  emit; exit 0
fi

case $STATUS in
  active)
    RERUN=1
    integer exp=${ST[EXPIRES]:-0}
    mode_label="Idle Only"; icon=active
    [[ ${ST[MODE]} == lid ]] && mode_label="Closed-Lid" icon=lid
    if (( exp )); then
      left=$(( exp - EPOCHSECONDS ))
      if (( left > 0 )); then
        title="Active ($mode_label): $(fmt_remaining $left) remaining"
      else
        title="Active ($mode_label): finishing…"
      fi
      when="Ends $(fmt_clock $exp)"
    else
      title="Active ($mode_label): Indefinite"
      when="Since $(fmt_clock ${ST[STARTED]:-$EPOCHSECONDS})"
    fi
    integer sdisp=${ST[DISPLAY]:-$DEF_DISP}
    item "$title" "$when · $(disp_note $sdisp) · ↩ Stop and restore normal sleep" stop true $icon

    if (( Q_SECS )); then
      offer $Q_SECS ${Q_MODE:-${ST[MODE]}} "Replace with: "
    elif (( Q_BAD )); then
      item "Unrecognised duration “$Q_RAW”" "Try 45m · 1h30m · 2:30 · until 17:30 · lid 2h" "" false warning
    else
      if (( exp )); then
        item "Extend +15m" "New end: $(fmt_clock $(( exp + 900 )))" "extend 900" true timer
        item "Extend +1h"  "New end: $(fmt_clock $(( exp + 3600 )))" "extend 3600" true timer
      fi
      integer rem=$(( exp ? (exp - EPOCHSECONDS > 0 ? exp - EPOCHSECONDS : 0) : 0 ))
      if [[ ${ST[MODE]} == idle ]]; then
        item "Switch to Closed-Lid mode" "Keeps the same timer · needs admin" "start_closed_lid $rem display=$sdisp" true lid
      else
        item "Switch to Idle-Only mode" "Re-enables lid-close sleep · keeps the same timer" "start_idle $rem display=$sdisp" true idle
      fi
    fi
    ;;
  degraded|orphan)
    if [[ $STATUS == degraded ]]; then
      sub="The guardian process is gone, so no timer or battery failsafe is running · ↩ Restore now"
    else
      sub="Set outside an active Insomniac session · ↩ Restore normal sleep (needs admin)"
    fi
    item "⚠ System sleep is disabled (pmset disablesleep 1)" "$sub" restore true warning
    ;;
esac

if [[ $STATUS != active ]]; then
  if (( Q_BAD )); then
    item "Unrecognised duration “$Q_RAW”" "Try 45m · 1h30m · 2:30 · until 17:30 · lid 2h" "" false warning
  elif (( Q_SECS )); then
    offer $Q_SECS ${Q_MODE:-idle} ""
  else
    if [[ $Q_MODE == lid ]]; then
      offer 0 lid ""; offer 0 idle ""
    else
      offer 0 idle ""; offer 0 lid ""
    fi
    for p in ${(s:,:)CFG_PRESETS}; do
      parse_duration "$p" && offer $REPLY ${Q_MODE:-idle} ""
    done
    item "Custom duration…" "Type e.g. 45m · 3h · 1h30m · 2:30 · until 17:30 · lid 2h" "" false custom
  fi

  # Explain how the last closed-lid session ended, if recent and automatic.
  if [[ -r $IN_LAST_REASON ]]; then
    read -r why at < $IN_LAST_REASON
    if [[ ${at:-} == <-> ]] && (( EPOCHSECONDS - at < 3600 )); then
      case $why in
        timer)    msg="timer finished" ;;
        battery)  msg="battery fell to ${CFG_BATT_FLOOR}%" ;;
        thermal)  msg="thermal pressure detected" ;;
        external) msg="sleep was re-enabled outside Insomniac" ;;
        *)        msg= ;;
      esac
      [[ -n $msg ]] && item "Last closed-lid session ended at $(fmt_clock $at)" \
        "Normal sleep was restored automatically: $msg" "" false info
    fi
  fi
fi

# Other apps holding sleep assertions (Zoom, Xcode, other caffeinates…).
foreign_assertions "${ST[CAF_PID]:-}"
if (( $#reply )); then
  item "Also preventing sleep: ${(j:, :)reply}" "Reported by pmset -g assertions (not controlled by Insomniac)" "" false info
fi

emit

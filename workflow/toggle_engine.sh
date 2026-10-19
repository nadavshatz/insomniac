#!/bin/zsh -f
# toggle_engine.sh — Insomniac backend (Alfred "Run Script" action).
#
# Usage (Alfred passes the whole arg as one string; both forms work):
#   toggle_engine.sh start_idle [seconds] [display=0|1]
#       caffeinate; 0/omitted = indefinite
#   toggle_engine.sh start_closed_lid [seconds] [display=0|1]
#       pmset disablesleep 1 + root guardian
#   display=1 keeps the display on (caffeinate -d), display=0 lets it sleep
#   while the system stays awake. Omitted: the prevent_display_sleep setting.
#   nolast: don't remember this start as the "last used" suggestion.
#   toggle_engine.sh extend <seconds>             add time to the running session
#   toggle_engine.sh stop                         end everything, restore defaults
#   toggle_engine.sh uninstall                    stop + remove root helper & boot guard
#   toggle_engine.sh reconcile                    print active|degraded|orphan|inactive
#   toggle_engine.sh status                       print raw state (debugging)
#
# Whatever is printed last on stdout becomes the Alfred notification text.

source "${0:A:h}/lib/common.zsh"
typeset -r ENGINE=${0:A}

# ---------------------------------------------------------------------------
# Privilege escalation
# ---------------------------------------------------------------------------

# True when the root-owned helper and boot guard are installed and identical
# to the copies shipped in this workflow version.
helper_current() {
  [[ -f $IN_HELPER_DST && -f $IN_DAEMON_DST ]] || return 1
  if [[ -z $IN_PREFIX ]]; then
    zmodload -F zsh/stat b:zstat
    local -a st
    zstat -A st +uid -- $IN_HELPER_DST || return 1
    (( st[1] == 0 )) || return 1
  fi
  cmp -s -- $IN_HELPER_SRC $IN_HELPER_DST && cmp -s -- $IN_DAEMON_SRC $IN_DAEMON_DST
}

# run_privileged <helper-args...>
# 1. Optional passwordless path: a sudoers rule for the helper (see README).
# 2. Otherwise the native macOS authorization dialog via AppleScript.
# The first run (or after an update) also installs the helper + boot guard,
# inside the same single authorization prompt.
# Results go to globals (not stdout) so callers keep PRIV_ERR: PRIV_OUT, PRIV_ERR.
typeset -g PRIV_OUT= PRIV_ERR=
run_privileged() {
  PRIV_OUT= PRIV_ERR=
  if helper_current && sudo -n -l $IN_HELPER_DST "$@" >/dev/null 2>&1; then
    PRIV_OUT=$(sudo -n $IN_HELPER_DST "$@")
    return
  fi

  local cmd="set -e; "
  if ! helper_current; then
    cmd+="/bin/mkdir -p ${(qq)IN_HELPER_DST:h} ${(qq)IN_DAEMON_DST:h}; "
    cmd+="/usr/bin/install -o root -g wheel -m 755 ${(qq)IN_HELPER_SRC} ${(qq)IN_HELPER_DST}; "
    cmd+="/usr/bin/install -o root -g wheel -m 644 ${(qq)IN_DAEMON_SRC} ${(qq)IN_DAEMON_DST}; "
  fi
  cmd+="${(qq)IN_HELPER_DST} ${(j: :)${(qq)@}}"

  local prompt="Insomniac needs to change the system sleep setting (pmset disablesleep)."
  local errf="$IN_DATA/.osa_err.$$" rc
  PRIV_OUT=$($OSASCRIPT \
        -e 'on run argv' \
        -e 'do shell script (item 1 of argv) with prompt (item 2 of argv) with administrator privileges' \
        -e 'end run' \
        -- "$cmd" "$prompt" 2>$errf)
  rc=$?
  PRIV_ERR=$(<$errf); rm -f -- $errf
  return rc
}

priv_cancelled() { [[ $PRIV_ERR == *(-128)* ]] }

# ---------------------------------------------------------------------------
# caffeinate
# ---------------------------------------------------------------------------
# 1 = keep the display awake for this session (set in main).
typeset -gi DISP=0

spawn_caffeinate() {  # seconds (0 = indefinite) → REPLY=pid
  local -a flags=(-i)
  (( DISP )) && flags+=(-d)
  (( $1 > 0 )) && flags+=(-t $1)
  # nohup + closed stdio: survives Alfred finishing the script, and Alfred
  # does not wait on it.
  /usr/bin/nohup $CAFFEINATE $flags </dev/null >/dev/null 2>&1 &
  REPLY=$!
  disown
  sleep 0.2
  caf_alive $REPLY
}

kill_caffeinate() {
  caf_alive "${ST[CAF_PID]:-}" && kill -TERM ${ST[CAF_PID]} 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------
# Menu bar indicator (menubar.js, run by osascript -l JavaScript)
# ---------------------------------------------------------------------------
menubar_running() {  # → REPLY=pid
  local pid=
  [[ -r $IN_MENUBAR_PID ]] && pid=$(<$IN_MENUBAR_PID)
  proc_matches "$pid" '*menubar.js*' && REPLY=$pid
}

menubar_stop() {
  # Called from the indicator's own menu: it posts the result and quits by
  # itself once the session is gone, so don't kill it mid-call.
  [[ -n ${INSOMNIAC_FROM_MENUBAR:-} ]] && return 0
  menubar_running && kill -TERM $REPLY 2>/dev/null
  rm -f -- $IN_MENUBAR_PID
  return 0
}

# Start the indicator if enabled and not already running. It inherits this
# process's environment (Alfred's workflow variables), so engine calls made
# from its menu behave exactly like calls made from Alfred.
menubar_ensure() {
  is_true $CFG_MENUBAR || { menubar_stop; return 0 }
  menubar_running && return 0
  [[ -r $IN_MENUBAR_JS ]] || return 0
  /usr/bin/nohup $JXA_RUNNER -l JavaScript $IN_MENUBAR_JS "$IN_DATA" "$ENGINE" \
    </dev/null >/dev/null 2>&1 &
  print -r -- $! > $IN_MENUBAR_PID
  disown
  return 0
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------
# 0 = don't record this start as the last-used suggestion (set in main).
typeset -gi REMEMBER=1

describe() {  # mode secs → human message
  local what="Keeping your Mac awake"
  [[ $1 == lid ]] && what="Closed-lid mode on"
  local disp=; (( DISP )) || disp=" · display can sleep"
  if (( $2 > 0 )); then
    print -r -- "$what for $(fmt_dur $2) (until $(fmt_clock $(( EPOCHSECONDS + $2 ))))$disp"
  else
    print -r -- "$what indefinitely$disp"
  fi
}

cmd_start_idle() {
  integer secs=${1:-0}
  state_read
  # Leaving closed-lid mode requires restoring pmset first.
  if [[ ${ST[MODE]:-} == lid ]] || (( $(sleep_disabled) )); then
    if ! run_privileged disable; then
      priv_cancelled && { print "Cancelled — closed-lid mode is still active"; return 0 }
      print "Could not restore sleep: ${PRIV_ERR:-unknown error}"; return 1
    fi
  fi
  kill_caffeinate
  if ! spawn_caffeinate $secs; then
    state_clear
    print "Failed to start caffeinate"; return 1
  fi
  state_write MODE=idle STARTED=$EPOCHSECONDS SECS=$secs \
              EXPIRES=$(( secs ? EPOCHSECONDS + secs : 0 )) CAF_PID=$REPLY DISPLAY=$DISP
  (( REMEMBER )) && last_write idle $secs $DISP
  menubar_ensure
  describe idle $secs
}

cmd_start_closed_lid() {
  integer secs=${1:-0}
  integer expires=$(( secs ? EPOCHSECONDS + secs : 0 ))
  local floor=$CFG_BATT_FLOOR thermal=0
  [[ $floor == <-> ]] && (( floor <= 100 )) || floor=10
  is_true $CFG_THERMAL && thermal=1

  if ! run_privileged enable $expires $floor $thermal; then
    priv_cancelled && { print "Cancelled — nothing was changed"; return 0 }
    print "Could not enable closed-lid mode: ${PRIV_ERR:-unknown error}"; return 1
  fi
  local gpid=${${(f)PRIV_OUT}[-1]:-}

  # Also hold a caffeinate assertion so behaviour with the lid OPEN matches
  # "Keep Awake" (and the display option applies).
  state_read
  kill_caffeinate
  spawn_caffeinate $secs
  state_write MODE=lid STARTED=$EPOCHSECONDS SECS=$secs EXPIRES=$expires \
              CAF_PID=${REPLY:-} GUARD_PID=$gpid DISPLAY=$DISP
  (( REMEMBER )) && last_write lid $secs $DISP
  menubar_ensure
  describe lid $secs
}

cmd_stop() {
  state_read
  if [[ ${ST[MODE]:-} == lid ]] || (( $(sleep_disabled) )) || [[ -n $(guard_pid) ]]; then
    if ! run_privileged disable; then
      priv_cancelled && { print "Cancelled — closed-lid mode is still active"; return 0 }
      print "Could not restore sleep: ${PRIV_ERR:-unknown error}"; return 1
    fi
  fi
  local was=${ST[MODE]:-}
  kill_caffeinate
  state_clear
  menubar_stop
  if [[ -n $was ]]; then print "Normal sleep restored"; else print "Sleep settings are at system defaults"; fi
}

cmd_extend() {
  integer add=${1:-0}
  (( add > 0 )) || { print "Nothing to extend"; return 1 }
  state_read || { print "No active session to extend"; return 1 }
  integer exp=${ST[EXPIRES]:-0}
  (( exp > 0 )) || { print "Session is already indefinite"; return 0 }
  integer left=$(( exp - EPOCHSECONDS )); (( left < 0 )) && left=0
  integer total=$(( left + add )); (( total > MAX_SECS )) && total=MAX_SECS
  REMEMBER=0
  if [[ ${ST[MODE]} == lid ]]; then cmd_start_closed_lid $total; else cmd_start_idle $total; fi
}

cmd_uninstall() {
  if [[ -e $IN_HELPER_DST || -e $IN_DAEMON_DST ]]; then
    local cmd="set -e; ${(qq)IN_HELPER_DST} uninstall; /bin/rm -f ${(qq)IN_DAEMON_DST}"
    [[ -x $IN_HELPER_DST ]] || cmd="/usr/bin/pmset -a disablesleep 0; /bin/rm -f ${(qq)IN_DAEMON_DST}"
    if ! $OSASCRIPT -e 'on run argv' \
         -e 'do shell script (item 1 of argv) with prompt "Insomniac will remove its privileged helper." with administrator privileges' \
         -e 'end run' -- "$cmd" >/dev/null 2>&1; then
      print "Uninstall cancelled"; return 0
    fi
  fi
  state_read && kill_caffeinate
  state_clear
  menubar_stop
  print "Privileged helper removed — you can now delete the workflow"
}

cmd_status() {
  state_read
  print -r -- "state: ${(kv)ST}"
  print -r -- "sleepdisabled: $(sleep_disabled)"
  print -r -- "guardian: $(guard_pid || print none)"
  print -r -- "helper current: $(helper_current && print yes || print no)"
}

main() {
  (( $# == 1 )) && set -- ${(z)1}
  local verb=${1:-}; shift 2>/dev/null
  local n=${1:-0} opt disp=
  [[ $n == <-> ]] || { print "Invalid duration: $n"; return 64 }
  for opt in ${@[2,-1]}; do
    case $opt in
      display=[01]) disp=${opt#display=} ;;
      nolast)       REMEMBER=0 ;;
      *)            print "Unknown option: $opt"; return 64 ;;
    esac
  done
  # Display choice: explicit display=0|1, else (for extend) the running
  # session's choice, else the workflow setting.
  if [[ -n $disp ]]; then
    DISP=$disp
  elif [[ $verb == extend ]] && state_read && [[ ${ST[DISPLAY]:-} == [01] ]]; then
    DISP=${ST[DISPLAY]}
  else
    is_true $CFG_DISPLAY && DISP=1
  fi
  (( n <= MAX_SECS )) || n=$MAX_SECS
  case $verb in
    start_idle)       cmd_start_idle $n ;;
    start_closed_lid) cmd_start_closed_lid $n ;;
    extend)           cmd_extend $n ;;
    stop|restore)     cmd_stop ;;
    uninstall)        cmd_uninstall ;;
    reconcile)        reconcile; print -r -- $STATUS ;;
    status)           cmd_status ;;
    noop|'')          return 0 ;;
    *)                print "Unknown action: $verb"; return 64 ;;
  esac
}

with_lock main "$@"

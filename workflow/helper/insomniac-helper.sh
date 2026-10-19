#!/bin/zsh -f
# insomniac-helper — the ONLY part of Insomniac that runs as root.
#
# Installed root:wheel 0755 at
#   /Library/PrivilegedHelperTools/io.github.nadavshatz.alfred-coffee.helper
# so root only ever executes a root-owned copy. It is self-contained (sources
# nothing) and runs with -f (no rc files).
#
# Commands:
#   enable <expires_epoch|0> <battery_floor_pct> <thermal_guard 0|1>
#       Stop any previous guardian, set `pmset -a disablesleep 1`, and start a
#       detached guardian. Prints the guardian PID.
#   disable
#       Stop the guardian and set `pmset -a disablesleep 0` (always).
#   status
#       Prints "sleepdisabled=<0|1> guardian=<pid|none>".
#   guard <expires_epoch|0> <battery_floor_pct> <thermal_guard 0|1>
#       Internal: the guardian loop. Restores sleep on timer expiry, low
#       battery, thermal pressure, or any catchable signal.
#   uninstall
#       disable, then remove the boot guard and this helper.

emulate -L zsh
setopt extended_glob no_unset
zmodload zsh/datetime

typeset -r LABEL="io.github.nadavshatz.alfred-coffee"

# The sandbox prefix is honoured only when NOT running as root (test-suite).
if (( EUID == 0 )); then
  typeset -r PFX="" PMSET=/usr/bin/pmset
  typeset -ri POLL=15
  export PATH=/usr/bin:/bin:/usr/sbin:/sbin
else
  typeset -r PFX="${INSOMNIAC_PREFIX:-}" PMSET="${INSOMNIAC_PMSET:-/usr/bin/pmset}"
  typeset -ri POLL=${INSOMNIAC_POLL:-15}
fi
typeset -r SELF="$PFX/Library/PrivilegedHelperTools/$LABEL.helper"
typeset -r DAEMON="$PFX/Library/LaunchDaemons/$LABEL.bootguard.plist"
typeset -r PIDFILE="$PFX/var/run/$LABEL.guardian.pid"
typeset -r LASTFILE="$PFX/var/run/$LABEL.last"

log()  { /usr/bin/logger -t insomniac -- "$*" 2>/dev/null || true }
die()  { print -u2 -- "insomniac-helper: $*"; exit 64 }

restore_sleep() {
  $PMSET -a disablesleep 0 >/dev/null 2>&1
  local rc=$?
  (( rc == 0 )) || $PMSET -a disablesleep 0 >/dev/null 2>&1   # one retry
}

record_reason() {
  print -r -- "$1 $EPOCHSECONDS" > $LASTFILE.$$ 2>/dev/null && mv -f $LASTFILE.$$ $LASTFILE
  chmod 644 $LASTFILE 2>/dev/null
}

is_guardian() {
  [[ $1 == <1-> ]] || return 1
  local cmd
  cmd=$(ps -p $1 -o command= 2>/dev/null) || return 1
  [[ $cmd == *"$LABEL.helper guard"* ]]
}

current_guardian() {
  local pid=
  [[ -r $PIDFILE ]] && pid=$(<$PIDFILE)
  is_guardian "$pid" && print $pid
}

stop_guardian() {
  local pid=$(current_guardian)
  [[ -n $pid ]] || { rm -f $PIDFILE; return 0 }
  # The guardian's TERM trap restores sleep and records reason=stopped.
  kill -TERM $pid 2>/dev/null
  integer i
  for (( i = 0; i < 50; i++ )); do
    is_guardian $pid || break
    sleep 0.1
  done
  is_guardian $pid && kill -KILL $pid 2>/dev/null
  rm -f $PIDFILE
}

validate() {  # expires floor thermal
  [[ $1 == <-> ]] || die "bad expiry: $1"
  [[ $2 == <-> ]] && (( $2 <= 100 )) || die "bad battery floor: $2"
  [[ $3 == [01] ]] || die "bad thermal flag: $3"
  (( $1 == 0 || $1 > EPOCHSECONDS )) || die "expiry is in the past"
}

# --- battery / thermal probes ---------------------------------------------
battery_low() {  # floor
  (( $1 > 0 )) || return 1
  local out
  out=$($PMSET -g batt 2>/dev/null) || return 1
  [[ $out == *"'Battery Power'"* ]] || return 1          # on AC: fine
  [[ $out == (#b)*[[:blank:]]([0-9]##)%* ]] || return 1
  (( match[1] <= $1 ))
}

thermal_hot() {
  local out line
  out=$($PMSET -g therm 2>/dev/null) || return 1
  for line in ${(f)out}; do
    # Intel: "CPU_Speed_Limit = 42" (percent of max). Trip when heavily throttled.
    if [[ $line == (#b)*CPU_Speed_Limit[[:blank:]]#=[[:blank:]]#([0-9]##)* ]]; then
      (( match[1] < 50 )) && return 0
    fi
    # Apple Silicon / Intel: a recorded thermal warning level above nominal.
    if [[ ${line:l} == (#b)*thermal*warning*level*[^0-9]([0-9]##)[^0-9]#(#e) ]]; then
      (( match[1] > 0 )) && return 0
    fi
  done
  return 1
}

# --- guardian ---------------------------------------------------------------
guard() {
  validate "$@"
  integer expires=$1 floor=$2 thermal=$3 sleeper=0
  local reason=signal

  on_exit() {
    (( sleeper )) && kill $sleeper 2>/dev/null
    restore_sleep
    record_reason $reason
    [[ $(cat $PIDFILE 2>/dev/null) == $$ ]] && rm -f $PIDFILE
    log "restored normal sleep (reason: $reason)"
    exit 0
  }
  trap 'reason=stopped; on_exit' TERM
  trap 'reason=signal; on_exit' INT HUP QUIT

  log "guardian $$ started (expires=$expires floor=$floor% thermal=$thermal)"
  while true; do
    if (( expires && EPOCHSECONDS >= expires )); then reason=timer; break; fi
    if battery_low $floor;                       then reason=battery; break; fi
    if (( thermal )) && thermal_hot;             then reason=thermal; break; fi
    # Someone else (System Settings, terminal) re-enabled sleep: nothing to guard.
    if [[ $($PMSET -g 2>/dev/null) != *SleepDisabled[[:blank:]]##1* ]]; then
      reason=external; break
    fi
    integer nap=POLL
    (( expires && expires - EPOCHSECONDS < nap )) && nap=$(( expires - EPOCHSECONDS ))
    (( nap < 1 )) && nap=1
    # Background sleep + wait so traps fire immediately instead of after the nap.
    sleep $nap &
    sleeper=$!
    wait $sleeper
    sleeper=0
  done
  on_exit
}

# --- commands ---------------------------------------------------------------
cmd=${1:-}; shift 2>/dev/null
case $cmd in
  enable)
    (( $# == 3 )) || die "usage: enable <expires> <floor> <thermal>"
    validate "$@"
    stop_guardian
    $PMSET -a disablesleep 1 || die "pmset failed"
    mkdir -p ${PIDFILE:h}
    # Detach fully: no stdio, new process reparented to launchd once we exit.
    $SELF guard "$@" </dev/null >/dev/null 2>&1 &!
    integer gpid=$!
    print -r -- $gpid > $PIDFILE
    chmod 644 $PIDFILE
    print -r -- $gpid
    ;;
  disable)
    stop_guardian
    restore_sleep
    ;;
  status)
    g=$(current_guardian)
    if [[ $($PMSET -g 2>/dev/null) == *SleepDisabled[[:blank:]]##1* ]]; then s=1; else s=0; fi
    print -r -- "sleepdisabled=$s guardian=${g:-none}"
    ;;
  guard)
    guard "$@"
    ;;
  uninstall)
    stop_guardian
    restore_sleep
    rm -f $DAEMON $LASTFILE $PIDFILE
    rm -f $SELF
    log "uninstalled"
    ;;
  *)
    die "unknown command '${cmd}'"
    ;;
esac

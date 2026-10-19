# lib/common.zsh — shared constants and helpers for Insomniac.
#
# Sourced by status_filter.sh and toggle_engine.sh (both run as the logged-in
# user). The root helper does NOT source this file: it is self-contained so
# that root never executes code from a user-writable location.

zmodload zsh/datetime   # EPOCHSECONDS, strftime
setopt extended_glob no_unset pipe_fail

# ---------------------------------------------------------------------------
# Identity & paths
# ---------------------------------------------------------------------------
typeset -r IN_LABEL="io.github.nadavshatz.insomniac"
typeset -r IN_WF_DIR="${${(%):-%x}:A:h:h}"          # .../workflow

# INSOMNIAC_PREFIX lets the test-suite redirect system paths into a sandbox.
# It is never honoured by the root helper.
typeset -r IN_PREFIX="${INSOMNIAC_PREFIX:-}"
typeset -r IN_HELPER_SRC="$IN_WF_DIR/helper/insomniac-helper.sh"
typeset -r IN_DAEMON_SRC="$IN_WF_DIR/helper/$IN_LABEL.bootguard.plist"
typeset -r IN_HELPER_DST="$IN_PREFIX/Library/PrivilegedHelperTools/$IN_LABEL.helper"
typeset -r IN_DAEMON_DST="$IN_PREFIX/Library/LaunchDaemons/$IN_LABEL.bootguard.plist"
typeset -r IN_GUARD_PIDFILE="$IN_PREFIX/var/run/$IN_LABEL.guardian.pid"
typeset -r IN_LAST_REASON="$IN_PREFIX/var/run/$IN_LABEL.last"

typeset -r PMSET="${INSOMNIAC_PMSET:-/usr/bin/pmset}"
typeset -r CAFFEINATE="${INSOMNIAC_CAFFEINATE:-/usr/bin/caffeinate}"
typeset -r OSASCRIPT="${INSOMNIAC_OSASCRIPT:-/usr/bin/osascript}"

# Alfred exports these; fall back to Alfred's conventional locations so the
# scripts can also be driven from a terminal.
typeset -r IN_DATA="${alfred_workflow_data:-$HOME/Library/Application Support/Alfred/Workflow Data/$IN_LABEL}"
typeset -r IN_STATE="$IN_DATA/state"
typeset -r IN_LOCK="$IN_DATA/.lock"
[[ -d $IN_DATA ]] || mkdir -p -m 700 -- "$IN_DATA"

# ---------------------------------------------------------------------------
# User configuration (Alfred "Configure Workflow…" variables)
# ---------------------------------------------------------------------------
is_true() { [[ ${1:l} == (1|true|yes|on) ]] }

typeset -r CFG_DISPLAY="${prevent_display_sleep:-1}"
typeset -r CFG_PRESETS="${presets:-15m,30m,1h,2h}"
typeset -r CFG_BATT_FLOOR="${battery_floor:-10}"
typeset -r CFG_THERMAL="${thermal_guard:-1}"
typeset -ri MAX_SECS=$(( 7 * 86400 ))

# ---------------------------------------------------------------------------
# State file: plain KEY=VALUE lines. Parsed, never sourced/eval'd.
# ---------------------------------------------------------------------------
typeset -gA ST
state_read() {
  ST=()
  [[ -r $IN_STATE ]] || return 1
  local line k v
  while IFS= read -r line; do
    [[ $line == (#b)([A-Z_]##)=([A-Za-z0-9_.-]#) ]] || continue
    k=$match[1] v=$match[2]
    [[ $k == (MODE|STARTED|EXPIRES|CAF_PID|GUARD_PID|SECS) ]] && ST[$k]=$v
  done < $IN_STATE
  [[ ${ST[MODE]:-} == (idle|lid) ]]
}

state_write() {  # state_write KEY=VAL ...
  local tmp="$IN_STATE.$$"
  print -rl -- "$@" > $tmp && mv -f -- $tmp $IN_STATE
}

state_clear() { rm -f -- $IN_STATE }

# ---------------------------------------------------------------------------
# System probes
# ---------------------------------------------------------------------------

# Prints 1 if `pmset -a disablesleep 1` is in effect, else 0.
sleep_disabled() {
  local out
  out=$($PMSET -g 2>/dev/null) || { print 0; return }
  if [[ $out == (#b)*SleepDisabled[[:blank:]]##([01])* ]]; then
    print $match[1]
  else
    print 0
  fi
}

# proc_matches PID PATTERN — true if PID is alive and its command line matches
# the zsh glob PATTERN. Uses ps, so it also works for root-owned processes.
proc_matches() {
  [[ $1 == <1-> ]] || return 1
  local cmd
  cmd=$(ps -p $1 -o command= 2>/dev/null) || return 1
  [[ $cmd == ${~2} ]]
}

caf_alive()   { proc_matches "${1:-}" '*caffeinate*' }
guard_alive() { proc_matches "${1:-}" "*$IN_LABEL.helper guard*" }

guard_pid() {
  local pid
  [[ -r $IN_GUARD_PIDFILE ]] && pid=$(<$IN_GUARD_PIDFILE)
  [[ ${pid:-} == <1-> ]] && print $pid
}

# Names of *other* processes holding sleep-preventing assertions.
# Sets reply=(name ...).
foreign_assertions() {
  local -a skip=(${(s: :)1:-})
  local out line name pid
  local -A seen
  reply=()
  out=$($PMSET -g assertions 2>/dev/null) || return 0
  for line in ${(f)out}; do
    [[ $line == (#b)*pid\ ([0-9]##)\(([^\)]##)\):*(PreventUserIdleSystemSleep|PreventSystemSleep|PreventUserIdleDisplaySleep|NoIdleSleepAssertion)* ]] || continue
    pid=$match[1] name=$match[2]
    (( ${skip[(Ie)$pid]} )) && continue
    [[ $name == (powerd|coreaudiod|WindowServer) ]] && continue
    [[ -n ${seen[$name]:-} ]] && continue
    seen[$name]=1
    reply+=($name)
  done
}

# ---------------------------------------------------------------------------
# Durations & formatting
# ---------------------------------------------------------------------------

# parse_duration STRING → REPLY=seconds. Accepts: 45 (minutes), 45m, 3h,
# 1h30m, 1.5h, 90s, 2d, 2:30 (h:mm), and long unit names (2 hours, 10 mins).
parse_duration() {
  local s=${${1:l}//[[:space:]]/}
  float total=0
  REPLY=
  [[ -n $s ]] || return 1
  if [[ $s == <-> ]]; then
    total=$(( s * 60 ))
  elif [[ $s == (#b)(<->):([0-5][0-9]) ]]; then
    total=$(( match[1] * 3600 + match[2] * 60 ))
  else
    local n u
    while [[ -n $s ]]; do
      [[ $s == (#b)([0-9]##(.[0-9]##|))(days|day|d|hours|hour|hrs|hr|h|minutes|minute|mins|min|m|seconds|second|secs|sec|s)(*) ]] || return 1
      n=$match[1] u=$match[3] s=$match[4]
      case $u in
        d*) total=$(( total + n * 86400 )) ;;
        h*) total=$(( total + n * 3600 )) ;;
        m*) total=$(( total + n * 60 )) ;;
        s*) total=$(( total + n )) ;;
      esac
    done
  fi
  integer secs=$total
  (( secs >= 1 && secs <= MAX_SECS )) || return 1
  REPLY=$secs
}

# parse_clock STRING → REPLY=seconds from now until that wall-clock time
# (today, or tomorrow if already past). Accepts 17:30, 5pm, 5:15am, 0930.
parse_clock() {
  local s=${${1:l}//[[:space:]]/} ap= today
  integer h m=0 target
  if [[ $s == (#b)(<->)(:([0-5][0-9])|)(am|pm|) ]]; then
    h=$match[1]; [[ -n $match[3] ]] && m=$match[3]; ap=$match[4]
  else
    return 1
  fi
  # "0930" → 09:30
  if [[ -z $match[2] && ${#match[1]} == 4 && -z $ap ]]; then
    h=${match[1][1,2]} m=${match[1][3,4]}
  fi
  if [[ -n $ap ]]; then
    (( h >= 1 && h <= 12 )) || return 1
    (( h == 12 )) && h=0
    [[ $ap == pm ]] && (( h += 12 ))
  fi
  (( h <= 23 && m <= 59 )) || return 1
  strftime -s today '%Y-%m-%d' $EPOCHSECONDS
  strftime -r -s target '%Y-%m-%d %H:%M' "$today $(printf '%02d:%02d' $h $m)" || return 1
  (( target <= EPOCHSECONDS )) && (( target += 86400 ))
  REPLY=$(( target - EPOCHSECONDS ))
  (( REPLY >= 1 && REPLY <= MAX_SECS ))
}

# Compact human duration for labels: 1h 30m · 45m · 2d 3h · 30s
fmt_dur() {
  integer t=$1 d h m s
  (( d = t / 86400, h = t % 86400 / 3600, m = t % 3600 / 60, s = t % 60 ))
  local -a out
  (( d )) && out+=(${d}d)
  (( h )) && out+=(${h}h)
  (( m )) && out+=(${m}m)
  (( s && t < 3600 )) && out+=(${s}s)
  print -r -- ${out:-0s}
}

# Countdown with stable width for the live-updating status row.
fmt_remaining() {
  integer t=$(( $1 > 0 ? $1 : 0 )) h m s
  (( h = t / 3600, m = t % 3600 / 60, s = t % 60 ))
  if   (( h )); then printf '%dh %02dm' $h $m
  elif (( m )); then printf '%dm %02ds' $m $s
  else               printf '%ds' $s
  fi
}

fmt_clock() {
  local out fmt='%H:%M'
  (( $1 - EPOCHSECONDS > 86400 )) && fmt='%a %H:%M'
  strftime -s out $fmt $1
  print -r -- $out
}

# ---------------------------------------------------------------------------
# Locking (prevents two engine runs racing on state / pmset)
# ---------------------------------------------------------------------------
with_lock() {
  zmodload zsh/system
  : >> $IN_LOCK
  local fd
  zsystem flock -t 10 -f fd $IN_LOCK || { print -u2 "insomniac: could not acquire lock"; return 75 }
  "$@"
  local rc=$?
  zsystem flock -u $fd
  return rc
}

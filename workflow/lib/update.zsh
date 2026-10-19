# lib/update.zsh — update checks against GitHub Releases.
#
# Only in the GitHub build. `scripts/build.sh --gallery` leaves this file out,
# because Alfred Gallery workflows are updated by Alfred itself and must not
# update themselves. Every caller checks that this file exists first.
#
# How it works, with no API token and no JSON parsing:
#   check    HEAD https://github.com/<repo>/releases/latest → 302 Location
#            …/releases/tag/vX.Y.Z. Result cached for 24h.
#   install  download Insomniac-X.Y.Z.alfredworkflow + .sha256 from the
#            release, verify the checksum, bundle id and version, then `open`
#            it. Alfred shows its own "update workflow" prompt and keeps the
#            user's settings.

typeset -r UPD_REPO="${INSOMNIAC_UPDATE_REPO:-https://github.com/nadavshatz/insomniac}"
typeset -r CURL="${INSOMNIAC_CURL:-/usr/bin/curl}"
typeset -r OPEN="${INSOMNIAC_OPEN:-/usr/bin/open}"
typeset -r IN_CACHE="${alfred_workflow_cache:-$HOME/Library/Caches/com.runningwithcrayons.Alfred/Workflow Data/$IN_LABEL}"
typeset -r UPD_FILE="$IN_CACHE/update"           # "<latest-version> <checked-epoch>"
typeset -r CFG_UPDATE="${update_mode:-notify}"   # notify | auto | off
typeset -ri UPD_INTERVAL=86400
[[ -d $IN_CACHE ]] || mkdir -p -m 700 -- "$IN_CACHE"

current_version() {
  if [[ -n ${alfred_workflow_version:-} ]]; then
    print -r -- $alfred_workflow_version; return
  fi
  local key=$'\n\t<key>version</key>\n\t<string>' p
  p=$(<$IN_WF_DIR/info.plist)
  [[ $p == *$key* ]] || return 1
  p=${p#*$key}
  print -r -- ${p%%</string>*}
}

# version_gt A B: true if A is newer than B. Numeric X.Y.Z; a pre-release
# (1.2.0-beta) ranks below its release (1.2.0).
version_gt() {
  local a=${1#v} b=${2#v}
  local -a A=(${(s:.:)${a%%-*}}) B=(${(s:.:)${b%%-*}})
  integer i x y
  for i in 1 2 3; do
    x=${A[i]:-0} y=${B[i]:-0}
    (( x > y )) && return 0
    (( x < y )) && return 1
  done
  [[ $a != *-* && $b == *-* ]]
}

valid_version() { [[ $1 == <->.<->.<->(-[A-Za-z0-9.]##|) ]] }

# update_available → REPLY=newer version from the cache.
update_available() {
  REPLY=
  [[ $CFG_UPDATE == off || ! -r $UPD_FILE ]] && return 1
  local v t
  read -r v t < $UPD_FILE
  valid_version "${v:-}" || return 1
  version_gt $v "$(current_version)" || return 1
  REPLY=$v
}

# update_due: no check in the last 24h (and checks not switched off).
update_due() {
  [[ $CFG_UPDATE == off ]] && return 1
  [[ -r $UPD_FILE ]] || return 0
  local v t
  read -r v t < $UPD_FILE
  [[ ${t:-} == <-> ]] || return 0
  (( EPOCHSECONDS - t >= UPD_INTERVAL ))
}

update_mark_checked() {  # version
  print -r -- "$1 $EPOCHSECONDS" > $UPD_FILE.$$ && mv -f -- $UPD_FILE.$$ $UPD_FILE
}

# fetch_latest → REPLY=latest release version (network).
fetch_latest() {
  REPLY=
  local hdr
  hdr=$($CURL -fsSI --max-time 10 "$UPD_REPO/releases/latest" 2>/dev/null) || return 1
  [[ $hdr == (#b)*[Ll]ocation:[[:blank:]]#[^[:space:]]#/releases/tag/v([0-9][0-9A-Za-z.-]#)* ]] || return 1
  valid_version $match[1] || return 1
  REPLY=$match[1]
}

sha256_of() {
  if [[ -x /usr/bin/shasum ]]; then /usr/bin/shasum -a 256 -- $1
  else sha256sum -- $1; fi | read -r REPLY _
}

# download_release VERSION → REPLY=path of a verified .alfredworkflow
download_release() {
  local v=$1 name="Insomniac-$1.alfredworkflow"
  local url="$UPD_REPO/releases/download/v$v/$name" dst="$IN_CACHE/$name"
  REPLY=
  rm -f -- $dst $dst.sha256
  $CURL -fsSL --max-time 120 -o $dst "$url" 2>/dev/null || { UPD_ERR="download failed"; return 1 }
  $CURL -fsSL --max-time 30 -o $dst.sha256 "$url.sha256" 2>/dev/null || { UPD_ERR="checksum missing"; return 1 }
  local want got
  read -r want _ < $dst.sha256
  sha256_of $dst; got=$REPLY; REPLY=
  [[ -n $want && ${(L)want} == ${(L)got} ]] || { UPD_ERR="checksum mismatch"; rm -f -- $dst; return 1 }
  local plist
  plist=$(unzip -p -- $dst info.plist 2>/dev/null) || { UPD_ERR="not a workflow package"; return 1 }
  [[ $plist == *"<string>$IN_LABEL</string>"* ]] || { UPD_ERR="wrong bundle id"; return 1 }
  [[ $plist == *$'\n\t<key>version</key>\n\t<string>'"$v</string>"* ]] || { UPD_ERR="version mismatch"; return 1 }
  REPLY=$dst
}

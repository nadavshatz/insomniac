#!/bin/zsh -f
# Packaging test: the .alfredworkflow contains everything Alfred needs, keeps
# executable bits, and carries the stamped version.
setopt extended_glob no_unset
ROOT=${0:A:h:h}
integer fail=0
ok()  { print -P "%F{green}✔%f $1" }
bad() { print -P "%F{red}✘ $1%f"; (( ++fail )) }

out=$(zsh $ROOT/scripts/build.sh 9.8.7) || { print -r -- $out; exit 1 }
PKG=$ROOT/dist/Insomniac-9.8.7.alfredworkflow
[[ -f $PKG ]] && ok "package built" || bad "package missing"

X=$(mktemp -d); trap 'rm -rf $X' EXIT
(cd $X && unzip -q $PKG)
for f in info.plist icon.png status_filter.sh toggle_engine.sh lib/common.zsh \
         helper/insomniac-helper.sh helper/io.github.nadavshatz.insomniac.bootguard.plist; do
  [[ -f $X/$f ]] && ok "contains $f" || bad "missing $f"
done
for f in status_filter.sh toggle_engine.sh helper/insomniac-helper.sh; do
  [[ -x $X/$f ]] && ok "$f is executable" || bad "$f not executable"
done
vpat=$'*\n\t<key>version</key>\n\t<string>9.8.7</string>*'
[[ $(<$X/info.plist) == ${~vpat} ]] \
  && ok "version stamped" || bad "version not stamped"
cmp -s $ROOT/workflow/info.plist $X/info.plist && bad "source info.plist was modified?" || ok "staged plist differs from source"
[[ $(<$ROOT/workflow/info.plist) != *9.8.7* ]] && ok "source tree untouched" || bad "source tree modified"
for p in $(cd $X && print -l -- **/*(.)); do
  [[ $p == (tests|scripts|docs)/* ]] && bad "dev file shipped: $p"
done
[[ -f $PKG.sha256 ]] && ok "checksum file written" || bad "checksum file missing"
if [[ -x /usr/bin/shasum ]]; then got=$(/usr/bin/shasum -a 256 $PKG); else got=$(sha256sum $PKG); fi
[[ $(<$PKG.sha256) == "${got%% *}  ${PKG:t}" ]] && ok "checksum matches package" || bad "checksum does not match"
[[ -f $X/lib/update.zsh ]] && ok "GitHub build includes the updater" || bad "GitHub build lacks the updater"
[[ $(<$X/info.plist) == *"<string>update_mode</string>"* ]] && ok "GitHub build has the Updates setting" || bad "Updates setting missing"

zsh $ROOT/scripts/build.sh --gallery 9.8.7 >/dev/null
GPKG=$ROOT/dist/Insomniac-9.8.7-gallery.alfredworkflow
GX=$(mktemp -d)
(cd $GX && unzip -q $GPKG)
[[ ! -e $GX/lib/update.zsh && ! -e $GX/icons/update.png ]] && ok "Gallery build has no updater code" || bad "Gallery build ships the updater"
[[ $(<$GX/info.plist) != *update_mode* && $(<$GX/info.plist) != *"awake update"* ]] && ok "Gallery build has no Updates setting" || bad "Gallery plist mentions updates"
[[ $(<$GX/info.plist) == *"<string>thermal_guard</string>"* && $(<$GX/info.plist) == *"<string>battery_floor</string>"* ]] \
  && ok "Gallery build keeps the other settings" || bad "Gallery build lost settings"
if command -v plutil >/dev/null; then plutil -lint -s $GX/info.plist && ok "Gallery plist lints" || bad "Gallery plist invalid"
else python3 -c "import plistlib,sys;plistlib.load(open(sys.argv[1],'rb'))" $GX/info.plist && ok "Gallery plist parses" || bad "Gallery plist invalid"; fi
grep -rqE 'curl|releases/(latest|download)' $GX && bad "Gallery build still references downloads" || ok "Gallery build never downloads anything"
rm -rf $GX; rm -f $GPKG $GPKG.sha256

zsh $ROOT/scripts/build.sh not-a-version >/dev/null 2>&1 && bad "bad version accepted" || ok "bad version rejected"
rm -f $PKG $PKG.sha256
(( fail == 0 )) && print "\nbuild: all passed"
(( fail == 0 ))

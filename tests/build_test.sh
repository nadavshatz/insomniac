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
zsh $ROOT/scripts/build.sh not-a-version >/dev/null 2>&1 && bad "bad version accepted" || ok "bad version rejected"
rm -f $PKG
(( fail == 0 )) && print "\nbuild: all passed"
(( fail == 0 ))

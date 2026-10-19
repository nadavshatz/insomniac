#!/bin/zsh -f
# Package workflow/ into dist/Insomniac-<version>.alfredworkflow (a zip).
#
#   zsh scripts/build.sh                  # version from workflow/info.plist
#   zsh scripts/build.sh 1.2.0            # stamp this version into the package
#   zsh scripts/build.sh --gallery [ver]  # Alfred Gallery variant: no updater
#
# Also writes <package>.sha256, which the updater verifies before installing.
#
# Files are staged in dist/stage so the source tree is never modified.
# Uses only tools that ship with macOS: zsh and zip.
setopt err_exit extended_glob no_unset
ROOT=${0:A:h:h}
GALLERY=0
[[ ${1:-} == --gallery ]] && { GALLERY=1; shift }
SRC=$ROOT/workflow
STAGE=$ROOT/dist/stage

plist=$(<$SRC/info.plist)
# The workflow's own version is the top-level key (one tab deep); objects
# inside have their own integer "version" keys.
key=$'\n\t<key>version</key>\n\t<string>'
[[ $plist == *$key* ]] || { print -u2 "no top-level version in info.plist"; exit 1 }
rest=${plist#*$key}
VERSION=${1:-${rest%%</string>*}}
[[ $VERSION == <->.<->.<->(-[A-Za-z0-9.]##|) ]] || { print -u2 "invalid version '$VERSION' (want X.Y.Z)"; exit 1 }

rm -rf $STAGE && mkdir -p $STAGE
cp -R $SRC/info.plist $SRC/icon.png $SRC/icons $SRC/lib $SRC/helper $SRC/*.sh $STAGE/
[[ -f $SRC/menubar.js ]] && cp $SRC/menubar.js $STAGE/
plist="${plist%%$key*}$key$VERSION</string>${rest#*</string>}"

SUFFIX=
if (( GALLERY )); then
  # Gallery workflows are updated by Alfred and must not update themselves:
  # drop the updater code, its setting, and its readme line.
  SUFFIX=-gallery
  rm -f $STAGE/lib/update.zsh $STAGE/icons/update.png
  marker='<string>update_mode</string>'
  [[ $plist == *$marker* ]] || { print -u2 "update_mode setting not found"; exit 1 }
  before=${plist%%$marker*} after=${plist#*$marker}
  open_tag=$'\n\t\t<dict>' close_tag=$'\n\t\t</dict>'
  plist="${before%$open_tag*}${after#*$close_tag}"
  line=$'\n'"  awake update          check for / install a new version"
  plist=${plist//$line/}
fi
print -r -- $plist > $STAGE/info.plist

chmod 755 $STAGE/*.sh $STAGE/helper/insomniac-helper.sh
chmod 644 $STAGE/lib/* $STAGE/helper/*.plist $STAGE/info.plist $STAGE/icon.png $STAGE/icons/*
OUT=$ROOT/dist/Insomniac-$VERSION$SUFFIX.alfredworkflow
rm -f $OUT $OUT.sha256
(cd $STAGE && zip -q -r -X $OUT .)
if [[ -x /usr/bin/shasum ]]; then sum=$(/usr/bin/shasum -a 256 $OUT); else sum=$(sha256sum $OUT); fi
print -r -- "${sum%% *}  ${OUT:t}" > $OUT.sha256
print "Built $OUT"

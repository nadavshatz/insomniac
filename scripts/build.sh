#!/bin/zsh -f
# Package workflow/ into dist/Insomniac-<version>.alfredworkflow (a zip).
#
#   zsh scripts/build.sh            # version from workflow/info.plist
#   zsh scripts/build.sh 1.2.0      # stamp this version into the package
#
# Files are staged in dist/stage so the source tree is never modified.
# Uses only tools that ship with macOS: zsh and zip.
setopt err_exit extended_glob no_unset
ROOT=${0:A:h:h}
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
print -r -- "${plist%%$key*}$key$VERSION</string>${rest#*</string>}" > $STAGE/info.plist

chmod 755 $STAGE/*.sh $STAGE/helper/insomniac-helper.sh
chmod 644 $STAGE/lib/* $STAGE/helper/*.plist $STAGE/info.plist $STAGE/icon.png $STAGE/icons/*
OUT=$ROOT/dist/Insomniac-$VERSION.alfredworkflow
rm -f $OUT
(cd $STAGE && zip -q -r -X $OUT .)
print "Built $OUT"

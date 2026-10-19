#!/bin/zsh -f
# Package workflow/ into dist/Insomniac-<version>.alfredworkflow (a zip).
# Uses only tools that ship with macOS: zsh, zip, /usr/libexec/PlistBuddy.
set -e
ROOT=${0:A:h:h}
cd $ROOT/workflow
if [[ -x /usr/libexec/PlistBuddy ]]; then
  VERSION=$(/usr/libexec/PlistBuddy -c 'Print :version' info.plist)
else
  VERSION=$(grep -A1 '<key>version</key>' info.plist | sed -n 's:.*<string>\(.*\)</string>.*:\1:p')
fi
chmod 755 status_filter.sh toggle_engine.sh helper/insomniac-helper.sh
chmod 644 lib/common.zsh helper/*.plist info.plist icon.png icons/*.png
mkdir -p $ROOT/dist
OUT=$ROOT/dist/Insomniac-$VERSION.alfredworkflow
rm -f $OUT
zip -q -r -X $OUT info.plist icon.png icons lib helper status_filter.sh toggle_engine.sh
print "Built $OUT"

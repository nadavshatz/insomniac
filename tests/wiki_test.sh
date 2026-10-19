#!/bin/zsh -f
# Wiki link check: every [text](Page) and [text](Page#anchor) link in
# docs/wiki points at an existing page and heading, using GitHub's anchor rules.
setopt extended_glob no_unset
WIKI=${0:A:h:h}/docs/wiki
integer fail=0 links=0
typeset -A anchors

slug() {  # GitHub heading anchor
  local s=${(L)1}
  s=${s//[^a-z0-9 _-]/}
  print -r -- ${s// /-}
}

for f in $WIKI/*.md; do
  page=${${f:t}%.md}
  local -a a=()
  for line in ${(f)"$(<$f)"}; do
    [[ $line == (#b)\#\##[[:space:]]##(*) ]] && a+=($(slug "$match[1]"))
  done
  anchors[$page]=${(j: :)a}
done

for f in $WIKI/*.md; do
  for target in ${(f)"$(grep -oE '\]\([^)]+\)' $f | sed -E 's/^\]\((.*)\)$/\1/')"}; do
    [[ $target == (http*|mailto:*|/*) ]] && continue
    (( ++links ))
    page=${target%%\#*} anchor=
    [[ $target == *\#* ]] && anchor=${target#*\#}
    [[ -z $page ]] && page=${${f:t}%.md}
    if [[ ! -f $WIKI/$page.md ]]; then
      print -r -- "✘ ${f:t}: link to missing page '$page'"; (( ++fail )); continue
    fi
    if [[ -n $anchor && " ${anchors[$page]} " != *" $anchor "* ]]; then
      print -r -- "✘ ${f:t}: '$page' has no heading '#$anchor'"; (( ++fail ))
    fi
  done
done
[[ -f $WIKI/Home.md ]] || { print "✘ Home.md missing"; (( ++fail )) }
print -r -- "wiki: $links internal links checked, $fail broken"
(( fail == 0 ))

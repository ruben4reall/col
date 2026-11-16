#!/bin/sh
# How many Homebrew packages have a newer version, and the first three of them, as a widget.
command -v brew >/dev/null 2>&1 || exit 0
# Only what Homebrew already knows: no update of its own index, which would take longer than an extension may run.
list=$(HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 brew outdated --quiet 2>/dev/null) || exit 0
count=$(printf '%s\n' "$list" | grep -c .)
if [ "$count" -eq 0 ]; then
  printf '{"widget":{"title":"Homebrew","value":"Up to date","symbol":"mug.fill","tint":"green","staleAfter":10800}}'
  exit 0
fi
lines=$(printf '%s\n' "$list" | head -3 | sed 's/.*/"&"/' | paste -sd, -)
printf '{"widget":{"title":"Homebrew","value":%d,"unit":"outdated","symbol":"mug.fill","tint":"orange","lines":[%s],"staleAfter":10800}}' "$count" "$lines"

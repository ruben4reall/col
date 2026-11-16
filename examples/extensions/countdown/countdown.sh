#!/bin/sh
# Days left until a date, as a widget. Edit the two lines below.
TITLE="${COUNTDOWN_TITLE:-New Year}"
DAY="${COUNTDOWN_DATE:-2027-01-01}"

target=$(date -j -f "%Y-%m-%d %H:%M:%S" "$DAY 00:00:00" +%s 2>/dev/null) || exit 0
now=$(date +%s)
left=$(( (target - now + 86399) / 86400 ))
if [ "$left" -lt 0 ]; then
  exit 0
elif [ "$left" -eq 0 ]; then
  printf '{"widget":{"title":"%s","value":"Today","symbol":"party.popper.fill","tint":"pink","lines":["%s"]}}' "$TITLE" "$DAY"
elif [ "$left" -eq 1 ]; then
  printf '{"widget":{"title":"%s","value":1,"unit":"day","symbol":"calendar","tint":"red","lines":["%s"]}}' "$TITLE" "$DAY"
else
  printf '{"widget":{"title":"%s","value":%d,"unit":"days","symbol":"calendar","tint":"red","lines":["%s"]}}' "$TITLE" "$left" "$DAY"
fi

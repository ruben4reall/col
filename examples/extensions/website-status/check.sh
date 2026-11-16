#!/bin/sh
# Whether a website answers, and how fast, as a widget; when it stops answering, an alert in the closed island too.
# Edit the address below.
URL="${WEBSITE_URL:-https://example.com}"

host=$(printf '%s' "$URL" | sed -E 's#^[a-z]+://##; s#/.*##')
result=$(curl --silent --output /dev/null --max-time 8 --write-out '%{http_code} %{time_total}' "$URL" 2>/dev/null)
code=${result%% *}
seconds=${result##* }
if [ -n "$code" ] && [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; then
  milliseconds=$(printf '%s' "$seconds" | awk '{ printf "%d", $1 * 1000 }')
  printf '{"widget":{"title":"%s","value":%d,"unit":"ms","symbol":"checkmark.circle.fill","tint":"green","lines":["HTTP %s"],"staleAfter":180}}' \
    "$host" "$milliseconds" "$code"
else
  [ "$code" = "000" ] || [ -z "$code" ] && reason="No answer" || reason="HTTP $code"
  printf '{"title":"%s","symbol":"exclamationmark.triangle.fill","tint":"red","text":"Down","priority":"alert","ttl":120,' "$host"
  printf '"widget":{"title":"%s","value":"Down","symbol":"exclamationmark.triangle.fill","tint":"red","lines":["%s"],"staleAfter":180}}' \
    "$host" "$reason"
fi

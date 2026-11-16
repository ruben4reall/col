#!/bin/sh
# The Docker containers running, and the first three by name, as a widget. Nothing while Docker is not running.
command -v docker >/dev/null 2>&1 || exit 0
names=$(docker ps --format '{{.Names}}' 2>/dev/null) || exit 0
count=$(printf '%s\n' "$names" | grep -c .)
lines=$(printf '%s\n' "$names" | grep . | head -3 | sed 's/.*/"&"/' | paste -sd, -)
printf '{"widget":{"title":"Docker","value":%d,"unit":"running","symbol":"shippingbox.fill","tint":"blue","lines":[%s],"staleAfter":300}}' "$count" "$lines"

#!/bin/sh
# Undo: remove every mount of the Home stand-in (restores the stock Home).
n=0
for m in $(awk '$2 ~ /com\.webos\.app\.home$/ {print $2}' /proc/mounts | sort -r); do umount -l "$m" 2>/dev/null && n=$((n+1)); done
echo "unmounted $n; /usr/bin/com.webos.app.home is now: $(head -c 4 /usr/bin/com.webos.app.home | od -c | head -1)"

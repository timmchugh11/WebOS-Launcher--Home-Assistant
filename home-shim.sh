#!/bin/sh
# Stand-in for /usr/bin/com.webos.app.home (bind-mounted over it).
# The app manager "launches Home"; we open our launcher instead.
# Fallbacks: if our launcher can't be launched, or Home is launched more than 6 times in 10 seconds,
# unmount every copy of ourselves and run the real Home.
LOG=/tmp/home-shim.log
NOW=$(date +%s)
revert() {
  echo "$NOW REVERT: $1" >> $LOG
  for m in $(awk '$2 ~ /com\.webos\.app\.home$/ {print $2}' /proc/mounts | sort -r); do umount -l "$m"; done
  exec /usr/bin/com.webos.app.home "$@"
}
echo "$NOW launched" >> $LOG
echo $NOW >> /tmp/home-shim.times
N=$(awk -v n=$NOW '$1>=n-10' /tmp/home-shim.times | wc -l)
[ "$N" -gt 6 ] && revert "tripwire"
[ -f /var/lib/ha-launcher/home-shim.disabled ] && revert "disabled flag"
R=$(luna-send -n 1 luna://com.webos.applicationManager/launch '{"id":"com.ha-launcher.home"}' 2>&1)
case "$R" in *'"returnValue": true'*|*'"returnValue":true'*) ;; *) revert "launcher launch failed: $R" ;; esac
sleep 5
exit 0

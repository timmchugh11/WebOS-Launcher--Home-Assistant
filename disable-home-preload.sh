#!/bin/sh
# Run ON the TV:  ssh root@<tv-ip> 'sh -s' < disable-home-preload.sh
#
# Stops LG's preload manager from relaunching LG's Home in the background. Without this, the Home stand-in
# (home-shim.sh) is run every ~12-20 seconds for the first ~4 minutes after boot and drags the launcher to the front
# of whatever app you just opened.
#
# It sets "com.webos.app.home": false in the preload manager's own persistent config,
# /var/preferences/webos-preload-manager-conf.json (the other apps keep their fast-start preloading), then restarts
# only that service. The change survives reboots.
#
# Undo:  cp /var/lib/ha-launcher/webos-preload-manager-conf.json.orig /var/preferences/webos-preload-manager-conf.json
#        systemctl restart preload-manager.service
set -e
F=/var/preferences/webos-preload-manager-conf.json
D=/var/lib/ha-launcher
mkdir -p $D
# If the TV has no saved copy yet, start from LG's default one (this case is untested - it already existed on our TV).
[ -f $F ] || cp /etc/palm/webos-preload-manager-conf.json $F
[ -f $D/webos-preload-manager-conf.json.orig ] || cp -p $F $D/webos-preload-manager-conf.json.orig
node -e '
const fs = require("fs"), f = "/var/preferences/webos-preload-manager-conf.json", t = f + ".tmp";
const j = JSON.parse(fs.readFileSync(f, "utf8"));
j.allowedApps = j.allowedApps || {};
j.allowedApps["com.webos.app.home"] = false;
fs.writeFileSync(t, JSON.stringify(j));
JSON.parse(fs.readFileSync(t, "utf8"));      // validate before putting it in place
fs.renameSync(t, f);
console.log("com.webos.app.home preloading is now", JSON.parse(fs.readFileSync(f, "utf8")).allowedApps["com.webos.app.home"]);
'
sync
systemctl restart preload-manager.service
echo "preload-manager restarted ($(systemctl is-active preload-manager.service)). Check after a reboot: /tmp/home-shim.log should only list your own Home presses."

#!/bin/sh
# Run ON the TV (ssh root@<tv-ip> 'sh -s' < bootd-override.sh).
# Makes the TV open the launcher (com.ha-launcher.home) as its first app at power-on by the remote,
# the TV's own button, or the up/down key. It writes /var/luna/preferences/bootd.json, a full copy of
# LG's /etc/palm/bootd.json with only those three "first app" entries changed. bootd reads that file
# instead of its own when it exists.
#
# Undo:  rm /var/luna/preferences/bootd.json /var/lib/ha-launcher/bootd-override.installed ; reboot
# The 00-home-launcher boot hook removes the override by itself if the launcher app is missing/disabled.
# REMOVE THE OVERRIDE BEFORE A FIRMWARE UPDATE.
set -e
APP=com.ha-launcher.home
D=/var/lib/ha-launcher
mkdir -p $D
if [ -f /var/luna/preferences/bootd.json ]; then
  echo "An override already exists - refusing to overwrite it:"; head -c 300 /var/luna/preferences/bootd.json; exit 1
fi
cp /etc/palm/bootd.json $D/bootd.json.orig
node -e '
const fs = require("fs");
const src = "/etc/palm/bootd.json", dst = "/var/luna/preferences/bootd.json", tmp = dst + ".tmp", app = process.argv[1];
const cfg = JSON.parse(fs.readFileSync(src, "utf8"));
for (const k of ["remoteKey", "localKey", "upDownKey", "micomPower"]) cfg.common.firstAppByPowerOnReason[k] = app;
fs.writeFileSync(tmp, JSON.stringify(cfg, null, 4));
JSON.parse(fs.readFileSync(tmp, "utf8"));   // validate what was written before putting it in place
fs.renameSync(tmp, dst);
console.log("first app at power-on is now", app);
' $APP
touch $D/bootd-override.installed
sync
echo "Done. Reboot the TV with its power button / remote to try it."

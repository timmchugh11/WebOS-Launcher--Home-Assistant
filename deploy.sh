#!/bin/bash
# Usage: TV=root@<tv-ip> ./deploy.sh [qml-dir]
# Builds an ipk of the QML launcher locally and installs it on the TV (as com.ha-launcher.home).
# It does NOT start it. The Home Assistant settings are generated ON THE TV from /var/lib/ha-launcher/ha.js (the same file the
# HTML launcher uses), so the token never lives in this folder.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
TV="${TV:-}"
[ -n "$TV" ] || { echo "Set TV first, e.g.:  TV=root@192.168.1.50 ./deploy.sh" >&2; exit 1; }
SRC="${1:-$HERE/qml}"; ID=$(sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' "$SRC/appinfo.json" | head -1)
VER=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$SRC/appinfo.json" | head -1)
B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
mkdir -p "$B/data/usr/palm/applications/$ID" "$B/data/usr/palm/packages/$ID" "$B/control"
cp -r "$SRC"/. "$B/data/usr/palm/applications/$ID/"
printf '{\n  "id": "%s",\n  "version": "%s",\n  "app": "%s"\n}\n' "$ID" "$VER" "$ID" > "$B/data/usr/palm/packages/$ID/packageinfo.json"
printf 'Package: %s\nVersion: %s\nSection: misc\nPriority: optional\nArchitecture: all\nInstalled-Size: 1\nMaintainer: ha-launcher <noreply@localhost>\nDescription: %s\nSource: {"Source":"%s","Feed":""}\n' "$ID" "$VER" "$ID" "$ID" > "$B/control/control"
echo 2.0 > "$B/debian-binary"
(cd "$B/control" && tar czf ../control.tar.gz --owner=0 --group=0 .)
(cd "$B/data" && tar czf ../data.tar.gz --owner=0 --group=0 .)
(cd "$B" && node "$HERE/mkar.js" "$ID.ipk" debian-binary control.tar.gz data.tar.gz)
scp -q -o BatchMode=yes "$B/$ID.ipk" $TV:/tmp/$ID.ipk
ssh -o BatchMode=yes $TV "sh -s" <<REMOTE
cat > /tmp/inst-qml.sh <<'X'
luna-send -i -f luna://com.webos.appInstallService/dev/install '{"id":"$ID","ipkUrl":"/tmp/$ID.ipk","subscribe":true}' </dev/null >/dev/null 2>&1 &
P=\$!; sleep 15; kill \$P 2>/dev/null
X
sh /tmp/inst-qml.sh; rm -f /tmp/inst-qml.sh /tmp/$ID.ipk
A=/media/developer/apps/usr/palm/applications/$ID
VERSION=$VER
[ -d \$A ] || { echo "install failed: \$A missing" >&2; exit 1; }
# Home Assistant settings, generated from the TV's own ha.js
if [ -f /var/lib/ha-launcher/ha.js ]; then
node -e '
global.window={}; eval(require("fs").readFileSync("/var/lib/ha-launcher/ha.js","utf8"));
const h=window.HA||{}; const q=JSON.stringify;
require("fs").writeFileSync(process.argv[1]+"/cfg.js", ".pragma library\nvar url="+q((h.url||"").replace(/^ws/,"http").replace(/\/api\/websocket\$/,""))+";\nvar token="+q(h.token||"")+";\nvar sensor="+q(h.sensor||h.battery||"")+";\nvar label="+q(h.label||"")+";\nvar preset="+q(h.preset||"")+";\nvar presetLabel="+q(h.presetLabel||"")+";\n");
' \$A
fi
# permission to ask the app manager for the app list / running apps / launch / close (installs only grant 'public')
echo '{"$ID-*":["public","applications.internal"],"$ID":["public","applications.internal"]}' > /var/luna-service2-dev/client-permissions.d/$ID.app.json
# a QML app also needs a luna role (the installer only writes one for web apps), and the manifest must point at it - without
# this every service call from the app silently gets no answer. The installer rewrites the manifest, so this is redone each time.
cat > /var/luna-service2-dev/roles.d/$ID.app.json <<R
{
	"appId": "$ID",
	"type": "regular",
	"allowedNames": ["$ID-*"],
	"trustLevel": "",
	"permissions": [ { "service": "$ID-*", "outbound": ["*"] } ]
}
R
echo '{"version":"'\$VERSION'","id":"$ID","roleFiles":["/var/luna-service2-dev/roles.d/$ID.app.json"],"clientPermissionFiles":["/var/luna-service2-dev/client-permissions.d/$ID.app.json"]}' > /var/luna-service2-dev/manifests.d/$ID.json
ls-control scan-services >/dev/null 2>&1
echo "installed \$(grep '"version"' \$A/appinfo.json | tr -d ' ,')  (not started)"
REMOTE

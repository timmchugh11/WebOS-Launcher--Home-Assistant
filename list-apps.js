// Run ON the TV: scp list-apps.js root@<tv-ip>:/tmp/ && ssh root@<tv-ip> node /tmp/list-apps.js
// Prints every installed app (id, title, icon path, root folder) as JSON so you can pick which ones go in
// the launcher (see README, "Choose your apps"). "visible:false" apps (Live TV, HDMI inputs, Settings) still
// launch fine by id - they are just hidden from LG's own launcher.
const fs = require('fs'), p = require('path');
const roots = ['/media/cryptofs/apps/usr/palm/applications', '/media/developer/apps/usr/palm/applications',
               '/usr/palm/applications', '/media/system/apps/usr/palm/applications'];
const out = [];
for (const r of roots) {
  let ds = [];
  try { ds = fs.readdirSync(r); } catch (e) { continue; }
  for (const d of ds) {
    try {
      const a = JSON.parse(fs.readFileSync(p.join(r, d, 'appinfo.json'), 'utf8'));
      out.push({ id: a.id, title: a.title, visible: a.visible !== false, icon: a.largeIcon || a.icon, dir: p.join(r, d) });
    } catch (e) { /* not an app folder */ }
  }
}
console.log(JSON.stringify(out, null, 1));

// Watches the TV remote's Linux input devices (read-only; keys still work normally).
// usage: node keywatch.js [--log-only]
// Press of the mapped key runs the mapped command. Config in /var/lib/ha-launcher/keys.json: {"398": "luna-send ..."}
const fs = require('fs'), cp = require('child_process');
const LOG_ONLY = process.argv.includes('--log-only');
const DEVICES = fs.readdirSync('/dev/input').filter(n => /^event[0-9]+$/.test(n)).map(n => '/dev/input/' + n); // all input devices
let map = {};
function loadMap() { try { map = JSON.parse(fs.readFileSync('/var/lib/ha-launcher/keys.json', 'utf8')); } catch (e) { map = {}; } }
loadMap(); fs.watchFile('/var/lib/ha-launcher/keys.json', { interval: 2000 }, loadMap);
const last = {};
function open(dev) {
  console.log('watching', dev);
  const s = fs.createReadStream(dev, { highWaterMark: 16 });
  let buf = Buffer.alloc(0);
  s.on('data', d => {
    if (process.env.RAW) console.log('raw', dev, d.length, d.toString('hex'));
    buf = Buffer.concat([buf, d]);
    while (buf.length >= 16) {
      const type = buf.readUInt16LE(8), code = buf.readUInt16LE(10), value = buf.readInt32LE(12);
      buf = buf.slice(16);
      if (type !== 1 || value !== 1) continue;           // key press only
      console.log(new Date().toISOString(), dev, 'key', code);
      if (LOG_ONLY || !map[code]) continue;
      const now = Date.now(); if (now - (last[code] || 0) < 700) continue; last[code] = now;
      cp.exec(map[code], () => {});
    }
  });
  s.on('error', e => { console.log('error', dev, e.code); setTimeout(() => open(dev), 5000); });
  s.on('end', () => setTimeout(() => open(dev), 2000));
}
DEVICES.forEach(open);

// usage: node mkar.js out.ipk file1 file2 ...   (creates a GNU-style ar archive)
const fs=require('fs'),path=require('path');
const [out,...files]=process.argv.slice(2);
const parts=[Buffer.from('!<arch>\n')];
for(const f of files){
  const d=fs.readFileSync(f), name=(path.basename(f)+'/').padEnd(16);
  const hdr=name+'0'.padEnd(12)+'0'.padEnd(6)+'0'.padEnd(6)+'100644'.padEnd(8)+String(d.length).padEnd(10)+'`\n';
  parts.push(Buffer.from(hdr,'latin1'),d); if(d.length%2) parts.push(Buffer.from('\n'));
}
fs.writeFileSync(out,Buffer.concat(parts));

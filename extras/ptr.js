// usage: node ptr.js "move 40 0" "wait 300" "click" ...   (sends Magic Remote pointer events via the TV's input socket)
const net=require('net'); const cmds=process.argv.slice(2);
const c=net.connect('/tmp/netinput.pointer.sock',async()=>{
  const sleep=ms=>new Promise(r=>setTimeout(r,ms));
  for(const cmd of cmds){ const [t,a,b]=cmd.split(' ');
    if(t==='wait') await sleep(+a);
    else if(t==='move') c.write('type:move\ndx:'+a+'\ndy:'+b+'\ndown:0\n\n');
    else if(t==='click') c.write('type:click\n\n');
    else if(t==='button') c.write('type:button\nname:'+a+'\n\n');
    await sleep(60);
  }
  await sleep(300); c.end(); process.exit(0);
});
c.on('error',e=>{console.log('sock error',e.message);process.exit(1)});

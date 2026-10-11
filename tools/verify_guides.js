const fs=require('fs'),vm=require('vm'),path=require('path');
const root=path.resolve('Encounter-Guides-v1.2.14');
for(const name of fs.readdirSync(root).filter(n=>n.endsWith('.html'))){
 const html=fs.readFileSync(path.join(root,name),'utf8');
 if(html.includes('@@')) throw Error('Unreplaced template '+name);
 for(const match of html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)){
  if(match[1].includes('application/json')){
   const data=JSON.parse(match[2]);
   if(name.startsWith('Hoennto'))for(const edition of ['firered','leafgreen']){
    const all=new Set(data.rows.filter(r=>r.edition===edition&&(r.mask&65536)).map(r=>r.id));
    if(all.size!==1025)throw Error('Incomplete Hoennto coverage');
   }
   if(name.startsWith('FR-LG')&&!data.rows.some(r=>r.id===39&&r.map==='FR_ROUTE_3'&&r.canon))throw Error('Jigglypuff missing');
   if(name.startsWith('Ruby')&&!data.rows.some(r=>r.id===349&&r.canon))throw Error('Ruby Feebas missing');
   console.log('PASS',name,data.rows.length,'validated encounter rows');
  }else new vm.Script(match[2],{filename:name});
 }
}
console.log('PASS all five guides: embedded JavaScript syntax and no unresolved templates');

// Controlled companion to source-followup-device-fixture.cjs. No external sites.
const http = require('node:http');
const fs = require('node:fs');
const zlib = require('node:zlib');

function createSources(root = 'http://127.0.0.1:18391') {
  const common = {sourceFormat:'native', version:1, group:'Codex临时验收', enabled:false, enabledExplore:false};
  const media = {...common, name:'Codex媒体跨域验收', url:root+'/media', type:'comic',
    search:{url:root+'/media/search', list:'$[*]', fields:{name:'$.name', bookUrl:'$.bookUrl'}},
    detail:{url:root+'/media/book', fields:{name:'$.name', tocUrl:'$.tocUrl'}},
    toc:{url:root+'/media/toc', list:'$[*]', fields:{title:'$.title', url:'$.url'}},
    content:{images:'$.images[*]', mediaHeaders:{'X-Media-Token':'probe-media-value'}}};
  const performance = {...common, name:'Codex大目录验收', url:root+'/perf',
    vars:[{key:'chapters', label:'目录章节数', options:[600,1000,3000], default:600}],
    js:`function search(ctx) {return [{name:'目录性能验收 '+ctx.vars.chapters+'章',bookUrl:'${root}/perf/book'}];}
function detail(ctx) {return {name:'目录性能验收 '+ctx.vars.chapters+'章',tocUrl:'${root}/perf/toc'};}
function toc(ctx) {
  var n=Number(ctx.vars.chapters), begin=Date.now();
  var response=http.get('${root}/perf/toc?count='+n);
  if(!response.ok) throw new Error('目录响应失败 '+response.status);
  var loaded=Date.now(), data=response.json(), parsed=Date.now();
  var result=data.map(function(c){return {title:c.name,url:c.url};});
  if(result.length!==n)throw new Error('章节数不匹配 '+result.length+'/'+n);
  log('目录样本 count='+n+'; fetchWallMs='+(loaded-begin)+'; parseWallMs='+(parsed-loaded)+'; mapWallMs='+(Date.now()-parsed));
  return result;
}`,
    search:{script:'search'}, detail:{script:'detail'}, toc:{script:'toc'},
    content:{text:'$.text'}};
  return [media,performance];
}

// Build two valid PNG panels so both successful downloads are visible in the reader.
function makePanel(rgb) {
  const width=600, height=400;
  const pixels=Buffer.alloc((width*3+1)*height);
  for(let y=0;y<height;y++)for(let x=0;x<width;x++) {
    const i=y*(width*3+1)+1+x*3;
    const color=(y<24 || y>=height-24 || x<24 || x>=width-24)?[255,255,255]:rgb;
    pixels[i]=color[0]; pixels[i+1]=color[1]; pixels[i+2]=color[2];
  }
  function chunk(type,data) {
    const kind=Buffer.from(type), bytes=Buffer.concat([kind,data]);
    let crc=0xffffffff;
    for(const value of bytes){crc^=value;for(let j=0;j<8;j++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}
    const len=Buffer.alloc(4),sum=Buffer.alloc(4);len.writeUInt32BE(data.length);sum.writeUInt32BE((crc^0xffffffff)>>>0);
    return Buffer.concat([len,bytes,sum]);
  }
  const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(width,0);ihdr.writeUInt32BE(height,4);ihdr[8]=8;ihdr[9]=2;
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),chunk('IDAT',zlib.deflateSync(pixels)),chunk('IEND',Buffer.alloc(0))]);
}

function createHandler(root, crossRoot, destination, record) {
  const sources=createSources(root), blue=makePanel([32,120,220]), green=makePanel([35,175,100]);
  return (req,res)=>{
    const url=new URL(req.url,root), path=url.pathname;
    const mediaToken=req.headers['x-media-token'];
    record({time:new Date().toISOString(), destination, method:req.method, path:req.url,
      hostCheck:req.headers['x-fixture-check']==='host',
      mediaTokenPresent:mediaToken!==undefined, mediaTokenMatches:mediaToken==='probe-media-value'});
    res.setHeader('Cache-Control','no-store');
    res.setHeader('Content-Type','application/json; charset=utf-8');
    const json=value=>res.end(JSON.stringify(value));
    if(destination==='cross' && path!=='/media/image'){res.statusCode=404;return json({error:'Unknown destination'});}
    if(path==='/sources.json')return json(sources);
    if(path==='/media/source.json')return json(sources[0]);
    if(path==='/perf/source.json')return json(sources[1]);
    if(path==='/media/search')return json([{name:'媒体跨域验收（蓝色同域、绿色跨域）',bookUrl:root+'/media/book'}]);
    if(path==='/media/book')return json({name:'媒体跨域验收（蓝色同域、绿色跨域）',tocUrl:root+'/media/toc'});
    if(path==='/media/toc')return json([{title:'同域保留头、跨域移除头',url:root+'/media/chapter'}]);
    if(path==='/media/chapter'){
      const run=Date.now();
      return json({images:[root+'/media/redirect?case=same&run='+run,root+'/media/redirect?case=cross&run='+run]});
    }
    if(path==='/media/redirect' || path==='/media/image'){
      const expected=destination==='cross'?mediaToken===undefined:mediaToken==='probe-media-value';
      if(!expected){res.statusCode=403;return json({error:destination==='cross'?'Custom header leaked across origin':'Required custom header missing'});}
      if(path==='/media/redirect'){
        res.statusCode=302;
        res.setHeader('Location',(url.searchParams.get('case')==='cross'?crossRoot:root)+'/media/image'+url.search);
        return res.end();
      }
      res.setHeader('Content-Type','image/png');return res.end(destination==='cross'?green:blue);
    }
    if(path==='/perf/toc'){
      const count=Number(url.searchParams.get('count'));
      if(![600,1000,3000].includes(count)){res.statusCode=400;return json({error:'count must be 600, 1000 or 3000'});}
      return json(Array.from({length:count},(_,i)=>({id:i+1,name:'第 '+(i+1)+' 章：目录性能样本',url:root+'/perf/chapter/'+(i+1)})));
    }
    if(path.startsWith('/perf/chapter/'))return json({text:'本章为受控目录验收样本，没有第三方内容。'});
    res.statusCode=404;json({error:'Unknown fixture route'});
  };
}

if(require.main===module){
  fs.mkdirSync('.codex_tmp',{recursive:true});
  const root='http://127.0.0.1:18391',crossRoot='http://127.0.0.1:18392';
  const record=row=>fs.appendFileSync('.codex_tmp/source-media-performance-requests.jsonl',JSON.stringify(row)+'\n');
  for(const [port,destination] of [[18391,'origin'],[18392,'cross']]){
    http.createServer(createHandler(root,crossRoot,destination,record)).listen(port,'127.0.0.1',()=>console.log('Controlled '+destination+' fixture listening on '+port));
  }
}
module.exports={createSources,createHandler};

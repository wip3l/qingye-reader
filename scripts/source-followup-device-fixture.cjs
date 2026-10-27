// Developer-controlled device fixture. No third-party content or credentials.
// Usage: node scripts/source-followup-device-fixture.cjs [device-visible base URL]
const http=require('http'),fs=require('fs');
fs.mkdirSync('.codex_tmp',{recursive:true});
const root=process.argv[2]||'http://127.0.0.1:18390';let retry=0;
const script=`function search(ctx) {
  var r=http.get('/echo',{headers:{'X-Probe-Header':'probe-value'}});
  var e=r.json();
  if(e.headers['x-probe-header']!=='probe-value'||!e.headers['user-agent']) throw new Error('request headers missing');
  if(!r.headersAvailable||r.headers['x-probe-response']!=='visible') throw new Error('response headers missing');
  http.get('/reset');
  r=http.get('/retry',{timeout:5000,retry:{times:2,onStatus:[503],base:80,maxDelay:500}});
  if(!r.ok||r.json().attempt!==2) throw new Error('retry failed');
  var strict=false;
  try {http.all(['/echo','/fail','/echo'],{failOnPartial:true});} catch(err){strict=/成功 2，失败 1/.test(String(err));}
  if(!strict) throw new Error('strict batch failed');
  var rendered=browser.render('/render',{waitFor:'#ready',timeout:10,js:'document.querySelector("#ready").textContent'});
  if(rendered!=='render-ok') throw new Error('render failed: '+rendered);
  var web=http.get('/render',{webView:true});
  if(!web.ok||web.headersAvailable) throw new Error('web header availability wrong');
  var timings=[];
  [600,1000,3000].forEach(function(n){
    var raw=JSON.stringify(Array.from({length:n},function(_,i){return {id:i,title:'章节 '+i,url:'/chapter/'+i};}));
    var samples=[];
    for(var round=0;round<6;round++) { var started=Date.now(); var rows=JSON.parse(raw).map(function(c){return {title:c.title,url:c.url};});
      if(rows.length!==n)throw new Error('parse count'); samples.push(Date.now()-started); }
    timings.push(n+':'+samples.join('/'));
  });
  var report='PASS headers/retry/strict/WebView; JSON目录毫秒 '+timings.join(';');
  log(report);
  http.post('/report',{report:report});
  return [{name:report,bookUrl:'/book'}];
}`;
const source={sourceFormat:'native',version:1,name:'Codex网络验收临时源',url:root,group:'Codex临时验收',enabled:false,enabledExplore:false,
 js:script,search:{script:'search'},detail:{url:'data:application/json,%7B%7D',fields:{name:'测试书'}},toc:{url:'data:application/json,%5B%5D',list:'$[*]',fields:{title:'$.title',url:'$.url'}},content:{url:'data:text/plain,test',text:'= body'}};
const log=x=>fs.appendFileSync('.codex_tmp/source-device-requests.jsonl',JSON.stringify({time:new Date().toISOString(),...x})+'\n');
http.createServer((req,res)=>{let body='';req.on('data',c=>body+=c);req.on('end',()=>{
  log({method:req.method,url:req.url,probeHeader:req.headers['x-probe-header']||'',uaPresent:!!req.headers['user-agent'],
    report:req.url==='/report'?body:undefined});
  res.setHeader('Content-Type','application/json');res.setHeader('X-Probe-Response','visible');
  if(req.url==='/source.json')return res.end(JSON.stringify(source));
  if(req.url==='/reset'){retry=0;return res.end('{}');}
  if(req.url==='/retry'){retry++;res.statusCode=retry===1?503:200;return res.end(JSON.stringify({attempt:retry}));}
  if(req.url==='/fail'){res.statusCode=403;return res.end('denied');}
  if(req.url==='/render'){res.setHeader('Content-Type','text/html');return res.end('<html><body><div id="ready">render-ok</div></body></html>');}
  return res.end(JSON.stringify({headers:req.headers,body}));
})}).listen(18390,'127.0.0.1',()=>console.log('Controlled fixture listening on 18390'));

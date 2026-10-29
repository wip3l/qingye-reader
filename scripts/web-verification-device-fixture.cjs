// Local HTTP fixture for WebView lifecycle/UA. Cookie partition API probe runs in entry_test;
// this HTTP server does not claim to test trusted HTTPS or Cloudflare challenges.
const http = require('node:http');
const fs = require('node:fs');
const root = 'http://127.0.0.1:18393';
const userAgent = 'Legado-WebVerification-Fixture';
const source = {
  sourceFormat: 'native', version: 1, name: 'Codex网页验证验收', url: root,
  group: 'Codex临时验收', enabled: false, enabledExplore: false,
  headers: { 'User-Agent': userAgent },
  login: { url: root + '/page' },
  actions: [{ label: '网页抓取诊断', script: 'diag' }, { label: '验证后继续抓取', script: 'verifyThenRender' }],
  js: `function diag() {
    var r=http.get('/page',{webView:{waitFor:'#ready',timeout:8},timeout:10000});
    if(!r.ok || r.statusCodeAvailable || r.body.indexOf('fixture-ready')<0) throw new Error('web response: '+r.error);
    var text=browser.render('/page',{waitFor:'#ready',timeout:8,js:'document.querySelector("#ready").textContent'});
    if(text!=='fixture-ready') throw new Error('render mismatch');
    http.post('/report',{passed:true,stage:'settings'});
    return 'PASS 网页抓取与渲染';
  }
  function verifyThenRender(){ browser.verify('/page','点完成后继续'); return diag(); }
  function search(ctx){diag();return [{name:'网页验证验收',bookUrl:'/book'}];}
  function challenge(ctx){browser.verify('/page','请完成网页操作');return [];}`,
  search: { script: 'search' },
  explore: { menus: [{ title: '验证入口', url: '/page' }], script: 'challenge' },
  detail: { url: 'data:application/json,%7B%7D', fields: { name: '网页验证验收' } },
  toc: { url: 'data:application/json,%5B%7B%22title%22%3A%22验收%22%2C%22url%22%3A%22%2Fchapter%22%7D%5D', list: '$[*]', fields: { title: '$.title', url: '$.url' } },
  content: { url: 'data:text/plain,fixture', text: '= body' }
};
module.exports = { source };
if (require.main === module) {
  fs.mkdirSync('.codex_tmp', { recursive: true });
  http.createServer((req, res) => {
    const uaMatches = req.headers['user-agent'] === userAgent;
    fs.appendFileSync('.codex_tmp/web-verification-device.jsonl', JSON.stringify({ time: new Date().toISOString(), method: req.method, path: req.url, uaMatches }) + '\n');
    if (req.url === '/source.json') { res.setHeader('Content-Type', 'application/json'); return res.end(JSON.stringify(source)); }
    if (req.url === '/slow') { const timer = setTimeout(() => res.end('slow'), 15000); res.on('close', () => clearTimeout(timer)); return; }
    if (req.url === '/report') { res.end('{}'); return; }
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    if (req.url === '/interactive') {
      // DOM is usable but a slow image keeps readyState below complete. Changing text also
      // prevents whole-page signature stability. No challenge solving or external traffic.
      return res.end('<!doctype html><html><body><h1 id="ready">' + (uaMatches ? 'fixture-ready' : 'UA mismatch') +
        '</h1><img src="/slow"><p id="changing"></p><script>setInterval(function(){document.getElementById("changing").textContent=String(Date.now())},30)</script></body></html>');
    }
    res.end('<!doctype html><html><body><h1 id="ready">' + (uaMatches ? 'fixture-ready' : 'UA mismatch') + '</h1></body></html>');
  }).listen(18393, '127.0.0.1', () => console.log('Web verification fixture listening on 18393'));
}

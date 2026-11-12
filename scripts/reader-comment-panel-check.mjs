// Run with: node --experimental-strip-types scripts/reader-comment-panel-check.mjs
// Exercise the actual reader methods with controlled Web callbacks and timers.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { ReaderCommentWebTheme } from '../entry/src/main/ets/core/reader/ReaderCommentWebTheme.ts';
import { NativeCommentPage } from '../harmony-book-source-engine/sourceengine/src/main/ets/core/nativesource/NativeCommentPage.ts';
import { NativeCommentDocumentPolicy } from '../entry/src/main/ets/core/book/NativeCommentDocumentPolicy.ts';

const source = fs.readFileSync(new URL('../entry/src/main/ets/pages/ReadBook.ets', import.meta.url), 'utf8');
function method(name) {
  const start = new RegExp(`^  (?:private )?(?:async )?${name}\\(`, 'm').exec(source)?.index;
  assert.notEqual(start, undefined, name);
  return source.slice(start, source.indexOf('\n  }', start) + 4).replace(/^  private /,'  ');
}
function harness() {
  let id = 0;
  const timers = new Map();
  const context = vm.createContext({
    ReaderCommentWebTheme, console: { warn() {} },
    setTimeout: fn => { timers.set(++id, fn); return id; },
    clearTimeout: key => timers.delete(key)
  });
  const methods = ['updateReaderCommentPanelHeight', 'scheduleReaderCommentPanelHostReady',
    'backReaderCommentPanel', 'closeReaderCommentPanel', 'failReaderCommentPanelLoad', 'retryReaderCommentPanelLoad',
    'readerInlinePageNeedsRefresh',
    'syncReaderCommentPanelWebTheme', 'loadReaderCommentPanelHtmlIfNeeded'];
  const page = vm.runInContext(stripTypeScriptTypes(`({${methods.map(method).join(',')}})`, { mode: 'strip' }), context);
  Object.assign(page, {
    showReaderCommentPanel: true, readerCommentPanelHeight: 0, readerCommentPanelLoadSerial: 1,
    readerCommentPanelReadyTimerId: -1, readerCommentPanelLoading: true, readerCommentPanelError: false,
    readerCommentPanelUrl: 'https://comments.example/', readerCommentPanelHtml: '',
    appDarkMode: true,
    readerCommentPanelController: { runJavaScript: async () => '0' }
  });
  return { page, timers, async tick() {
    const [key, fn] = timers.entries().next().value || [];
    assert(fn, 'scheduled readiness check exists');
    timers.delete(key); fn();
    // Drain runJavaScript, theme status and host visibility continuations.
    for (let i = 0; i < 5; i++) await Promise.resolve();
  } };
}

{
  const { page } = harness();
  page.updateReaderCommentPanelHeight(300);
  assert.equal(page.readerCommentPanelHeight, 300);
  page.updateReaderCommentPanelHeight(600);
  assert.equal(page.readerCommentPanelHeight, 600, 'expanded content uses expanded viewport');
  page.updateReaderCommentPanelHeight(400);
  assert.equal(page.readerCommentPanelHeight, 400, 'collapse updates viewport too');
  for (const invalid of [0, -1, NaN, Infinity]) page.updateReaderCommentPanelHeight(invalid);
  assert.equal(page.readerCommentPanelHeight, 400);
  page.showReaderCommentPanel = false;
  page.updateReaderCommentPanelHeight(600);
  assert.equal(page.readerCommentPanelHeight, 400, 'closing animation keeps existing document size');
}
{
  const h = harness();
  h.page.scheduleReaderCommentPanelHostReady(0);
  await h.tick();
  assert.equal(h.page.readerCommentPanelLoading, true, 'unpainted document stays covered');
  h.page.readerCommentPanelController.runJavaScript = async () => '1';
  await h.tick();
  assert.equal(h.page.readerCommentPanelLoading, false, 'reveal only after themed frames are ready');
  assert.equal(h.timers.size, 0);
}
{
  const h = harness();
  let resolveOld;
  h.page.readerCommentPanelController.runJavaScript = () => new Promise(resolve => { resolveOld = resolve; });
  h.page.scheduleReaderCommentPanelHostReady(0);
  await h.tick();
  h.page.closeReaderCommentPanel();
  h.page.showReaderCommentPanel = true; // A new panel/document has started loading.
  resolveOld('1');
  for (let i = 0; i < 5; i++) await Promise.resolve();
  assert.equal(h.page.readerCommentPanelLoading, true, 'old document cannot reveal a reopened panel');
}
{
  const h = harness();
  h.page.readerCommentPanelController.runJavaScript = async () => { throw Error('controller not ready'); };
  h.page.scheduleReaderCommentPanelHostReady(0);
  for (let i = 0; i <= 60; i++) await h.tick();
  assert.equal(h.page.readerCommentPanelError, true);
  assert.equal(h.page.readerCommentPanelLoading, true, 'failed theme stays covered instead of flashing white');
  assert.equal(h.timers.size, 0, 'retries are bounded');
  let refreshed = false;
  h.page.readerCommentPanelController.refresh = () => { refreshed = true; };
  h.page.retryReaderCommentPanelLoad();
  assert(refreshed);
  assert.equal(h.page.readerCommentPanelError, false);
}
for (const previousUrl of [null, 'about:blank', 'https://comments.example/list']) {
  const { page } = harness();
  let wentBack = false;
  page.readerCommentPanelController.getBackForwardEntries = () => ({
    currentIndex: previousUrl === null ? 0 : 1,
    getItemAtIndex: () => ({ historyUrl: previousUrl })
  });
  page.readerCommentPanelController.backward = () => { wentBack = true; };
  page.backReaderCommentPanel();
  const hasHistory = previousUrl?.startsWith('https:') === true;
  assert.equal(wentBack, hasHistory, 'navigate real history only');
  assert.equal(page.showReaderCommentPanel, hasHistory, 'root/blank back closes sheet');
}
{
  const { page } = harness();
  page.readerCommentPanelController.getBackForwardEntries = () => { throw Error('not attached'); };
  page.backReaderCommentPanel();
  assert.equal(page.showReaderCommentPanel, false, 'back works during loading too');
}
{
  let backs = 0, closes = 0, forwards = 0;
  const window = { LegadoCommentHost: { back() { backs++; }, close() { closes++; } }, close() {} };
  const history = { back() { throw Error('must delegate to host'); }, go(delta) { forwards += delta; } };
  const context = vm.createContext({ window, history });
  vm.runInContext(ReaderCommentWebTheme.navigation(), context);
  vm.runInContext(ReaderCommentWebTheme.navigation(), context); // loadData/document-start double injection
  history.back(); history.go(-1); window.close(); history.go(1);
  assert.equal(backs, 2);
  assert.equal(closes, 1);
  assert.equal(forwards, 1, 'forward navigation remains unchanged');
}
for (const dark of [false, true]) {
  new vm.Script(ReaderCommentWebTheme.bootstrap(dark));
  new vm.Script(ReaderCommentWebTheme.apply(dark, true));
  const html = ReaderCommentWebTheme.prepareHtml('<!doctype html><html><head><script>pageInit()</script></head><body>评论</body></html>', dark);
  assert(html.startsWith('<!doctype html>'), 'preserve standards mode');
  assert(html.indexOf('__LEGADO_COMMENT_INLINE__') < html.indexOf('pageInit()'), 'theme precedes page scripts');
}
{
  // Each open starts from the app scheme; the reader may then use the page's own theme button and the sheet follows.
  const reports = [], styles = new Map(), timers = [], observers = [], clicks = [];
  const classes = new Set();
  let headerColor = 'rgb(255, 255, 255)';
  const body = { nodeType: 1, parentElement: null, classList: {
    contains: name => classes.has(name),
    toggle: (name, on) => { if (on ?? !classes.has(name)) classes.add(name); else classes.delete(name); }
  } };
  const header = { nodeType: 1, parentElement: body };
  const label = { nodeType: 1, parentElement: header };
  const root = { style: {}, setAttribute() {}, appendChild(node) { styles.set(node.id, node); } };
  let pageToggles = 0;
  const window = {
    innerWidth: 400,
    LegadoCommentHost: { surfaceColor: color => reports.push(color) },
    toggleCmtTheme() { pageToggles++; body.classList.toggle('dark'); },
    dispatchEvent() {}
  };
  const document = { documentElement: root, body, head: root, readyState: 'complete',
    getElementById: id => id === 'themeToggle' ? {} : (styles.get(id) ?? null),
    createElement: () => ({ remove() { styles.delete(this.id); } }),
    elementFromPoint: () => label,
    addEventListener: (type, fn, capture) => { assert.equal(type, 'click'); assert.equal(capture, true); clicks.push(fn); } };
  const context = vm.createContext({ window, document, localStorage: { setItem() {} }, location: { href: 'about:blank' },
    CustomEvent: class {}, requestAnimationFrame: fn => fn(), setTimeout: fn => timers.push(fn),
    getComputedStyle: node => ({ backgroundColor: node === header ? headerColor : 'rgba(0, 0, 0, 0)' }),
    MutationObserver: class { constructor(fn) { this.fn = fn; } observe(target) { observers.push({ target, fn: this.fn }); } } });
  vm.runInContext(`window.__LEGADO_COMMENT_INLINE__=true;`, context);
  vm.runInContext(ReaderCommentWebTheme.apply(false, true), context);
  assert.deepEqual(reports, ['#ffffff'], 'host learns the top colour once applied');
  assert.equal(styles.get('legado-theme-lock'), undefined, 'page theme button stays usable');
  assert.deepEqual(observers.map(item => item.target), [root, body], 'root and body attributes are watched');
  assert.equal(clicks.length, 1);
  for (const fn of timers.splice(0)) fn();
  // The reader taps the page's own theme button: the painted colour changes after a transition.
  window.toggleCmtTheme();
  assert.equal(pageToggles, 1, 'page theme switch still works');
  clicks[0]();
  headerColor = 'rgb(43, 43, 43)';
  for (const fn of timers.splice(0)) fn();
  assert.deepEqual(reports, ['#ffffff', '#2b2b2b'], 'delayed recheck catches the manual switch');
  assert.match(styles.get('legado-comment-canvas').textContent, /#131313/, 'root canvas follows the page');
  observers[1].fn();
  for (const fn of timers.splice(0)) fn();
  assert.deepEqual(reports, ['#ffffff', '#2b2b2b'], 'unchanged colour does not repeat reports');
  // The app switches to dark while the sheet is open: the page already is dark, so it is left alone.
  vm.runInContext(ReaderCommentWebTheme.apply(true, true), context);
  assert.equal(pageToggles, 1);
  assert.equal(clicks.length, 1, 'repeated applies do not stack listeners');
  assert(classes.has('dark'), 'page follows the app dark mode');
}
{
  const context = vm.createContext({});
  const page = vm.runInContext(stripTypeScriptTypes(
    `({${['readerCommentPanelWebBackground', 'isReaderCommentPanelDark', 'updateReaderCommentPanelSurface']
      .map(method).join(',')}})`, { mode: 'strip' }), context);
  Object.assign(page, { showReaderCommentPanel: true, readerCommentPanelSurface: '', appDarkMode: false });
  assert.equal(page.readerCommentPanelWebBackground(), '#FFFFFF');
  page.updateReaderCommentPanelSurface('#2b2b2b');
  assert.equal(page.readerCommentPanelWebBackground(), '#2b2b2b', 'sheet and drag-bar area follow the page');
  assert.equal(page.isReaderCommentPanelDark(), true);
  page.updateReaderCommentPanelSurface('red;');
  assert.equal(page.readerCommentPanelSurface, '#2b2b2b', 'only plain hex colours are accepted from the page');
  page.showReaderCommentPanel = false;
  page.updateReaderCommentPanelSurface('#ffffff');
  assert.equal(page.readerCommentPanelSurface, '#2b2b2b', 'closing sheet keeps its colour until reopened');
  page.readerInlinePageMode = true;
  page.appDarkMode = true;
  assert.equal(page.readerCommentPanelWebBackground(), '#18191B', 'inline sheet follows host dark mode');
  page.appDarkMode = false;
  assert.equal(page.readerCommentPanelWebBackground(), '#FFFFFF', 'inline sheet returns to light mode');
}
console.log('PASS comment panel: live resize, painted-theme reveal, stale callbacks, bounded failure/retry, early HTML theme, Web back/close bridge, manual page theme reaches sheet, page top colour reaches sheet');

for (const inline of [true, false]) {
  let refresh, remoteChecks=0, stabilizations=0;
  const context=vm.createContext({setTimeout:fn=>{refresh=fn;return 1;},clearTimeout(){}});
  const reader=vm.runInContext(stripTypeScriptTypes(`({${method('scheduleReaderThemeRefresh')}})`,{mode:'strip'}),context);
  Object.assign(reader,{readerThemeRefreshOffset:-1,readerThemeRefreshTimerId:-1,readerPageVisible:true,content:'chapter',
    readerThemeRefreshLayoutIdentity:'',readerTypographyCacheIdentity:()=>'layout',
    getReaderStableReflowOffset:()=>10,enterReaderImmersive(){},invalidateReaderTypographyLayout(){},
    refreshReaderTextRender(){},paginateContent(){},scheduleReaderLayoutStabilization(){stabilizations++;},saveReadingProgress(){},
    onTtsCoverSettingsChanged(){},showReaderCommentPanel:true,readerInlinePageMode:inline,
    readerCommentPanelLoadSerial:1,readerCommentPanelLoading:false,readerCommentPanelError:false,
    scheduleReaderCommentPanelHostReady(){remoteChecks++;}});
  reader.scheduleReaderThemeRefresh(); refresh();
  assert.equal(remoteChecks,inline?0:1,'offline theme changes must not invoke the remote Web readiness poll');
  assert.equal(reader.readerCommentPanelLoading,!inline,'offline content stays visible during theme change');
  assert.equal(stabilizations,0,'a colour-only theme change paginates once without a stabilization pass');
}

function inlineHarness() {
  const calls = [], toasts = [];
  const context = vm.createContext({ NativeCommentPage, Error, HttpClient: class {},
    ReaderActionMarker: { parse: () => ({ url: 'action' }) },
    NativeSourceService: { getCommentPage(...args) {
      return new Promise((resolve,reject) => calls.push({ args, resolve, reject }));
    } }, HdsFeedback: { showToast: text => toasts.push(text) } });
  const page = vm.runInContext(stripTypeScriptTypes(`({${['openReaderInlinePage', 'readerInlinePageNeedsRefresh',
    'retryReaderCommentPanelLoad'].map(method).join(',')}})`, {mode:'strip'}),context);
  Object.assign(page, { book:{bookUrl:'book'}, chapters:[{url:'chapter'}], currentChapterIndex:0,
    readerInlinePageSerial:0, currentReaderSource:()=>({bookSourceUrl:'source'}),
    closeReaderCommentPanel() { this.readerInlinePageSerial++; this.showReaderCommentPanel=false; },
    openReaderCommentPanel(url) { this.remote=url; this.readerInlinePageMode=false; } });
  return {page,calls,toasts,open:()=>page.openReaderInlinePage({bookSourceUrl:'source'},{url:'action'},'marker')};
}
{
  const h=inlineHarness(); const first=h.open();
  assert(h.page.readerInlinePageMode && h.page.readerCommentPanelLoading);
  h.page.closeReaderCommentPanel(); assert(h.calls[0].args[5](), 'closing cancels engine requests');
  h.calls[0].resolve(Object.assign(new NativeCommentPage(),{html:'old'})); await first;
  assert.equal(h.page.showReaderCommentPanel,false); assert.notEqual(h.page.readerInlinePage.html,'old');
}
{
  const h=inlineHarness(); const first=h.open(); const second=h.open();
  h.calls[1].resolve(Object.assign(new NativeCommentPage(),{html:'new',height:0.4})); await second;
  h.calls[0].resolve(Object.assign(new NativeCommentPage(),{html:'old'})); await first;
  assert.equal(h.page.readerInlinePage.html,'new'); assert.equal(h.page.readerInlinePage.height,0.4);
  assert.equal(h.page.readerCommentPanelLoading,false);
}
{
  const h=inlineHarness(); const pending=h.open(); h.page.chapters=[{url:'other'}];
  assert(h.calls[0].args[5]()); h.calls[0].resolve(new NativeCommentPage()); await pending;
  assert.equal(h.page.showReaderCommentPanel,false,'changed chapter closes stale loading sheet');
}
{
  const h=inlineHarness(); const pending=h.open();
  h.calls[0].resolve(Object.assign(new NativeCommentPage(),{fallbackUrl:'https://fallback.example',error:'empty'})); await pending;
  assert.equal(h.page.remote,'https://fallback.example'); assert.equal(h.toasts.length,1);
}
{
  const h=inlineHarness(); const pending=h.open(); h.calls[0].reject(Error('invalid context')); await pending;
  assert.equal(h.page.readerCommentPanelError,true); assert(h.toasts[0].includes('invalid context'));
  assert.equal(h.page.readerInlinePageError,'invalid context');
  let retried;
  const openAgain=h.page.openReaderInlinePage.bind(h.page);
  h.page.openReaderInlinePage=(...args)=>{ retried=openAgain(...args); return retried; };
  h.page.retryReaderCommentPanelLoad();
  assert.equal(h.calls.length,2,'transient failure can retry the action');
  assert.equal(h.page.readerInlinePageError,'','new attempt clears the previous reason');
  h.calls[1].resolve(Object.assign(new NativeCommentPage(),{html:'ok'}));
  await retried;
  assert.equal(h.page.readerInlinePage.html,'ok');
}
for (const message of ['评论入口已失效，请刷新本章', '评论上下文不可用，请刷新本章',
  '正文段落已变化，请刷新本章后打开评论']) {
  const h=inlineHarness(); const pending=h.open(); h.calls[0].reject(Error(message)); await pending;
  let refreshes=0;
  h.page.refreshCurrentChapter=async()=>{ refreshes++; };
  assert.equal(h.page.readerInlinePageNeedsRefresh(),true);
  h.page.retryReaderCommentPanelLoad();
  assert.equal(refreshes,1); assert.equal(h.page.showReaderCommentPanel,false);
  assert.equal(h.calls.length,1,'stale actions refresh the chapter instead of looping the same marker');
}
const inlineView=fs.readFileSync(new URL('../entry/src/main/ets/components/NativeCommentPageView.ets',import.meta.url),'utf8');
for (const required of ['incognitoMode: true','.blockNetwork(true)','.fileAccess(false)', '.domStorageAccess(false)',
  '.databaseAccess(false)', '.geolocationAccess(false)', '.allowWindowOpenMethod(false)', '.onOverrideUrlLoading', '.onInterceptRequest']) {
  assert(inlineView.includes(required),required);
}
assert(!inlineView.includes('.javaScriptProxy('),'offline view has no native bridge');
assert(inlineView.includes('.darkMode(this.darkMode ? WebDarkMode.On : WebDarkMode.Off)'));
assert(inlineView.includes('.forceDarkAccess(false)'), 'source CSS handles dark colours without double inversion');
assert(inlineView.includes('.backgroundColor(this.surfaceColor())'));
assert(source.includes('page: this.readerInlinePage, darkMode: this.appDarkMode'));
assert(fs.readFileSync(new URL('../entry/src/main/ets/pages/BookSourceDebug.ets',import.meta.url),'utf8')
  .includes('page: this.inlinePreview, darkMode: this.appDarkMode'));
function inlineWebHarness() {
  const timers=new Map(),loads=[],displays=[];let id=0,ready='false',stopped=0;
  const names=['load','pageEnded','clearTimer','scheduleReady','fail','aboutToDisappear','beginDisplay','endDisplay'];
  const methods=names.map(name=>{
    const start=new RegExp(`^  (?:private )?${name}\\(`,'m').exec(inlineView)?.index;
    assert.notEqual(start,undefined,name);
    return inlineView.slice(start,inlineView.indexOf('\n  }',start)+4).replace(/^  private /,'  ');
  });
  const util={Base64Helper:class {encodeToStringSync(bytes){return Buffer.from(bytes).toString('base64');}},TextEncoder:class {encodeInto(text){return Buffer.from(text,'utf8');}}};
  const context=vm.createContext({NativeCommentPage,util,Error,setTimeout:(fn,ms)=>{timers.set(++id,{fn,ms});return id;},clearTimeout:id=>timers.delete(id)});
  const view=vm.runInContext(stripTypeScriptTypes(`({${methods.join(',')}})`,{mode:'strip'}),context);
  Object.assign(view,{attached:true,initialPageReady:true,serial:0,timer:-1,readyTimer:-1,page:Object.assign(new NativeCommentPage(),{html:'<p>test</p>'}),
    error:'',displayOpen:false,onDisplay:(state,message)=>displays.push(state+(message?':'+message:'')),
    controller:{loadData:(...args)=>loads.push(args),runJavaScript:async()=>ready,stop:()=>stopped++}});
  return {view,timers,loads,displays,ready:value=>{ready=value;},stopped:()=>stopped,async tick(ms){
    const [key,value]=[...timers].find(([,value])=>value.ms===ms)||[];assert(value,'expected timer');timers.delete(key);value.fn();
    for(let i=0;i<6;i++) await Promise.resolve();
  }};
}
{
  const h=inlineWebHarness();h.view.initialPageReady=false;h.view.load();
  assert.equal(h.loads.length,0,'loadData must not race the initial declarative about:blank navigation');
  h.view.pageEnded('about:blank');assert.equal(h.loads.length,1);
  h.view.pageEnded('data:text/html;base64,'+h.view.documentBase64);
  assert.equal(h.loads.length,1,'generated page-end only probes readiness, never submits another document');
  h.view.aboutToDisappear();assert.equal(h.view.initialPageReady,false);
}
{
  const h=inlineWebHarness();h.view.page.html='<p style="color:#123">中文 # 100% 😀</p>';h.view.load();
  assert.equal(h.loads[0][2],'base64');
  const document=Buffer.from(h.loads[0][0],'base64').toString('utf8');
  assert(document.includes('__NATIVE_PAGE_GENERATION__=1'));assert(document.includes('中文 # 100% 😀'));
  for(const prefix of ['data:text/html;base64,','data:text/html;charset=utf-8;base64,']) {
    assert(NativeCommentDocumentPolicy.allowsNavigation(prefix+h.view.documentBase64,true,h.view.documentBase64));
    assert(!NativeCommentDocumentPolicy.allowsNavigation(prefix+h.view.documentBase64,false,h.view.documentBase64),'subframe data documents stay blocked');
    assert(!NativeCommentDocumentPolicy.allowsNavigation(prefix+'PGgxPm90aGVyPC9oMT4=',true,h.view.documentBase64),'other HTML stays blocked');
  }
  for(const url of ['https://example.com','file:///etc/passwd','data:text/html,<p>other</p>','javascript:alert(1)']) {
    assert(!NativeCommentDocumentPolicy.allowsNavigation(url,true,h.view.documentBase64),url);
    assert(!NativeCommentDocumentPolicy.allowsResource(url,true,h.view.documentBase64),url);
  }
  assert(NativeCommentDocumentPolicy.allowsNavigation('about:srcdoc',false,h.view.documentBase64));
  assert(NativeCommentDocumentPolicy.allowsResource('data:image/png;base64,AA==',false,h.view.documentBase64));
  await h.tick(100);assert.equal(h.view.loading,true,'no page-end event is needed for readiness polling');
  h.ready('true');await h.tick(100);assert.equal(h.view.loading,false);assert.equal(h.timers.size,0);
  h.view.aboutToDisappear();assert.deepEqual(h.displays,['start','ready'],'display result is reported once');
}
{
  const h=inlineWebHarness();h.view.load();await h.tick(15000);assert.match(h.view.error,/15 秒/);
  assert.equal(h.view.attached,false);assert.equal(h.timers.size,0);assert.equal(h.stopped(),1);
  assert.deepEqual(h.displays,['start','failed:评论页渲染超过 15 秒'],'generation pass is not reported as display pass');
}
{
  const h=inlineWebHarness();h.view.load();h.view.aboutToDisappear();assert.equal(h.timers.size,0);assert.equal(h.view.attached,false);
  assert.deepEqual(h.displays,['start','cancelled:预览已关闭']);
}
{
  const h=inlineWebHarness();h.view.load();h.view.load();
  assert.deepEqual(h.displays,['start','cancelled:已重新加载','start'],'a reload closes the previous attempt first');
}
{
  const h=inlineWebHarness();h.view.load();const stale=[...h.timers.values()].find(x=>x.ms===15000).fn;
  h.view.load();stale();assert.equal(h.view.error,'','old timeout cannot fail the replacement document');
  h.view.aboutToDisappear();assert.equal(h.view.documentBase64,'','destroyed documents lose their navigation grant');
}
console.log('PASS inline comment panel: click, close cancellation, stale results, chapter changes, fallback and error handling; Web policy wiring');

const panel = source.slice(source.indexOf('  readerCommentPanel()'), source.indexOf('  readerFloatingTopMenu()'));
assert.match(panel, /scrollForward: NestedScrollMode.SELF_ONLY/);
assert.match(panel, /scrollBackward: NestedScrollMode.SELF_ONLY/);
assert.doesNotMatch(panel, /hitTestBehavior\(HitTestMode.Block\)/, 'no inert overlay can cover the system drag handle');
const sheetContext = vm.createContext({ SheetSize: { LARGE: 'large' }, ScrollSizeMode: { CONTINUOUS: 'continuous' },
  LengthMetrics: { vp: value => ({ vp: value }) }, ThemeRuntime: { largeRadius: () => 22 } });
const sheetPage = vm.runInContext(stripTypeScriptTypes(`({${method('readerCommentSheetOptions')}})`, { mode: 'strip' }), sheetContext);
sheetPage.readerCommentPanelWebBackground = () => '#FFFFFF';
const sheet = sheetPage.readerCommentSheetOptions();
assert.equal(sheet.dragBar, true, 'native sheet owns the functional drag handle');
assert.deepEqual(Array.from(sheet.detents), ['60%', 'large']);
assert.equal(sheet.scrollSizeMode, 'continuous');
assert.deepEqual(sheet.radius, { vp: 22 }, 'sheet corners follow the theme large radius');
assert.equal(sheet.onHeightDidChange, undefined, 'whole-sheet height must not be used as Web viewport height');
const resizeHandler = panel.match(/\.onSizeChange\((\(_oldValue: SizeOptions, newValue: SizeOptions\) => \{[\s\S]*?\n    \})\)/)?.[1];
assert(resizeHandler, 'measure the content viewport below the native handle');
const resizeHarness = harness();
const resize = vm.runInContext(stripTypeScriptTypes(resizeHandler, { mode: 'strip' }), vm.createContext(resizeHarness.page));
for (const height of [320, 640, 420]) {
  resize({ height: 0 }, { height });
  assert.equal(resizeHarness.page.readerCommentPanelHeight, height, 'native drag resizes Web in vp without including the handle');
}
console.log('PASS: native drag handle enabled; theme corner radius; Web scroll isolated; content viewport follows available height');

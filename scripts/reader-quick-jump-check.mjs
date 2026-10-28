import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';
import { loadReaderModules } from './lib/load-reader-modules.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const strip = text => stripTypeScriptTypes(text.replace(/^export /gm, ''), { mode: 'strip' });
const modelContext = vm.createContext({});
vm.runInContext(strip(read('core/reader/ReaderQuickJumpModel.ts')) + '\nglobalThis.Model = ReaderQuickJumpModel;', modelContext);
const M = modelContext.Model;
for (const bad of [NaN, Infinity, -Infinity]) assert.equal(M.clampPercent(bad), 0);
assert.equal(M.normalizeMode('percent'), 'percent');
assert.equal(M.normalizeMode('bad'), 'chapter');
for (const [p,n,c,r] of [[0,240,0,0],[100,240,239,1],[62.5,240,149,1],[62.6,240,150,.24],
  [50,1,0,.5],[-1,240,0,0],[110,240,239,1],[50,0,0,0]]) {
  const t = M.fromPercent(p,n);
  assert.equal(t.chapterIndex,c);
  assert(Math.abs(t.chapterRatio-r)<1e-8);
}
assert.equal(M.pageIndex(.24,25),5);
assert.equal(M.pageIndex(0,25),0);
assert.equal(M.pageIndex(1,25),24);
// Every actual page-end percentage must round-trip, including chapter boundaries.
let checked = 0;
for (const count of [1,2,240,10001]) for (const pages of [1,7,25,301]) {
  for (const chapter of new Set([0,Math.floor(count/2),count-1])) {
    for (let page=0;page<pages;page++) {
      const t=M.fromPercent((chapter+(page+1)/pages)/count*100,count);
      assert.equal(t.chapterIndex,chapter);
      assert.equal(M.pageIndex(t.chapterRatio,pages),page);
      checked++;
    }
  }
}
console.log(`PASS: percentage boundaries and ${checked} page round-trips`);

const source = read('pages/ReadBook.ets');
const method = source.slice(source.indexOf('  async performReaderQuickJump('), source.indexOf('  restorePendingPageIndex('));
assert(method.includes('async performReaderQuickJump'));

function harness(options={}) {
  const calls=[], toasts=[];
  let h;
  const session={
    currentOwnerId:()=>options.mirror?'background':'',
    isOwner:()=>!!options.owner,
    pause:async()=>{h.globalTtsPaused=true;calls.push('pause-mirror')},
    jumpToPreparedPosition:async(owner,chapter,offset,resume)=>{
      calls.push(['mirror',owner,chapter,offset,resume]);return options.mirrorFailure!==true;
    },
    toggle:async()=>{calls.push('resume-mirror')},
    updatePosition:()=>{}
  };
  const context=vm.createContext({
    ReaderQuickJumpModel:M,ReaderTtsFloatingSession:session,
    HdsFeedback:{showToast:t=>toasts.push(t)},console:{warn(){}},setTimeout,clearTimeout,
    sleepMs:async()=>{if(options.onYield) options.onYield(h)}
  });
  vm.runInContext(strip(`class ReaderHarness { ${method} }\nglobalThis.ReaderHarness=ReaderHarness;`),context);
  h=new context.ReaderHarness();
  const chapters=Array.from({length:240},(_,i)=>({url:`chapter-${i}`}));
  const engine={book:{bookUrl:'book'},chapters,curIdx:47,curPos:9,
    peekContent:async()=>{calls.push('fetch');if(options.fetch)return options.fetch(h);return 'x'.repeat(250)}
  };
  const result={source:'body',pages:['p0'],starts:[0],ends:[10],complete:false};
  Object.assign(h,{
    quickJumpBusy:false,quickJumpSerial:0,bookUrl:'book',currentChapterIndex:47,currentPageIndex:9,
    content:'original',contentPages:Array(20).fill('original'),readerPageVisible:true,
    readerUseChapterQuickJump:true,contentLoadSerial:1,readerPaginationWorkSerial:0,
    mirroredTtsFocusSyncSerial:0,chapters,globalTtsPaused:false,
    isTtsSpeaking:false,isTtsPaused:false,readerAutoScrollActive:false,readerAutoScrollPaused:true,
    ttsFloatingSessionOwnerId:'visible',readerPaginationCache:new Map(),
    isReaderComicModeActive:()=>!!options.comic,hasPagedReaderArea:()=>true,
    readerComicEffectiveMode:()=> 'webtoon',isReaderComicDualPageActive:()=>!!options.doublePage,
    readerComicChapterSwitching:false,readerContinuousCommitChapter:-1,
    readerEngine:()=>engine,readerPaginationViewportIdentity:()=>'viewport',
    readerTypographyCacheIdentity:()=>'font',readerEffectivePageTurnMode:()=>2,
    isMirroringActiveTtsForCurrentBook:()=>!!options.mirror,
    ttsReader:{isSpeaking:()=>!!options.owner,isPaused:()=>!!options.owner},pauseReaderAutoScroll:()=>{},
    prepareReaderContentRules:async b=>b,buildPagedSourceText:(_,b)=>b,
    buildReaderPaginationCacheKey:()=> 'target',getCachedReaderPagination:()=>null,
    createIncrementalReaderPagination:(body,chapter,count,register)=>{
      assert.equal(register,false,'preflight must not overwrite visible V2 session');
      calls.push('paginate');return options.paginate ? options.paginate(body) : result;
    },
    appendReaderPaginationBatch:r=>{
      assert.equal(h.content,'original','incremental pagination must not publish provisional text');
      assert.equal(h.currentChapterIndex,47);
      const i=r.pages.length;r.pages.push(`p${i}`);r.starts.push(i*10);r.ends.push((i+1)*10);
      r.complete=r.pages.length===25;
    },
    normalizeReaderSpreadPageIndex:i=>options.doublePage?i-i%2:i,
    normalizeReaderQuickJumpPageIndex:i=>options.doublePage?i-i%2:i,
    stopReaderComicScreenScroll:()=>calls.push('stop-scroll'),cancelReaderComicPan:()=>{},
    updateReaderComicPaginationProgress:(_chapter,result)=>{h.readerComicPaginationTotalPages=result.pages.length},
    comicImageActions:()=>({onChapterBecameCurrent:chapter=>calls.push(['comic-chapter',chapter])}),
    closeReaderCommentPanel:()=>{},clearQueuedReaderPageTurns:()=>{},
    applyReaderPaginationResult:r=>{h.contentPages=r.pages;calls.push('commit')},
    saveReadingProgress:async(_notify,commit)=>{assert.equal(h.quickJumpBusy,true);assert.equal(commit,true);calls.push('save')},
    scheduleReaderPaginationCompletion:()=>calls.push('background-pagination'),preloadReaderContentLater:()=>{},
    resetMenuChapterPreview:()=>{},startReaderAutoScroll:async()=>{},
    stopTtsReaderForChapterSwitch:()=>calls.push('stop-old-speech'),
    updateTtsFloatingSession:()=>{},
    startTtsReadingFromCurrentPosition:async(_toast,_manual,_serial,offset)=>calls.push(['speak',offset]),
  });
  return {h,calls,toasts,engine};
}

{
  const {h,calls,engine}=harness();
  assert(await h.performReaderQuickJump(150,.24));
  assert.equal(h.currentChapterIndex,150);assert.equal(h.currentPageIndex,5);
  assert.equal(engine.curIdx,150);assert.equal(h.contentPages.length,25);
  assert.deepEqual(calls,['fetch','paginate','commit','save']);
  assert.equal(h.quickJumpBusy,false);
}
{
  const {h,calls}=harness();
  assert(await h.performReaderQuickJump(87,-1));
  assert.equal(h.currentPageIndex,0);
  assert(calls.includes('background-pagination'),'chapter jump should not wait for whole chapter');
}
{
  const {h}=harness({doublePage:true});
  assert(await h.performReaderQuickJump(150,.24));assert.equal(h.currentPageIndex,4);
}
for(const options of [{fetch:async()=>''},{fetch:async()=>{throw Error('offline')}},
  {onYield:h=>{h.contentLoadSerial++}}, {onYield:h=>{h.readerPageVisible=false}},
  {onYield:h=>{h.chapters=h.chapters.slice(0,200)}},
  {onYield:h=>{h.readerUseChapterQuickJump=false}}]) {
  const {h,calls,engine}=harness(options);
  assert.equal(await h.performReaderQuickJump(150,.24),false);
  assert.equal(h.currentChapterIndex,47);assert.equal(h.currentPageIndex,9);
  assert.equal(h.content,'original');assert.equal(engine.curIdx,47);
  assert(!calls.includes('save'));assert.equal(h.quickJumpBusy,false);
}
{
  let release;
  const {h,calls}=harness({fetch:()=>new Promise(resolve=>{release=resolve})});
  const first=h.performReaderQuickJump(150,.24);
  assert.equal(await h.performReaderQuickJump(87,-1),false,'duplicate submission blocked');
  release('body');assert(await first);assert.equal(calls.filter(c=>c==='commit').length,1);
}
{
  const {h,calls}=harness({mirror:true});
  assert(await h.performReaderQuickJump(150,.24));
  const handoff=calls.find(c=>Array.isArray(c));
  assert.deepEqual(handoff,['mirror','background',150,50,true]);
  assert(calls.indexOf(handoff)<calls.indexOf('commit'));
}
{
  const {h,calls}=harness({mirror:true,mirrorFailure:true});
  assert.equal(await h.performReaderQuickJump(150,.24),false);
  assert.equal(h.currentChapterIndex,47);assert(!calls.includes('commit'));
  assert(calls.includes('resume-mirror'));
}
console.log('PASS: deferred commit, chapter fast path, spread normalization, offline failure, stale navigation, duplicate submission and mirrored TTS handoff');
for (const resume of [false,true]) {
  const {h,calls}=harness({owner:true});
  h.readerPageVisible=false;
  assert(await h.performReaderQuickJump(150,-1,53,true,resume));
  assert.equal(h.currentPageIndex,5);
  if(resume) assert.deepEqual(calls.find(c=>Array.isArray(c)),['speak',53]);
  else {
    assert(!calls.some(c=>Array.isArray(c)));
    assert.equal(h.isTtsPaused,true);
    assert.equal(h.quickJumpPausedSpeechOffset,53);
  }
}
console.log('PASS: hidden TTS owner resolves source offsets and preserves paused/playing intent');

const modules = await loadReaderModules();
try {
  const {ReaderImageMarker:I,ReaderChunkPagination:C,ReaderInfoBarText:Info}=modules;
  const body=Array.from({length:25},(_,i)=>I.create(`/data/comic/${i}.jpg`)).join('\n\n');
  const comicOptions={comic:true,mirror:true,owner:true,fetch:async()=>body,
    paginate:source=>({...C.splitComic(source),source,complete:true})};
  for(const [percent,chapter,page] of [[0,0,0],[100,239,24],[62.5,149,24],[62.6,150,5]]) {
    for(const doublePage of [false,true]) {
      const {h,calls,engine}=harness({...comicOptions,doublePage});
      h.readerComicPaginationTotalPages=300;
      const target=M.fromPercent(percent,240);
      assert(await h.performReaderQuickJump(target.chapterIndex,target.chapterRatio));
      const expected=doublePage?page-page%2:page;
      assert.equal(h.currentChapterIndex,chapter);assert.equal(h.currentPageIndex,expected);
      assert.equal(engine.curPos,expected);assert.equal(h.readerComicPaginationTotalPages,25);
      assert.equal(h.contentPages[expected],I.create(`/data/comic/${expected}.jpg`));
      assert.equal(Info.bookPercent({chapterIndex:chapter,chapterCount:240,
        pageIndex:expected,pageCount:h.readerComicPaginationTotalPages}),
        (chapter+(expected+1)/25)/240*100);
      assert(!calls.includes('pause-mirror') && !calls.includes('stop-old-speech'));
      assert(!calls.some(c=>Array.isArray(c)&&c[0]==='speak'));
      assert(calls.some(c=>Array.isArray(c)&&c[0]==='comic-chapter'&&c[1]===chapter));
    }
  }
  const {h}=harness(comicOptions);
  assert(await h.performReaderQuickJump(87,-1));
  assert.equal(h.currentChapterIndex,87);assert.equal(h.currentPageIndex,0);
  for(const fetch of [async()=>{throw Error('offline')},async h=>{
    h.readerComicEffectiveMode=()=> 'rtl';return body;
  }]) {
    const {h,calls,engine}=harness({...comicOptions,fetch});
    assert.equal(await h.performReaderQuickJump(150,.24),false);
    assert.equal(h.currentChapterIndex,47);assert.equal(h.currentPageIndex,9);
    assert.equal(h.content,'original');assert.equal(engine.curIdx,47);
    assert(!calls.includes('save'));
  }
} finally { modules.cleanup(); }
console.log('PASS: comic image pagination, chapter start, 0/100 and chapter boundaries, dual pages, actual progress, failed fetch and mode changes');

// Drive the actual slider/dialog handlers: preview, mode switch and Cancel never commit progress.
function pageMethod(name) {
  const match=new RegExp(`^  (?:async )?${name}\\(`,'m').exec(source);
  assert(match,name);
  return source.slice(match.index,source.indexOf('\n  }',match.index)+4);
}
{
  const savedModes=[],jumps=[];
  let button=0;
  const context=vm.createContext({
    ReaderQuickJumpModel:M,ReaderInfoBarText:{bookPercent:()=>19.8},
    ReaderSettingsStore:{saveLayoutElementSettings:async(...args)=>savedModes.push(args.at(-1))},
    SliderChangeMode:{Begin:0,Moving:1,End:2,Click:3},
    promptAction:{showDialog:async()=>({index:button})},HdsFeedback:{showToast(){}},
    animateTo:(_options,action)=>action(),Curve:{EaseOut:0},getContext:()=>({}),console
  });
  vm.runInContext(strip(`class Controls { ${['getMenuChapterDisplayIndex','getMenuPercentDisplay',
    'setReaderQuickJumpMode','handleMenuChapterSliderChange','confirmMenuChapterJump',
    'resetMenuChapterPreview'].map(pageMethod).join('\n')} }\nglobalThis.Controls=Controls;`),context);
  const h=new context.Controls();
  Object.assign(h,{quickJumpBusy:false,menuChapterConfirming:false,quickJumpSerial:0,
    bookUrl:'book',chapters:Array(240).fill({}),currentChapterIndex:47,currentPageIndex:9,
    readerQuickJumpMode:'chapter',readerPageVisible:true,readerUseChapterQuickJump:true,
    contentPages:Array(20).fill(''),shouldBlockReaderInteraction:()=>false,
    clampChapterIndex:i=>Math.max(0,Math.min(239,i)),getReaderInfoBarContext:()=>({}),
    isCurrentReaderPaginationComplete:()=>true,normalizeReaderSpreadPageIndex:i=>i,
    normalizeReaderQuickJumpPageIndex:i=>i,readerQuickJumpChapterUnit:()=> '章',
    getChapterTitle:()=> 'Chapter',readerPanelSubTextColor:()=> 'gray',accentColor:()=> 'blue',
    performReaderQuickJump:async(...args)=>{jumps.push(args);return true}
  });
  h.handleMenuChapterSliderChange(87,1);
  assert.equal(h.getMenuChapterDisplayIndex(),87);
  assert.equal(h.currentChapterIndex,47);assert.equal(jumps.length,0);
  h.setReaderQuickJumpMode('percent');
  assert.equal(h.menuChapterSliderActive,false);assert.equal(h.currentPageIndex,9);
  assert.deepEqual(savedModes,['percent']);
  h.handleMenuChapterSliderChange(62.6,1);
  await h.confirmMenuChapterJump(h.getMenuChapterDisplayIndex());
  assert.equal(jumps.length,0);assert.equal(h.menuChapterSliderActive,false);
  assert.equal(h.currentChapterIndex,47);
  button=1;h.handleMenuChapterSliderChange(62.6,1);
  await h.confirmMenuChapterJump(h.getMenuChapterDisplayIndex());
  assert.equal(jumps.length,1);assert.equal(jumps[0][0],150);
  assert(Math.abs(jumps[0][1]-.24)<1e-8);
}
console.log('PASS: preview and mode switch leave position untouched; Cancel resets preview; Confirm commits the frozen target once');

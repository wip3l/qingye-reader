import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { readEtsModule, projectRoot } from './lib/ets-module-staging.mjs';

const pending=[];
const source={bookSourceUrl:'https://fixture.invalid',bookSourceName:'fixture',enabledExplore:true,exploreUrl:'native'};
const native={isNative:()=>true,filters:()=>[],
  explore:(_s,_h,_url,_p,_d,cancelled)=>new Promise((resolve,reject)=>pending.push({cancelled,resolve,reject})),
  exploreMenus:(_s,_h,_d,cancelled)=>new Promise((resolve,reject)=>pending.push({cancelled,resolve,reject}))};
const context=vm.createContext({console,NativeSourceService:native,
  appDb:{getBookSource:async()=>source,getEnabledBookSourcesForExplore:async()=>[source]},
  VerificationSupport:{clearVerification(){}},ExplorePlatformSelector:class{}});
const code=readEtsModule('core/book/ExploreCoordinator.ts');
function method(source,name){
  const start=new RegExp(`^  (?:private )?(?:static )?(?:async )?${name}\\(`,'m').exec(source)?.index;
  assert.notEqual(start,undefined,name);
  return source.slice(start,source.indexOf('\n  }',start)+4).replace(/^  private /,'  ');
}
const methods=['cancelPending','getEntries','explore','exploreNative','nativeEntries'];
const create=()=>Object.assign(vm.runInContext(stripTypeScriptTypes(`({${methods.map(n=>method(code,n)).join(',')}})`),context),{
  loadGeneration:0,http:{},noticeMessage:'',menuCache:{},filterSelectors:{},menuCacheKey:()=> 'key',
  sanitizeExploreBook(){},storeMenuCache(key,entries){this.menuCache[key]={entries,cachedAt:Date.now()};}});
const entry={sourceUrl:source.bookSourceUrl,url:'/list'};
const settle=async()=>{for(let i=0;i<10;i++)await Promise.resolve();};

const a=create(),b=create();
const old=a.explore(entry);await settle();const oldRequest=pending.shift();
const independent=b.explore(entry);await settle();const other=pending.shift();
a.cancelPending();
assert.equal(oldRequest.cancelled(),true);assert.equal(other.cancelled(),false);
const current=a.explore(entry);await settle();const fresh=pending.shift();assert.equal(fresh.cancelled(),false);
fresh.resolve([{bookUrl:'/new',name:'new'}]);await current;
a.noticeMessage='current result';oldRequest.reject(new Error('stale error'));await old;
assert.equal(a.noticeMessage,'current result','late failure must not overwrite current UI notice');
other.resolve([]);await independent;

const menus=a.getEntries();await settle();const oldMenus=pending.shift();
a.cancelPending();assert.equal(oldMenus.cancelled(),true);
oldMenus.resolve([{title:'stale',target:'/stale'}]);assert.equal((await menus).length,0);
assert.equal(a.menuCache.key,undefined,'cancelled menus cannot repopulate cache');

// Verify the real service wrapper forwards the same cancellation function to its runner.
const serviceSource=readEtsModule('core/nativesource/NativeSourceService.ts');
vm.runInContext(stripTypeScriptTypes(`class Service {
  ${method(serviceSource,'exploreMenus')}
  ${method(serviceSource,'explore')}
}`),context);
const Service=vm.runInContext('Service',context);
let received;
Service.runner=(_s,_h,cancelled)=>{received=cancelled;return {explore:async()=>[],exploreMenus:async()=>[]};};
Service.toSearchBook=(_s,book)=>book;
context.NativeSourceService=Service;
const cancel=()=>true;
await Service.explore(source,{},'/list',1,null,cancel);assert.equal(received,cancel);
await Service.exploreMenus(source,{},null,cancel);assert.equal(received,cancel);

const pageSource=fs.readFileSync(`${projectRoot}/entry/src/main/ets/components/home/ExplorePage.ets`,'utf8');
const page=vm.runInContext(stripTypeScriptTypes(`({${['beginExploreLoad','cancelExploreLoad','aboutToDisappear']
  .map(n=>method(pageSource,n)).join(',')}})`),context);
let cancellations=0;
Object.assign(page,{coordinator:{cancelPending(){cancellations++;}},exploreLoadVersion:0,
  exploreMetadataQueued:new Set(),exploreMetadataUnavailable:new Set(),isLoadingMore:true,exploreContentLoadedAt:42});
page.beginExploreLoad();page.aboutToDisappear();
assert.equal(cancellations,2);assert.equal(page.exploreLoadVersion,2);
assert.equal(page.isLoading,false);assert.equal(page.isLoadingMore,false);assert.equal(page.exploreContentLoadedAt,0);
console.log('PASS explore cancellation: active requests, dynamic menus/cache, stale errors, independent coordinator, service forwarding, page lifecycle');

// node scripts/home-motion-check.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
import { projectRoot } from './lib/ets-module-staging.mjs';

const read = file => fs.readFileSync(`${projectRoot}/entry/src/main/ets/${file}`, 'utf8');
const ledgerSource = read('utils/ResultArrivalTracker.ts').replace('export class', 'class');
const ledger = vm.runInNewContext(stripTypeScriptTypes(`${ledgerSource}\nnew ResultArrivalTracker()`));
ledger.record(['group:novel:book', 'item:source-a/book'], true, 0);
assert.equal(ledger.claim('group:novel:book', 10), 0);
ledger.record(['group:novel:book', 'item:source-a/book', 'item:source-b/book'], true, 40);
assert.equal(ledger.claim('group:novel:book', 50), -1, 'growing aggregation must not replay the card');
assert.equal(ledger.claim('item:source-b/book', 50), 20, 'a new raw source can animate separately');
assert.equal(ledger.claim('item:source-b/book', 60), -1, 'recycling the same card cannot replay it');
assert.equal(ledger.claim('item:source-a/book', 501), -1, 'scrolling to an old offscreen result does not animate');
ledger.record(['hidden'], false, 510);
ledger.record(['hidden'], true, 520);
assert.equal(ledger.claim('hidden', 530), -1, 'background arrivals remain quiet when returning');
ledger.record(['pending'], true, 540);
ledger.discardPending();
assert.equal(ledger.claim('pending', 550), -1, 'leaving the page cancels pending arrivals');
ledger.reset();
ledger.record(Array.from({ length: 30 }, (_, i) => `${i}`), true, 1000);
const batchDelays = Array.from({ length: 30 }, (_, i) => ledger.claim(`${i}`, 1010));
assert.deepEqual(batchDelays.slice(0, 8), [0, 20, 40, 60, 80, 100, 100, 100]);
assert.ok(batchDelays.every(delay => delay >= 0 && delay <= 100), 'wide-screen batches all fade in without an unbounded stagger');
ledger.record(['later-batch'], true, 1400);
assert.equal(ledger.claim('later-batch', 1401), 0, 'later incremental batches start promptly');
ledger.reset();
ledger.record(['group:novel:book'], true, 2000);
assert.equal(ledger.claim('group:novel:book', 2001), 0, 'a new search session can animate the same book again');
ledger.reset();
ledger.record(['slow-cover'], true, 3000);
ledger.markReady('slow-cover', true, 9000);
assert.equal(ledger.claim('slow-cover', 9001), 0, 'arrival starts after decoding, not at the raw result timestamp');
ledger.markReady('slow-cover', true, 9500);
assert.equal(ledger.claim('slow-cover', 9501), -1, 'category remount and cover updates cannot replay readiness');
ledger.markReady('background-cover', false, 9600);
ledger.markReady('background-cover', true, 9700);
assert.equal(ledger.claim('background-cover', 9701), -1, 'background-prepared cards remain quiet on return');

let now = 0, nextTimer = 0;
const timers = new Map();
const context = vm.createContext({
  Date: { now: () => now }, Math, Index: { TAB_SWITCH_DURATION: 320 },
  setTimeout: (callback, delay) => { timers.set(++nextTimer, { callback, due: now + delay }); return nextTimer; },
  clearTimeout: id => timers.delete(id)
});
const indexSource = read('pages/Index.ets');
const names = ['prepareHomeTabSwitch', 'homeTabIsMounted', 'homeTabIsActive', 'finishHomeTabSwitch', 'selectHomeTab', 'clearHomeTabSwitch'];
const bodies = names.map(name => {
  const start = indexSource.indexOf(`  ${name}(`);
  assert.ok(start >= 0, name);
  return indexSource.slice(start, indexSource.indexOf('\n  }', start) + 4);
});
const home = vm.runInContext(stripTypeScriptTypes(`({${bodies.join(',')}})`), context);
let hds = true;
const changes = [];
Object.assign(home, {
  currentIndex: 0, homeTransitionFrom: -1, homeTransitionTo: -1, homeTransitionTimer: -1,
  homeTransitionStartedAt: 0, exploreTabMounted: false, syncHomeSystemBars() {},
  supportsImmersiveTabs: () => hds,
  immersiveTabsController: { changeIndex: index => changes.push(['hds', index]) },
  compatTabsController: { changeIndex: index => changes.push(['compat', index]) }
});
home.selectHomeTab(1);
assert.equal(home.exploreTabMounted, true, 'discovery mounts before the native slide begins');
assert.equal(home.homeTabIsMounted(0), true, 'outgoing shelf survives during the transition');
assert.equal(home.homeTabIsActive(1), true, 'destination starts loading immediately');
home.finishHomeTabSwitch(1);
assert.equal(home.homeTabIsMounted(0), true, 'an early onChange must not blank the outgoing page');
now = 100;
home.selectHomeTab(3);
home.finishHomeTabSwitch(1);
assert.equal(home.homeTransitionTo, 3, 'late callback from the previous slide cannot replace latest selection');
assert.equal(timers.size, 0, 'new selection cancels old cleanup');
home.finishHomeTabSwitch(3);
now = 420;
for (const [id, timer] of timers) if (timer.due <= now) { timers.delete(id); timer.callback(); }
assert.equal(home.currentIndex, 3);
assert.equal(home.homeTabIsMounted(0), true, 'shelf survives completion so returning cannot mount an empty loading page');
assert.equal(home.homeTransitionTo, -1);
hds = false;
home.selectHomeTab(0);
assert.deepEqual(changes, [['hds', 1], ['hds', 3], ['compat', 0]], 'programmatic navigation uses native controllers in both paths');
home.finishHomeTabSwitch(0);
home.clearHomeTabSwitch();
assert.equal(timers.size, 0, 'unmount/theme replacement cancels delayed cleanup');
assert.equal(home.homeTabIsActive(0), true);

// Repeated discovery -> shelf switches must preserve the same shelf instance at every phase,
// including an idle interval well beyond the transition's retention timer.
for (let round = 0; round < 3; round++) {
  for (const target of [1, 0]) {
    home.selectHomeTab(target);
    assert.equal(home.homeTabIsMounted(0), true, 'shelf survives transition preparation');
    home.finishHomeTabSwitch(target);
    assert.equal(home.homeTabIsMounted(0), true, 'shelf survives onChange');
    now += 1000;
    for (const [id, timer] of timers) if (timer.due <= now) { timers.delete(id); timer.callback(); }
    assert.equal(home.homeTabIsMounted(0), true, 'shelf survives offscreen cleanup and the next return');
    assert.equal(home.homeTabIsMounted(3), false, 'retaining the shelf does not retain the settings page');
  }
}

const indexChangeStart = indexSource.indexOf('  onCurrentIndexChanged(');
const indexChangeBody = indexSource.slice(indexChangeStart, indexSource.indexOf('\n  }', indexChangeStart) + 4);
const indexChange = vm.runInContext(stripTypeScriptTypes(`({${indexChangeBody}})`), context);
const collapse = [0.75, 0.5, 0, 0.5];
const collapseState = { currentIndex: 0, tabHeaderCollapseProgress: collapse, syncBottomBarCollapse() {} };
indexChange.onCurrentIndexChanged.call(collapseState);
assert.equal(collapse[0], 0.75, 'returning shelf keeps bottom-bar progress consistent with its retained header');
collapseState.currentIndex = 3;
indexChange.onCurrentIndexChanged.call(collapseState);
assert.equal(collapse[3], 0, 'rebuilt settings page still resets its header');

// Discovery uses the same ledger with category-scoped identities, including its dynamic list page.
vm.runInContext(stripTypeScriptTypes(ledgerSource), context);
const exploreSource = read('components/home/ExplorePage.ets');
const exploreMethods = ['exploreResultArrivalKey', 'claimExploreResultArrival', 'onExploreResultReady', 'isCurrentExplorePage'];
const explore = vm.runInContext(stripTypeScriptTypes(`({${exploreMethods.map(name => {
  const start = exploreSource.indexOf(`  ${name}(`);
  assert.ok(start >= 0, name);
  return exploreSource.slice(start, exploreSource.indexOf('\n  }', start) + 4);
}).join(',')}})`), context);
Object.assign(explore, { resultArrivalTracker: vm.runInContext('new ResultArrivalTracker()', context),
  isActive: true, selectedIndex: 0, exploreBooksPageKey: 'first', explorePageKeys: () => ['first', 'second'] });
const discovered = { origin: 'source', bookUrl: '/book' };
explore.onExploreResultReady('first', discovered);
assert.equal(explore.claimExploreResultArrival('first', discovered), 0, 'first discovery admission animates');
explore.onExploreResultReady('first', discovered);
assert.equal(explore.claimExploreResultArrival('first', discovered), -1, 'metadata, remounts and cover updates cannot replay discovery');
explore.selectedIndex = 1;
explore.exploreBooksPageKey = 'second';
now += 400;
explore.onExploreResultReady('', discovered);
assert.equal(explore.claimExploreResultArrival('second', discovered), 0, 'list and grid share the current category identity');
assert.equal(explore.claimExploreResultArrival('', discovered), -1, 'switching layouts cannot replay');
explore.selectedIndex = 0;
explore.exploreBooksPageKey = 'first';
explore.onExploreResultReady('first', discovered);
assert.equal(explore.claimExploreResultArrival('first', discovered), -1, 'returning to a cached category remains still');
const background = { origin: 'source', bookUrl: '/background' };
explore.onExploreResultReady('second', background);
explore.selectedIndex = 1;
explore.onExploreResultReady('second', background);
assert.equal(explore.claimExploreResultArrival('second', background), -1, 'offscreen preview completion cannot animate on return');
explore.isActive = false;
const hidden = { origin: 'source', bookUrl: '/hidden' };
explore.onExploreResultReady('second', hidden);
explore.isActive = true;
explore.onExploreResultReady('second', hidden);
assert.equal(explore.claimExploreResultArrival('second', hidden), -1, 'background discovery results remain still');

console.log('PASS home motion: retained shelf, native tab routing, search/discovery arrivals, category identity, recycling, background results and bounded wide-screen stagger');

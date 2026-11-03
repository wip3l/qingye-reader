import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../entry/src/main/ets/core/reader/ReaderV2RenderNode.ets', import.meta.url), 'utf8');
const frames = []; let nodes = 0;
class Frame { update(page) { this.page = page; } }
const Controller = vm.runInNewContext(stripTypeScriptTypes(source.slice(source.indexOf('export class ReaderV2PageNodeController'))
  .replace('export class', 'class')) + '\nReaderV2PageNodeController', {
  ReaderV2PageFrameNode: Frame, ReaderRenderFrame: { wait: () => new Promise(resolve => frames.push(resolve)) },
  NodeController: class { rebuild() { this.makeNode({}); } },
});
Controller.onNodeCreated = () => nodes++;
async function render() { for (const complete of frames.splice(0)) complete(); await Promise.resolve(); }
const controller = new Controller();
const first = {}, second = {}, third = {};
controller.bindPageToHost(first, 'page-1'); controller.makeNode({});
assert.equal(nodes, 1);
controller.bindPageToHost(second, 'page-2');
assert.equal(nodes, 1, 'binding a new host must not rebuild the outgoing native node');
controller.makeNode({}); await render();
assert.equal(nodes, 2, 'a normal page handoff creates exactly one node');
assert.equal(controller.node.page, second);
controller.bindPageToHost(second, 'page-2'); await render(); assert.equal(nodes, 2);
controller.bindPageToHost(third, 'page-3'); await render();
assert.equal(nodes, 3, 'retained-container compatibility failure still forces one rebuild');
assert.equal(controller.node.page, third);
controller.bindPageToHost(first, 'stale'); controller.updatePage(null); await render();
assert.equal(nodes, 4, 'clearing native content cancels the stale pending repair');
assert.equal(controller.node.page, null);
controller.bindPageToHost(first, 'superseded'); controller.bindPageToHost(second, 'latest'); await render();
assert.equal(nodes, 5, 'only the latest binding can repair a retained host');
assert.equal(controller.node.page, second);
controller.updatePage(third, true); assert.equal(nodes, 6, 'explicit forced refresh keeps its legacy repair');
assert.equal(controller.node.page, third);
const readerSource = fs.readFileSync(new URL('../entry/src/main/ets/pages/ReadBook.ets', import.meta.url), 'utf8');
const bodyStart = readerSource.indexOf('  readerKeyedCurrentPageLayer(');
const body = readerSource.slice(bodyStart, readerSource.indexOf('\n  }', bodyStart) + 4);
assert.match(body, /ForEach\(this\.currentReaderV2ChapterSurfaceKeys\(this\.pageRenderVersion\)/,
  'the native body keeps its page/pending/reflow key');
assert.match(body, /readerCurrentPageLayer\(this\.pageRenderVersion, this\.visibleCurrentPageText\(\),\s*this\.ttsHighlightRenderVersion, controllerRole\)/);
assert.doesNotMatch(body, /readerSimulationPaperBackground/, 'paper is outside the per-page remount');
for (const surface of ['readerCurrentPageSurface', 'readerCurrentPageSurfaceAlternate']) {
  const start = readerSource.indexOf(`  ${surface}(`);
  const declaration = readerSource.slice(start, readerSource.indexOf('\n  }', start) + 4);
  assert.match(declaration, /readerKeyedCurrentPageLayer/);
  assert.match(declaration, /readerSimulationPaperBackground/);
}
const incomingStart = readerSource.indexOf('  readerIncomingPageSurfaceKeys(');
const incomingMethod = readerSource.slice(incomingStart, readerSource.indexOf('\n  }', incomingStart) + 4);
const IncomingIdentity = vm.runInNewContext(stripTypeScriptTypes(`class IncomingIdentity { ${incomingMethod} }`) + '\nIncomingIdentity');
const incoming = new IncomingIdentity();
Object.assign(incoming, { pageTurnIncomingChapterIndex: 3, pageTurnIncomingPageIndex: 1,
  pageTurnIncomingRenderVersion: 1, readerV2SurfaceGeneration: 0, pageTurnIncomingDocumentSource: 'chapter-a',
  isLandscapeDoublePageActive: () => false, readerV2Page: () => ({}) });
const key = () => incoming.readerIncomingPageSurfaceKeys()[0];
let previous = key();
for (let turn = 0; turn < 80; turn++) {
  incoming.pageTurnIncomingChapterIndex = Math.floor(turn / 8);
  incoming.pageTurnIncomingPageIndex = turn % 8;
  incoming.pageTurnIncomingRenderVersion++;
  assert.notEqual(key(), previous, 'queued turns need an independent destination host');
  previous = key();
  for (let frame = 0; frame < 20; frame++) {
    incoming.pageSlideOffsetX = -frame * 10;
    assert.equal(key(), previous, 'drag frames must retain the destination host');
  }
}
incoming.readerV2Page = () => null;
const pending = key();
incoming.readerV2Page = () => ({});
assert.notEqual(key(), pending, 'publication of a measured destination remounts a loading leaf');
incoming.isLandscapeDoublePageActive = () => true;
incoming.readerV2Page = (_chapter, page) => page === incoming.pageTurnIncomingPageIndex ? {} : null;
const halfPending = key();
incoming.readerV2Page = () => ({});
assert.notEqual(key(), halfPending, 'the second page of a spread can become ready independently');
previous = key(); incoming.readerV2SurfaceGeneration++;
assert.notEqual(key(), previous, 'theme/typography invalidation refreshes the destination');
const incomingLayerStart = readerSource.indexOf('  readerIncomingPageLayer(');
const incomingLayer = readerSource.slice(incomingLayerStart, readerSource.indexOf('\n  }', incomingLayerStart) + 4);
assert.match(incomingLayer, /ForEach\(this\.readerIncomingPageSurfaceKeys\(this\.pageRenderVersion\)/,
  'private layout publication must reevaluate pending-to-ready destination keys');
assert.match(incomingLayer, /readerIncomingPageContent\(controllerRole\)/);
const simulationStart = readerSource.indexOf('  readerSimulationPageTurnSurface(');
const simulation = readerSource.slice(simulationStart, readerSource.indexOf('\n  }', simulationStart) + 4);
assert.match(simulation, /ForEach\(this\.readerIncomingPageSurfaceKeys\(this\.pageRenderVersion\)/,
  'double-page capture and its visible destination must advance together');
console.log('PASS: native host fallback, queued destination identity, stable drag frames and pending/spread publication');

const currentStart = readerSource.indexOf('  currentReaderV2ChapterSurfaceKeys(');
const currentMethod = readerSource.slice(currentStart, readerSource.indexOf('\n  }', currentStart) + 4);
const CurrentIdentity = vm.runInNewContext(stripTypeScriptTypes(`class CurrentIdentity { ${currentMethod} }`) + '\nCurrentIdentity');
const current = new CurrentIdentity();
Object.assign(current, { currentChapterIndex: 0, currentPageIndex: 0, readerV2SurfaceGeneration: 0,
  pagedContentText: 'first chapter', isLandscapeDoublePageActive: () => true, readerV2Page: () => null });
const pendingCurrent = current.currentReaderV2ChapterSurfaceKeys()[0];
current.readerV2Page = (_chapter, page) => page === 0 ? {} : null;
const firstReady = current.currentReaderV2ChapterSurfaceKeys()[0];
assert.notEqual(firstReady, pendingCurrent, 'initial chapter publication replaces the loading host without a turn');
current.readerV2Page = () => ({});
assert.notEqual(current.currentReaderV2ChapterSurfaceKeys()[0], firstReady, 'late right leaf updates the settled spread');
const stableCurrent = current.currentReaderV2ChapterSurfaceKeys()[0];
current.pageRenderVersion++;
assert.equal(current.currentReaderV2ChapterSurfaceKeys()[0], stableCurrent, 'background publication does not remount measured text');

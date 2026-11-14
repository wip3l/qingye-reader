// 编辑器包读写的往返测试：手写包、应用导出的方案包、带错误的包，以及导出后再用应用格式层解码。
// npm test（node --experimental-strip-types --test test/）
import assert from 'node:assert/strict';
import test from 'node:test';
import { zipSync, strToU8, strFromU8 } from 'fflate';
import { createHash } from 'node:crypto';
import * as io from '../src/core/packageIo.ts';

const json = (value) => strToU8(JSON.stringify(value));

function png(width, height) {
  const b = new Uint8Array(33);
  b.set([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  new DataView(b.buffer).setUint32(16, width);
  new DataView(b.buffer).setUint32(20, height);
  return b;
}

function jpg(width, height, seed = 0) {
  return new Uint8Array([0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, seed, 0xFF, 0xC0, 0, 17, 8, height >> 8, height & 255, width >> 8, width & 255, 3, 0, 0]);
}

const svg = (body = '<path d="M0 0h24v24H0z"/>', box = '0 0 24 24') =>
  strToU8(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="${box}">${body}</svg>`);

function handWritten() {
  return {
    'night-garden/manifest.json': json({
      format: 'qytheme', formatVersion: 2, packageId: 'night-garden', name: '夜花园', author: '小明', version: '1.0',
      baseTheme: 'plain-default', requires: ['custom-scheme-v1', 'theme-parts-v1']
    }),
    'night-garden/theme.json': json({
      parts: {
        light: {
          colors: { pageColor: '#F6F3EC', accentColor: '#2F6B5F' },
          reader: { backgroundColor: '#FBF7EE', textColor: '#2F2A22', contentTone: 'light', backgroundMode: 'ornaments',
            leading: 'assets/tl.svg', trailing: 'assets/br.svg' },
          emphasis: { mode: 'bubble', color: '#DDEFE8', textColor: '#1F4A40' }
        },
        dark: { reader: { backgroundColor: '#141917', backgroundMode: 'image', image: 'assets/dark.jpg', imageFit: 'contain' } },
        ttsPanel: { light: { artwork: 'assets/tts.svg', skyColor: '#D9EDE5', surfaceColor: '#F4F7F5', glowColor: '#2E2F6B5F' } },
        navigation: { bookshelf: 'assets/n1.svg', explore: 'assets/n2.svg', search: 'assets/n3.svg', mine: 'assets/n4.svg' },
        book: { covers: ['assets/c1.jpg', 'assets/c2.png'], shelfFrame: 'assets/frame.svg' },
        startup: { light: { image: 'assets/start.jpg', title: '夜花园', subtitle: '月下翻页' } },
        bubble: { cap: 'assets/cap.svg' },
        homeBackdrop: { light: 'assets/home.jpg' },
        logo: 'assets/logo.svg',
        radius: { card: 14, button: 22 }
      }
    }),
    'night-garden/assets/tl.svg': svg('<circle cx="9" cy="9" r="9"/>', '0 0 480 480'),
    'night-garden/assets/br.svg': svg('<circle cx="20" cy="20" r="9"/>', '0 0 480 480'),
    'night-garden/assets/dark.jpg': jpg(1080, 2340),
    'night-garden/assets/tts.svg': svg('<rect width="720" height="520"/>', '0 0 720 520'),
    'night-garden/assets/n1.svg': svg(), 'night-garden/assets/n2.svg': svg('<path d="M1 1h2v2z"/>'),
    'night-garden/assets/n3.svg': svg('<path d="M2 2h2v2z"/>'), 'night-garden/assets/n4.svg': svg('<path d="M3 3h2v2z"/>'),
    'night-garden/assets/c1.jpg': jpg(450, 660, 1), 'night-garden/assets/c2.png': png(450, 660),
    'night-garden/assets/frame.svg': svg('<rect x="2" y="2" width="446" height="656" fill="none" stroke="#000"/>', '0 0 450 660'),
    'night-garden/assets/start.jpg': jpg(841, 1870, 2),
    'night-garden/assets/home.jpg': jpg(1080, 1350, 3),
    'night-garden/assets/cap.svg': svg('<circle cx="8" cy="8" r="8"/>', '0 0 16 16'),
    'night-garden/assets/logo.svg': svg('<circle cx="32" cy="32" r="30"/>', '0 0 64 64')
  };
}

test('image sizes come from file headers', () => {
  assert.deepEqual(io.imageSize(png(450, 660), 'png'), { width: 450, height: 660 });
  assert.deepEqual(io.imageSize(jpg(841, 1870), 'jpg'), { width: 841, height: 1870 });
  assert.deepEqual(io.imageSize(svg('', '0 0 720 520'), 'svg'), { width: 720, height: 520 });
});

test('a hand-written package opens strictly and survives export', async () => {
  const files = io.readZip(zipSync(handWritten()));
  const loaded = await io.loadProject(files);
  assert.deepEqual(loaded.problems, []);
  const p = loaded.project;
  assert.equal(p.manifest.packageId, 'night-garden');
  assert.equal(p.parts.light.reader.leading, 'assets/tl.svg');
  assert.deepEqual(p.parts.book.covers, ['assets/c1.jpg', 'assets/c2.png']);
  assert.equal(p.parts.homeBackdrop.light, 'assets/home.jpg');
  assert.equal(p.assets.get('assets/c2.png').width, 450);
  assert.equal(p.assets.size, 15);

  const zip = await io.exportZip(p);
  const again = await io.loadProject(io.readZip(zip));
  assert.deepEqual(again.problems, []);
  assert.deepEqual(io.normalizedParts(again.project.parts), io.normalizedParts(p.parts));
  const manifest = JSON.parse(strFromU8(io.readZip(zip).get('manifest.json')));
  assert.deepEqual(manifest.requires, ['custom-scheme-v1', 'theme-parts-v1']);
  assert.equal(manifest.assets.length, 15);
  assert.equal(manifest.assets[0].sha256.length, 64);
});

test('switching background mode drops the other mode\'s images from the export', async () => {
  const { project } = await io.loadProject(io.readZip(zipSync(handWritten())));
  project.parts.light.reader.backgroundMode = 'none';
  const files = await io.exportFiles(project);
  assert.equal(files.has('assets/tl.svg'), false);
  const theme = JSON.parse(strFromU8(files.get('theme.json')));
  assert.equal(theme.parts.light.reader.leading, undefined);
  assert.equal(theme.parts.light.reader.backgroundMode, 'none');
});

test('display areas for animated images survive export and follow their image', async () => {
  const entries = handWritten();
  const theme = JSON.parse(strFromU8(entries['night-garden/theme.json']));
  const area = (image) => ({ image, x: 10, y: 20, width: 300, height: 440, imageWidth: 450, imageHeight: 660 });
  theme.parts.book.coverCrops = [area('assets/c2.png')];
  theme.parts.book.shelfFolder = 'assets/c1.jpg';
  theme.parts.book.shelfFolderCrop = area('assets/c1.jpg');
  theme.parts.homeBackdrop.lightCrop = { image: 'assets/home.jpg', x: 0, y: 100, width: 1080, height: 1250, imageWidth: 1080, imageHeight: 1350 };
  entries['night-garden/theme.json'] = json(theme);
  const { project, problems } = await io.loadProject(io.readZip(zipSync(entries)));
  assert.deepEqual(problems, []);
  assert.deepEqual(project.parts.book.coverCrops, [area('assets/c2.png')]);
  assert.equal(project.parts.homeBackdrop.lightCrop.y, 100);

  let parts = JSON.parse(strFromU8((await io.exportFiles(project)).get('theme.json'))).parts;
  assert.deepEqual(parts.book.coverCrops, [area('assets/c2.png')]);
  assert.deepEqual(parts.book.shelfFolderCrop, area('assets/c1.jpg'));
  assert.equal(parts.homeBackdrop.lightCrop.height, 1250);

  // 换掉或删掉那张图后，它的区域不再写进包，也不会把旧图带进去。
  project.parts.book.covers = ['assets/c1.jpg'];
  project.parts.book.shelfFolder = 'assets/start.jpg';
  project.parts.homeBackdrop.light = 'assets/start.jpg';
  const files = await io.exportFiles(project);
  parts = JSON.parse(strFromU8(files.get('theme.json'))).parts;
  assert.equal(parts.book.coverCrops, undefined);
  assert.equal(parts.book.shelfFolderCrop, undefined);
  assert.equal(parts.homeBackdrop.lightCrop, undefined);
  assert.equal(files.has('assets/c2.png'), false);
});

test('dark covers are a separate optional list with their own display areas', async () => {
  const entries = handWritten();
  const theme = JSON.parse(strFromU8(entries['night-garden/theme.json']));
  const area = (image) => ({ image, x: 10, y: 20, width: 300, height: 440, imageWidth: 450, imageHeight: 660 });
  theme.parts.book.coversDark = ['assets/d1.jpg', 'assets/c2.png'];
  theme.parts.book.coverCropsDark = [area('assets/d1.jpg')];
  entries['night-garden/theme.json'] = json(theme);
  entries['night-garden/assets/d1.jpg'] = jpg(450, 660, 9);
  const { project, problems } = await io.loadProject(io.readZip(zipSync(entries)));
  assert.deepEqual(problems, []);
  assert.deepEqual(project.parts.book.covers, ['assets/c1.jpg', 'assets/c2.png']);
  assert.deepEqual(project.parts.book.coversDark, ['assets/d1.jpg', 'assets/c2.png']);

  let files = await io.exportFiles(project);
  let parts = JSON.parse(strFromU8(files.get('theme.json'))).parts;
  assert.deepEqual(parts.book.coversDark, ['assets/d1.jpg', 'assets/c2.png']);
  assert.deepEqual(parts.book.coverCropsDark, [area('assets/d1.jpg')]);
  assert.equal(files.has('assets/d1.jpg'), true);

  // 删掉深色那张图后，它的区域和文件都不再进包；清空深色那套就回到老主题包的写法。
  project.parts.book.coversDark = ['assets/c2.png'];
  files = await io.exportFiles(project);
  parts = JSON.parse(strFromU8(files.get('theme.json'))).parts;
  assert.equal(parts.book.coverCropsDark, undefined);
  assert.equal(files.has('assets/d1.jpg'), false);
  project.parts.book.coversDark = [];
  parts = JSON.parse(strFromU8((await io.exportFiles(project)).get('theme.json'))).parts;
  assert.equal(parts.book.coversDark, undefined);
  assert.deepEqual(parts.book.covers, ['assets/c1.jpg', 'assets/c2.png']);
});

test('a package with only dark covers is written as plain covers for older apps', async () => {
  const { project } = await io.loadProject(io.readZip(zipSync(handWritten())));
  project.parts.book.coversDark = project.parts.book.covers;
  project.parts.book.covers = [];
  project.parts.book.shelfFolderDark = 'assets/start.jpg';
  const parts = JSON.parse(strFromU8((await io.exportFiles(project)).get('theme.json'))).parts;
  assert.deepEqual(parts.book.covers, ['assets/c1.jpg', 'assets/c2.png']);
  assert.equal(parts.book.coversDark, undefined);
  assert.equal(parts.book.shelfFolder, 'assets/start.jpg');
  assert.equal(parts.book.shelfFolderDark, undefined);
});

test('more than 8 covers export with the feature flag older apps need to see', async () => {
  const entries = handWritten();
  for (let i = 0; i < 16; i++) entries[`night-garden/assets/k${i}.jpg`] = jpg(450, 660, 20 + i);
  const { project } = await io.loadProject(io.readZip(zipSync(entries)));
  const requiresOf = async () => JSON.parse(strFromU8((await io.exportFiles(project)).get('manifest.json'))).requires;
  assert.equal(io.MAX_COVERS, 16);
  // 8 张以内和以前一样，不多声明；深色那套旧版本应用不读，放满也不用声明。
  project.parts.book.covers = Array.from({ length: 8 }, (_, i) => `assets/k${i}.jpg`);
  project.parts.book.coversDark = Array.from({ length: 16 }, (_, i) => `assets/k${i}.jpg`);
  assert.equal((await requiresOf()).includes('book-covers-16-v1'), false);
  project.parts.book.covers = Array.from({ length: 16 }, (_, i) => `assets/k${i}.jpg`);
  assert.equal((await requiresOf()).includes('book-covers-16-v1'), true);
  const again = await io.loadProject(io.readZip(await io.exportZip(project)));
  assert.deepEqual(again.problems, []);
  assert.equal(again.project.parts.book.covers.length, 16);
  // 只填了深色那套时它会写成 covers，超过 8 张同样要声明。
  project.parts.book.covers = [];
  assert.equal((await requiresOf()).includes('book-covers-16-v1'), true);
  // 一套超过 16 张导出时由格式层拦下。
  project.parts.book.covers = Array.from({ length: 17 }, (_, i) => `assets/k${i % 16}.jpg`);
  await assert.rejects(io.exportFiles(project).then((files) => io.verifyFiles(files)), /最多 16 张/);
});

test('the dark folder illustration is optional and keeps its own display area', async () => {
  const entries = handWritten();
  const theme = JSON.parse(strFromU8(entries['night-garden/theme.json']));
  const area = (image) => ({ image, x: 10, y: 20, width: 300, height: 440, imageWidth: 450, imageHeight: 660 });
  theme.parts.book.shelfFolder = 'assets/c1.jpg';
  theme.parts.book.shelfFolderDark = 'assets/fd.jpg';
  theme.parts.book.shelfFolderCropDark = area('assets/fd.jpg');
  entries['night-garden/theme.json'] = json(theme);
  entries['night-garden/assets/fd.jpg'] = jpg(450, 660, 8);
  const { project, problems } = await io.loadProject(io.readZip(zipSync(entries)));
  assert.deepEqual(problems, []);
  assert.equal(project.parts.book.shelfFolderDark, 'assets/fd.jpg');

  let files = await io.exportFiles(project);
  let parts = JSON.parse(strFromU8(files.get('theme.json'))).parts;
  assert.equal(parts.book.shelfFolder, 'assets/c1.jpg');
  assert.equal(parts.book.shelfFolderDark, 'assets/fd.jpg');
  assert.deepEqual(parts.book.shelfFolderCropDark, area('assets/fd.jpg'));

  // 换掉深色那张后旧区域不再写进包；移除后回到老主题包的写法，文件也不再进包。
  project.parts.book.shelfFolderDark = 'assets/c2.png';
  parts = JSON.parse(strFromU8((await io.exportFiles(project)).get('theme.json'))).parts;
  assert.equal(parts.book.shelfFolderCropDark, undefined);
  project.parts.book.shelfFolderDark = '';
  files = await io.exportFiles(project);
  parts = JSON.parse(strFromU8(files.get('theme.json'))).parts;
  assert.equal(parts.book.shelfFolderDark, undefined);
  assert.equal(files.has('assets/fd.jpg'), false);
});

test('shelf layouts can each carry their own backdrop next to the shared one', async () => {
  const entries = handWritten();
  const theme = JSON.parse(strFromU8(entries['night-garden/theme.json']));
  const area = (image) => ({ image, x: 0, y: 100, width: 1080, height: 1250, imageWidth: 1080, imageHeight: 1350 });
  theme.parts.shelfBackdrop = {
    companion: { light: 'assets/sc.jpg', dark: 'assets/home.jpg', lightCrop: area('assets/sc.jpg') },
    compact: { dark: 'assets/sc.jpg' }
  };
  entries['night-garden/theme.json'] = json(theme);
  entries['night-garden/assets/sc.jpg'] = jpg(1080, 1350, 7);
  const { project, problems } = await io.loadProject(io.readZip(zipSync(entries)));
  assert.deepEqual(problems, []);
  assert.equal(project.parts.shelfBackdrop.companion.light, 'assets/sc.jpg');
  assert.equal(project.parts.shelfBackdrop.compact.dark, 'assets/sc.jpg');
  assert.equal(project.parts.homeBackdrop.light, 'assets/home.jpg');

  let files = await io.exportFiles(project);
  let parts = JSON.parse(strFromU8(files.get('theme.json'))).parts;
  assert.deepEqual(parts.shelfBackdrop.companion, { light: 'assets/sc.jpg', dark: 'assets/home.jpg', lightCrop: area('assets/sc.jpg') });
  assert.deepEqual(parts.shelfBackdrop.compact, { dark: 'assets/sc.jpg' });
  assert.equal(parts.homeBackdrop.light, 'assets/home.jpg', 'the shared backdrop stays where older apps read it');

  // 只配布局专属图、不配通用背景也能导出；换图后旧区域不再写进包，全部移除后这一节和文件都不进包。
  project.parts.homeBackdrop = {};
  project.parts.shelfBackdrop.companion.light = 'assets/start.jpg';
  files = await io.exportFiles(project);
  parts = JSON.parse(strFromU8(files.get('theme.json'))).parts;
  assert.equal(parts.homeBackdrop, undefined);
  assert.equal(parts.shelfBackdrop.companion.lightCrop, undefined);
  project.parts.shelfBackdrop = { companion: { light: '', dark: '' }, compact: {} };
  files = await io.exportFiles(project);
  parts = JSON.parse(strFromU8(files.get('theme.json'))).parts;
  assert.equal(parts.shelfBackdrop, undefined);
  assert.equal(files.has('assets/sc.jpg'), false);
});

test('a display area outside its image is rejected like the app would', async () => {
  const entries = handWritten();
  const theme = JSON.parse(strFromU8(entries['night-garden/theme.json']));
  theme.parts.book.coverCrops = [{ image: 'assets/c2.png', x: 300, y: 0, width: 300, height: 440, imageWidth: 450, imageHeight: 660 }];
  entries['night-garden/theme.json'] = json(theme);
  const { problems } = await io.loadProject(io.readZip(zipSync(entries)));
  assert.equal(problems.some((problem) => String(problem.message || problem).includes('coverCrops')), true);
});

test('navigation takes bitmap icons, selected icons and an icons-only bar', async () => {
  const entries = handWritten();
  const theme = JSON.parse(strFromU8(entries['night-garden/theme.json']));
  theme.parts.navigation.explore = 'assets/n2.png';
  theme.parts.navigation.bookshelfSelected = 'assets/n1on.png';
  theme.parts.navigation.labels = 'hidden';
  entries['night-garden/theme.json'] = json(theme);
  entries['night-garden/assets/n2.png'] = png(96, 96);
  entries['night-garden/assets/n1on.png'] = png(96, 97);
  const { project, problems } = await io.loadProject(io.readZip(zipSync(entries)));
  assert.deepEqual(problems, []);
  assert.equal(project.parts.navigation.explore, 'assets/n2.png');
  assert.equal(project.parts.navigation.bookshelfSelected, 'assets/n1on.png');
  assert.equal(project.parts.navigation.labels, 'hidden');

  const files = await io.exportFiles(project);
  assert.equal(files.has('assets/n1on.png'), true);
  const nav = JSON.parse(strFromU8(files.get('theme.json'))).parts.navigation;
  assert.equal(nav.bookshelfSelected, 'assets/n1on.png');
  assert.equal(nav.labels, 'hidden');
  assert.equal(nav.exploreSelected, undefined);
});

test('navigation keeps the optional listen and footprint tab icons', async () => {
  const entries = handWritten();
  const theme = JSON.parse(strFromU8(entries['night-garden/theme.json']));
  theme.parts.navigation.listen = 'assets/n5.svg';
  theme.parts.navigation.footprintSelected = 'assets/n6.png';
  entries['night-garden/theme.json'] = json(theme);
  entries['night-garden/assets/n5.svg'] = strToU8('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M4 4h16v16H4z"/></svg>');
  entries['night-garden/assets/n6.png'] = png(96, 96);
  const { project, problems } = await io.loadProject(io.readZip(zipSync(entries)));
  assert.deepEqual(problems, []);
  assert.equal(project.parts.navigation.listen, 'assets/n5.svg');
  assert.equal(project.parts.navigation.footprintSelected, 'assets/n6.png');

  const files = await io.exportFiles(project);
  assert.equal(files.has('assets/n5.svg'), true);
  assert.equal(files.has('assets/n6.png'), true);
  const nav = JSON.parse(strFromU8(files.get('theme.json'))).parts.navigation;
  assert.equal(nav.listen, 'assets/n5.svg');
  assert.equal(nav.footprintSelected, 'assets/n6.png');
  assert.equal(nav.footprint, undefined);
});

test('export fills the legacy search icon from explore for older apps', async () => {
  const { project } = await io.loadProject(io.readZip(zipSync(handWritten())));
  project.parts.navigation.search = '';
  const files = await io.exportFiles(project);
  const nav = JSON.parse(strFromU8(files.get('theme.json'))).parts.navigation;
  assert.equal(nav.search, nav.explore);
  assert.equal(files.has('assets/n3.svg'), false);
});

test('export reports the same errors the app would', async () => {
  const { project } = await io.loadProject(io.readZip(zipSync(handWritten())));
  project.parts.navigation.mine = '';
  await assert.rejects(io.exportFiles(project), /parts\.navigation 需要 bookshelf、explore、mine/);
  project.parts.navigation.mine = 'assets/n4.svg';
  // 只有一角的角饰照样能导出，清单自动声明 reader-single-corner-v1；两角都空才报错。
  project.parts.light.reader.trailing = '';
  project.parts.light.reader.leadingScale = 1.4;
  project.parts.light.reader.trailingScale = 1;
  const single = await io.exportFiles(project);
  assert.ok(JSON.parse(strFromU8(single.get('manifest.json'))).requires.includes('reader-single-corner-v1'));
  const singleReader = JSON.parse(strFromU8(single.get('theme.json'))).parts.light.reader;
  assert.equal(singleReader.leadingScale, 1.4);
  assert.equal('trailingScale' in singleReader, false);
  const leading = project.parts.light.reader.leading;
  project.parts.light.reader.leading = '';
  await assert.rejects(io.exportFiles(project), /至少要有 leading 或 trailing/);
  project.parts.light.reader.leading = leading;
  project.parts.light.reader.trailing = 'assets/br.svg';
  delete project.parts.light.reader.leadingScale;
  delete project.parts.light.reader.trailingScale;
  const both = await io.exportFiles(project);
  assert.ok(!JSON.parse(strFromU8(both.get('manifest.json'))).requires.includes('reader-single-corner-v1'));
  project.manifest.packageId = 'bad id';
  await assert.rejects(io.exportFiles(project), /packageId/);
});

test('a broken package still opens so it can be fixed', async () => {
  const entries = handWritten();
  const theme = JSON.parse(strFromU8(entries['night-garden/theme.json']));
  theme.parts.light.colors.pageColor = 'red';
  entries['night-garden/theme.json'] = json(theme);
  const loaded = await io.loadProject(io.readZip(zipSync(entries)));
  assert.equal(loaded.problems.length, 1);
  assert.match(loaded.problems[0], /pageColor 不是合法的颜色/);
  assert.equal(loaded.project.parts.light.reader.trailing, 'assets/br.svg');
  loaded.project.parts.light.colors.pageColor = '#F6F3EC';
  await io.exportFiles(loaded.project);
});

test('an app-exported scheme keeps settings, layout, emphasis and fonts', async () => {
  const startup = jpg(841, 1870, 7);
  const font = new Uint8Array([0x00, 0x01, 0x00, 0x00, 1, 2, 3, 4, 5, 6, 7, 8]);
  const sha = (b) => createHash('sha256').update(b).digest('hex');
  const startupId = sha(startup).substring(0, 24);
  const fontId = sha(font).substring(0, 24);
  const entries = {
    'manifest.json': json({
      format: 'qytheme', formatVersion: 1, packageId: '', name: '我的方案', author: '', exportedAt: 1, appVersion: '4.4',
      requires: ['custom-scheme-v1', 'reader-layout-v1', 'emphasis-rules-v3', 'fonts-v1', 'scheme-overrides-v1'],
      assets: [
        { id: startupId, path: `assets/${startupId}.jpg`, kind: 'image', size: startup.length, sha256: sha(startup) },
        { id: fontId, path: `assets/${fontId}.ttf`, kind: 'font', size: font.length, sha256: sha(font), name: '霞鹜' }
      ]
    }),
    'theme.json': json({
      settings: { customBaseThemeId: 'warm-paper', customLightStartupImagePath: `qytheme-asset:${startupId}`,
        customLightSources: { paletteThemeId: 'forest-mist' }, customLightPalette: { pageColor: '#FFFFFF' } },
      layout: { fontSize: 21, lineHeight: 14, bodyFontFamily: 'lxgw' },
      emphasis: { enabled: true, rules: [{ id: 1, pattern: '“[^”]*”' }] },
      fonts: [{ family: 'lxgw', name: '霞鹜', assetId: fontId }]
    }),
    [`assets/${startupId}.jpg`]: startup,
    [`assets/${fontId}.ttf`]: font
  };
  const loaded = await io.loadProject(io.readZip(zipSync(entries)));
  assert.deepEqual(loaded.problems, []);
  const p = loaded.project;
  assert.equal(p.sourceFormatVersion, 1);
  assert.match(p.manifest.packageId, /^custom-[0-9a-f]{8}$/);
  assert.equal(p.settings.customLightStartupImagePath, `assets/${startupId}.jpg`);
  assert.equal(p.fonts[0].assetPath, `assets/${fontId}.ttf`);

  const files = await io.exportFiles(p);
  const manifest = JSON.parse(strFromU8(files.get('manifest.json')));
  assert.equal(manifest.formatVersion, 2);
  assert.deepEqual(manifest.requires, ['custom-scheme-v1', 'reader-layout-v1', 'emphasis-rules-v3', 'fonts-v1', 'scheme-overrides-v1']);
  const verified = await io.verifyFiles(files);
  assert.equal(JSON.parse(verified.theme.layoutJson).fontSize, 21);
  assert.equal(JSON.parse(verified.theme.settingsJson).customLightPalette.pageColor, '#FFFFFF');
  assert.equal(verified.theme.fonts[0].family, 'lxgw');
  assert.ok(verified.theme.fonts[0].assetId);
});

test('pack:self in settings follows a changed packageId', async () => {
  const entries = handWritten();
  const theme = JSON.parse(strFromU8(entries['night-garden/theme.json']));
  theme.settings = { customBaseThemeId: 'pack:self', customLightSources: { readerThemeId: 'pack:self' },
    customLightReaderBackgroundAssetId: 'pack:self:light' };
  entries['night-garden/theme.json'] = json(theme);
  entries['night-garden/manifest.json'] = json({ ...JSON.parse(strFromU8(entries['night-garden/manifest.json'])),
    requires: ['custom-scheme-v1', 'theme-parts-v1'] });
  const { project, problems } = await io.loadProject(io.readZip(zipSync(entries)));
  assert.deepEqual(problems, []);
  assert.equal(project.settings.customBaseThemeId, 'pack:self');
  project.manifest.packageId = 'night-garden-2';
  const verified = await io.verifyFiles(await io.exportFiles(project));
  const settings = JSON.parse(verified.theme.settingsJson);
  assert.equal(settings.customBaseThemeId, 'pack:night-garden-2');
  assert.equal(settings.customLightReaderBackgroundAssetId, 'pack:night-garden-2:light');
});

test('drafts keep an unfinished project as is', async () => {
  const { project } = await io.loadProject(io.readZip(zipSync(handWritten())));
  project.parts.navigation.mine = '';
  const { project: back, meta } = io.deserializeDraft(io.serializeDraft(project, { file: 'x.qytheme' }));
  assert.equal(meta.file, 'x.qytheme');
  assert.equal(back.parts.navigation.mine, '');
  assert.equal(back.assets.size, project.assets.size);
});

test('uploaded files are renamed to safe asset paths and checked', () => {
  const taken = new Set(['assets/cover.jpg']);
  assert.equal(io.safeAssetPath('Cover.JPEG', 'jpg', (p) => taken.has(p)), 'assets/cover_2.jpg');
  assert.equal(io.safeAssetPath('封面 01.png', 'png', () => false), 'assets/01.png');
  assert.match(String(io.makeAsset('assets/x.svg', strToU8('<svg><script>1</script></svg>'))), /不允许的内容/);
  assert.match(String(io.makeAsset('assets/x.bin', strToU8('hello'))), /认不出/);
});

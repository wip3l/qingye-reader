// 主进程：窗口、文件对话框、读写文件、最近打开、草稿与关闭前确认。包的解析与校验都在渲染进程（src/core）。
const { app, BrowserWindow, dialog, ipcMain, Menu, shell } = require('electron');
const fs = require('node:fs');
const path = require('node:path');

const ICON = app.isPackaged
  ? path.join(process.resourcesPath, 'icon.png')
  : path.join(__dirname, '..', '..', '..', 'AppScope', 'resources', 'base', 'media', 'ic_app_theme_custom.png');
const MAX_FOLDER_BYTES = 200 * 1024 * 1024;
const PACKAGE_FILTERS = [{ name: '轻页主题包', extensions: ['qytheme', 'zip'] }];

let win = null;
let dirty = false;
let allowClose = false;

const userFile = (name) => path.join(app.getPath('userData'), name);

function readRecent() {
  try {
    const list = JSON.parse(fs.readFileSync(userFile('recent.json'), 'utf8'));
    return Array.isArray(list) ? list.filter((item) => item && typeof item.path === 'string') : [];
  } catch (_) {
    return [];
  }
}

function addRecent(filePath, kind) {
  const list = readRecent().filter((item) => item.path !== filePath);
  list.unshift({ path: filePath, kind, name: path.basename(filePath), time: Date.now() });
  fs.mkdirSync(app.getPath('userData'), { recursive: true });
  fs.writeFileSync(userFile('recent.json'), JSON.stringify(list.slice(0, 10)));
}

/** 主题文件夹只读 manifest.json、theme.json 和 assets/ 下一层文件，其余忽略。 */
function readFolder(dir) {
  const files = [];
  let total = 0;
  const take = (rel) => {
    const full = path.join(dir, rel);
    const size = fs.statSync(full).size;
    total += size;
    if (total > MAX_FOLDER_BYTES) throw new Error('文件夹里的素材超过 200 MB，不像是主题包');
    files.push([rel.replace(/\\/g, '/'), new Uint8Array(fs.readFileSync(full))]);
  };
  for (const name of ['manifest.json', 'theme.json']) {
    if (fs.existsSync(path.join(dir, name))) take(name);
  }
  if (!files.length) throw new Error('这个文件夹里没有 manifest.json 和 theme.json');
  const assetsDir = path.join(dir, 'assets');
  if (fs.existsSync(assetsDir) && fs.statSync(assetsDir).isDirectory()) {
    for (const entry of fs.readdirSync(assetsDir, { withFileTypes: true })) {
      if (entry.isFile()) take(path.join('assets', entry.name));
    }
  }
  return files;
}

function readTarget(target) {
  const stat = fs.statSync(target);
  if (stat.isDirectory()) {
    const files = readFolder(target);
    addRecent(target, 'folder');
    return { path: target, name: path.basename(target), kind: 'folder', files };
  }
  if (stat.size > 80 * 1024 * 1024) throw new Error('主题包超过 80 MB，应用无法导入');
  const bytes = new Uint8Array(fs.readFileSync(target));
  addRecent(target, 'zip');
  return { path: target, name: path.basename(target), kind: 'zip', bytes };
}

function wrap(fn) {
  return async (...args) => {
    try {
      return { ok: true, value: await fn(...args) };
    } catch (error) {
      return { ok: false, error: error && error.message ? error.message : String(error) };
    }
  };
}

function uniqueDir(parent, name) {
  let target = path.join(parent, name);
  let n = 2;
  while (fs.existsSync(target)) target = path.join(parent, `${name} (${n++})`);
  return target;
}

function launchFile() {
  const args = process.argv.slice(app.isPackaged ? 1 : 2);
  return args.find((arg) => !arg.startsWith('-') && fs.existsSync(arg)) || null;
}

function createWindow() {
  win = new BrowserWindow({
    width: 1440,
    height: 920,
    minWidth: 1100,
    minHeight: 700,
    title: '轻页主题编辑器',
    icon: fs.existsSync(ICON) ? ICON : undefined,
    backgroundColor: '#E9ECEA',
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true }
  });
  win.loadFile(path.join(__dirname, '..', 'dist', 'renderer', 'index.html'));
  // 冒烟检查：QY_EDITOR_SMOKE_SHOT=<png> 时加载完（先执行 QY_EDITOR_SMOKE_SCRIPT 里的页面脚本）截一张图、
  // 打印渲染进程的报错后退出。
  const shot = process.env.QY_EDITOR_SMOKE_SHOT;
  if (shot) {
    win.webContents.on('console-message', (_event, level, message) => { if (level >= 2) console.error(`[renderer] ${message}`); });
    win.webContents.once('did-finish-load', () => setTimeout(async () => {
      if (process.env.QY_EDITOR_SMOKE_SCRIPT) {
        await win.webContents.executeJavaScript(process.env.QY_EDITOR_SMOKE_SCRIPT);
        await new Promise((resolve) => setTimeout(resolve, 800));
      }
      const image = await win.webContents.capturePage();
      fs.writeFileSync(shot, image.toPNG());
      allowClose = true;
      app.quit();
    }, Number(process.env.QY_EDITOR_SMOKE_DELAY || 2500)));
  }
  win.webContents.setWindowOpenHandler(({ url }) => {
    if (/^https?:/.test(url)) shell.openExternal(url);
    return { action: 'deny' };
  });
  win.webContents.on('will-navigate', (event) => event.preventDefault());
  win.webContents.on('before-input-event', (event, input) => {
    if (input.type === 'keyDown' && input.key === 'F12') win.webContents.toggleDevTools();
  });
  win.on('close', (event) => {
    if (!dirty || allowClose) return;
    const choice = dialog.showMessageBoxSync(win, {
      type: 'question',
      buttons: ['取消', '不保存，直接关闭'],
      defaultId: 0,
      cancelId: 0,
      title: '有未保存的更改',
      message: '当前主题有未保存的更改。',
      detail: '直接关闭会丢掉这些更改。要保留的话先取消，按 Ctrl+S 保存或导出。'
    });
    if (choice === 0) {
      event.preventDefault();
      return;
    }
    try { fs.rmSync(userFile('draft.zip'), { force: true }); } catch (_) { /* 草稿删不掉不影响关闭 */ }
  });
}

ipcMain.handle('open-dialog', wrap(async (_event, folder) => {
  const result = await dialog.showOpenDialog(win, folder
    ? { title: '打开主题文件夹', properties: ['openDirectory'] }
    : { title: '打开主题包', properties: ['openFile'], filters: PACKAGE_FILTERS });
  if (result.canceled || !result.filePaths.length) return null;
  return readTarget(result.filePaths[0]);
}));

ipcMain.handle('open-path', wrap(async (_event, target) => readTarget(target)));

ipcMain.handle('save-file', wrap(async (_event, target, defaultName, bytes) => {
  let file = target;
  if (!file) {
    const last = readRecent().find((item) => item.kind === 'zip');
    const result = await dialog.showSaveDialog(win, {
      title: '保存主题包',
      defaultPath: path.join(last ? path.dirname(last.path) : app.getPath('documents'), defaultName),
      filters: [{ name: '轻页主题包', extensions: ['qytheme'] }]
    });
    if (result.canceled || !result.filePath) return null;
    file = result.filePath;
  }
  const temp = `${file}.saving`;
  fs.writeFileSync(temp, Buffer.from(bytes));
  fs.renameSync(temp, file);
  addRecent(file, 'zip');
  return file;
}));

ipcMain.handle('export-folder', wrap(async (_event, name, files) => {
  const result = await dialog.showOpenDialog(win, { title: '选择导出位置（会在里面新建一个主题文件夹）', properties: ['openDirectory', 'createDirectory'] });
  if (result.canceled || !result.filePaths.length) return null;
  const target = uniqueDir(result.filePaths[0], name);
  for (const [rel, bytes] of files) {
    const full = path.join(target, ...rel.split('/'));
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, Buffer.from(bytes));
  }
  addRecent(target, 'folder');
  return target;
}));

ipcMain.handle('recent', wrap(async () => readRecent().map((item) => ({ ...item, exists: fs.existsSync(item.path) }))));
ipcMain.handle('forget-recent', wrap(async (_event, target) => {
  fs.writeFileSync(userFile('recent.json'), JSON.stringify(readRecent().filter((item) => item.path !== target)));
}));
ipcMain.handle('save-draft', wrap(async (_event, bytes) => {
  fs.mkdirSync(app.getPath('userData'), { recursive: true });
  fs.writeFileSync(userFile('draft.zip'), Buffer.from(bytes));
}));
ipcMain.handle('load-draft', wrap(async () => (fs.existsSync(userFile('draft.zip')) ? new Uint8Array(fs.readFileSync(userFile('draft.zip'))) : null)));
ipcMain.handle('clear-draft', wrap(async () => fs.rmSync(userFile('draft.zip'), { force: true })));
ipcMain.handle('launch-file', wrap(async () => launchFile()));
ipcMain.handle('reveal', wrap(async (_event, target) => shell.showItemInFolder(target)));
ipcMain.on('set-dirty', (_event, value) => { dirty = !!value; });
ipcMain.on('set-title', (_event, title) => { if (win) win.setTitle(String(title)); });

app.whenReady().then(() => {
  Menu.setApplicationMenu(null);
  createWindow();
});
app.on('window-all-closed', () => app.quit());

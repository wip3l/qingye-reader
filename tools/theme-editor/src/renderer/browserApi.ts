// 不在 Electron 里（网页版，或直接用浏览器打开构建产物）时的替身：用文件选择框打开，用下载或系统分享面板保存，
// 草稿放 IndexedDB（带图片的包常超过 localStorage 约 5 MB 的上限）。文件夹的打开与导出需要桌面程序。

function pick(accept: string): Promise<File | null> {
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    // 手机的文件选择框不认识 .qytheme，按后缀过滤会让文件变灰选不了；触屏上不过滤，读进来后再校验。
    if (!window.matchMedia('(pointer: coarse)').matches) input.accept = accept;
    input.onchange = () => resolve(input.files && input.files[0] ? input.files[0] : null);
    input.addEventListener('cancel', () => resolve(null));
    input.click();
  });
}

function download(name: string, bytes: Uint8Array, type = 'application/zip'): void {
  const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}

/** 交给系统分享面板；用户取消返回 false，浏览器不让分享时抛错由调用方改下载。 */
async function share(name: string, bytes: Uint8Array): Promise<boolean> {
  const file = new File([bytes as BlobPart], name, { type: 'application/zip' });
  try {
    await navigator.share({ files: [file], title: name });
    return true;
  } catch (error) {
    if ((error as Error).name === 'AbortError') return false;
    throw error;
  }
}

// ---- 草稿：IndexedDB 一个库一张表一条记录 ----

const DB_NAME = 'qy-theme-editor';
const STORE = 'drafts';
const DRAFT_KEY = 'current';
/** 旧版把草稿以 base64 放在 localStorage，读到后迁走。 */
const LEGACY_KEY = 'qy-theme-editor-draft';

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function withStore<T>(mode: IDBTransactionMode, run: (store: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const db = await openDb();
  try {
    return await new Promise<T>((resolve, reject) => {
      const tx = db.transaction(STORE, mode);
      const req = run(tx.objectStore(STORE));
      tx.oncomplete = () => resolve(req.result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error);
    });
  } finally {
    db.close();
  }
}

function legacyDraft(): Uint8Array | null {
  try {
    const text = localStorage.getItem(LEGACY_KEY);
    if (!text) return null;
    const raw = atob(text);
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    return bytes;
  } catch (_) {
    return null;
  }
}

function dropLegacy(): void {
  try { localStorage.removeItem(LEGACY_KEY); } catch (_) { /* 无存储 */ }
}

const ok = <T>(value: T) => Promise.resolve({ ok: true, value });
const fail = (error: string) => Promise.resolve({ ok: false, error });

let dirty = false;
window.addEventListener('beforeunload', (event) => {
  if (!dirty) return;
  event.preventDefault();
  event.returnValue = '';
});

export function browserApi(): any {
  return {
    async openDialog(folder: boolean) {
      if (folder) return fail('浏览器里打不开文件夹，请用桌面程序');
      const file = await pick('.qytheme,.zip');
      if (!file) return { ok: true, value: null };
      return { ok: true, value: { path: '', name: file.name, kind: 'zip', bytes: new Uint8Array(await file.arrayBuffer()) } };
    },
    openPath: () => fail('浏览器里不能按路径打开'),
    async saveFile(_target: string | null, name: string, bytes: Uint8Array, how?: 'share' | 'download') {
      if (how === 'share') {
        try {
          return { ok: true, value: (await share(name, bytes)) ? name : null };
        } catch (_) {
          // 分享被浏览器拒绝（例如点按授权已过期），改走下载。
        }
      }
      download(name, bytes);
      return { ok: true, value: name };
    },
    exportFolder: () => fail('浏览器里不能导出文件夹，请用桌面程序'),
    async saveImage(name: string, bytes: Uint8Array) {
      download(name, bytes, 'image/png');
      return { ok: true, value: name };
    },
    recent: () => ok([]),
    forgetRecent: () => ok(undefined),
    async saveDraft(bytes: Uint8Array) {
      try {
        await withStore('readwrite', (store) => store.put(bytes, DRAFT_KEY));
        dropLegacy();
      } catch (_) {
        // 存储不可用（隐私模式等）时跳过，草稿只是兜底。
      }
      return { ok: true, value: undefined };
    },
    async loadDraft() {
      try {
        const value = await withStore<any>('readonly', (store) => store.get(DRAFT_KEY));
        if (value instanceof Uint8Array) return { ok: true, value };
        if (value instanceof ArrayBuffer) return { ok: true, value: new Uint8Array(value) };
      } catch (_) {
        // 没有 IndexedDB 时再看旧草稿。
      }
      return { ok: true, value: legacyDraft() };
    },
    async clearDraft() {
      try { await withStore('readwrite', (store) => store.delete(DRAFT_KEY)); } catch (_) { /* 无存储 */ }
      dropLegacy();
      return { ok: true, value: undefined };
    },
    launchFile: () => ok(null),
    reveal: () => ok(undefined),
    setDirty: (value: boolean) => { dirty = !!value; },
    setTitle: (title: string) => { document.title = title; }
  };
}

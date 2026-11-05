// 不在 Electron 里（直接用浏览器打开构建产物）时的替身：用文件选择框打开、用下载保存，草稿放 localStorage。
// 文件夹的打开与导出需要桌面程序。

function pick(accept: string): Promise<File | null> {
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = accept;
    input.onchange = () => resolve(input.files && input.files[0] ? input.files[0] : null);
    input.click();
  });
}

function download(name: string, bytes: Uint8Array): void {
  const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: 'application/zip' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}

const DRAFT_KEY = 'qy-theme-editor-draft';
const ok = <T>(value: T) => Promise.resolve({ ok: true, value });
const fail = (error: string) => Promise.resolve({ ok: false, error });

export function browserApi(): any {
  return {
    async openDialog(folder: boolean) {
      if (folder) return fail('浏览器里打不开文件夹，请用桌面程序');
      const file = await pick('.qytheme,.zip');
      if (!file) return { ok: true, value: null };
      return { ok: true, value: { path: '', name: file.name, kind: 'zip', bytes: new Uint8Array(await file.arrayBuffer()) } };
    },
    openPath: () => fail('浏览器里不能按路径打开'),
    saveFile(_target: string | null, name: string, bytes: Uint8Array) {
      download(name, bytes);
      return ok(name);
    },
    exportFolder: () => fail('浏览器里不能导出文件夹，请用桌面程序'),
    recent: () => ok([]),
    forgetRecent: () => ok(undefined),
    saveDraft(bytes: Uint8Array) {
      try {
        let text = '';
        for (let i = 0; i < bytes.length; i += 0x8000) text += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
        localStorage.setItem(DRAFT_KEY, btoa(text));
      } catch (_) {
        // 草稿太大或存储不可用时跳过。
      }
      return ok(undefined);
    },
    loadDraft() {
      try {
        const text = localStorage.getItem(DRAFT_KEY);
        if (!text) return ok(null);
        const raw = atob(text);
        const bytes = new Uint8Array(raw.length);
        for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
        return ok(bytes);
      } catch (_) {
        return ok(null);
      }
    },
    clearDraft() {
      try { localStorage.removeItem(DRAFT_KEY); } catch (_) { /* 无存储 */ }
      return ok(undefined);
    },
    launchFile: () => ok(null),
    reveal: () => ok(undefined),
    setDirty: () => undefined,
    setTitle: (title: string) => { document.title = title; }
  };
}

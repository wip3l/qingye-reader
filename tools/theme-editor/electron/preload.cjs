// 渲染进程能用的全部系统能力；每个调用返回 { ok, value } 或 { ok: false, error }。
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('editorApi', {
  openDialog: (folder) => ipcRenderer.invoke('open-dialog', !!folder),
  openPath: (target) => ipcRenderer.invoke('open-path', target),
  saveFile: (target, defaultName, bytes) => ipcRenderer.invoke('save-file', target, defaultName, bytes),
  exportFolder: (name, files) => ipcRenderer.invoke('export-folder', name, files),
  recent: () => ipcRenderer.invoke('recent'),
  forgetRecent: (target) => ipcRenderer.invoke('forget-recent', target),
  saveDraft: (bytes) => ipcRenderer.invoke('save-draft', bytes),
  loadDraft: () => ipcRenderer.invoke('load-draft'),
  clearDraft: () => ipcRenderer.invoke('clear-draft'),
  launchFile: () => ipcRenderer.invoke('launch-file'),
  reveal: (target) => ipcRenderer.invoke('reveal', target),
  setDirty: (value) => ipcRenderer.send('set-dirty', value),
  setTitle: (title) => ipcRenderer.send('set-title', title)
});

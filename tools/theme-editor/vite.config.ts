import { defineConfig } from 'vite';

// 渲染进程直接引用主仓 entry/ 下的主题包格式源码，与应用共用一份校验逻辑。
export default defineConfig({
  root: 'src/renderer',
  base: './',
  build: {
    outDir: '../../dist/renderer',
    emptyOutDir: true,
    target: 'chrome130',
    chunkSizeWarningLimit: 2000
  }
});

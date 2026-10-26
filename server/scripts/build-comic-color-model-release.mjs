import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const server = fileURLToPath(new URL('../', import.meta.url));
const stage = path.join(server, 'release/qingye-comic-color-models');
fs.mkdirSync(stage, {recursive:true});
const copy = (source, relative) => {
  const target = path.join(stage, relative);
  fs.mkdirSync(path.dirname(target), {recursive:true}); fs.copyFileSync(source,target);
};
for (const name of ['comicColorModels', 'comicColorModelRoutes', 'cloudObjectStore']) {
  copy(path.join(server, `dist/${name}.js`), `dist/${name}.js`);
  copy(path.join(server, `src/${name}.ts`), `src/${name}.ts`);
}
for (const name of ['patch.mjs','update.sh','with-obs-env.mjs','README.md']) {
  copy(path.join(server, 'scripts/comic-color-model-update', name), `scripts/comic-color-model-update/${name}`);
}
copy(path.join(server,'scripts/publish-comic-color-models.mjs'),'scripts/publish-comic-color-models.mjs');
copy(path.join(server,'scripts/comic-color-model-publish.mjs'),'scripts/comic-color-model-publish.mjs');
copy(path.join(server,'scripts/comic-color-model-update/README.md'),'README.md');
const ai = path.resolve(server, '../harmony-book-ai-engine');
for (const name of ['alac.ms','alac-npu-portrait.ms','alac-npu-landscape.ms']) {
  copy(path.join(ai,'models/comic-colorizer',name),`models/${name}`);
}
for (const name of ['model.json','LICENSE']) copy(path.join(ai,'aiengine/src/main/resources/rawfile/comic-colorizer',name),`models/${name}`);
fs.writeFileSync(path.join(stage,'package.json'),'{"private":true,"type":"module"}\n');
const entries=[];
function scan(folder) {
  for (const item of fs.readdirSync(folder,{withFileTypes:true})) {
    const full=path.join(folder,item.name);
    if(item.isDirectory()) scan(full);
    else if(item.name!=='SHA256SUMS') entries.push(`${createHash('sha256').update(fs.readFileSync(full)).digest('hex')}  ${path.relative(stage,full).replaceAll('\\','/')}`);
  }
}
scan(stage);fs.writeFileSync(path.join(stage,'SHA256SUMS'),entries.sort().join('\n')+'\n');
console.log(stage);

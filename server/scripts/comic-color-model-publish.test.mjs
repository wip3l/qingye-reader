import assert from 'node:assert/strict';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { publishModel, safePublishError } from './comic-color-model-publish.mjs';
import { createObsStore } from '../dist/cloudObjectStore.js';
const body = Buffer.from('verified model');
const model = {file:'alac.ms',bytes:body.length,sha256:createHash('sha256').update(body).digest('hex')};
function setup(head, responses) {
  const methods=[];
  return {methods, args:{model,body,key:'model-key',log:()=>{},store:{
    async head(){if(head!==200)throw Error(`OBS operation failed (${head})`);return {bytes:body.length};},
    signDownload(){return 'https://obs.invalid/download?secret=hidden';},
    signUpload(key,md5,seconds,protect){assert.equal(protect,true);return 'https://obs.invalid/upload?secret=hidden';}
  }, async fetcher(url,opts){methods.push(opts.method||'GET');
    if(opts.method==='PUT')assert.equal(opts.headers['x-obs-forbid-overwrite'],'true');
    const next=responses.shift();if(next instanceof Error)throw next;
    assert.ok(next,'unexpected network call');return next;
  }}};
}
const ok=()=>new Response(body,{status:200});
const denied=()=>new Response('<Code>AccessDenied</Code><Message>secret credential</Message>',{status:403});
test('missing object masked by HEAD/GET 403 uploads and verifies',async()=>{
  const f=setup(403,[denied(),new Response('',{status:200}),ok()]);await publishModel(f.args);
  assert.deepEqual(f.methods,['GET','PUT','GET']);
});
test('HEAD 403 with readable existing object never uploads',async()=>{
  const f=setup(403,[ok()]);await publishModel(f.args);assert.deepEqual(f.methods,['GET']);
});
test('HEAD 404 uploads; HEAD 200 reuses; concurrent conflict verifies',async()=>{
  for(const status of [200,409,412]){const f=setup(404,[new Response('',{status}),ok()]);await publishModel(f.args);assert.deepEqual(f.methods,['PUT','GET']);}
  const f=setup(200,[ok()]);await publishModel(f.args);assert.deepEqual(f.methods,['GET']);
});
test('actual PUT denial reports phase/status/code without secrets',async()=>{
  const f=setup(403,[denied(),denied()]);
  await assert.rejects(publishModel(f.args),error=>{
    assert.equal(safePublishError(error),'alac.ms | PUT | HTTP 403 AccessDenied');
    assert.doesNotMatch(error.message,/hidden|credential/);return true;
  });
});
test('unexpected HEAD error stops; hash mismatch and transport errors remain failures',async()=>{
  await assert.rejects(publishModel(setup(500,[]).args),/HEAD \| HTTP 500/);
  await assert.rejects(publishModel(setup(200,[new Response('wrong')]).args),/REMOTE_HASH_MISMATCH/);
  const error=new Error('secret URL');error.cause={code:'ENOTFOUND',message:'secret host'};
  await assert.rejects(publishModel(setup(200,[error]).args),/GET verification \| ENOTFOUND/);
  assert.equal(safePublishError(new Error('secret')),'REQUEST_FAILED');
});
test('OBS SDK signs overwrite protection header; normal cloud uploads retain original signature',()=>{
  const store=createObsStore({endpoint:'https://obs.cn-north-4.myhuaweicloud.com',region:'cn-north-4',
    bucket:'fixture',ak:'test',sk:'not-a-real-secret'});
  const ordinary=store.signUpload('key','md5',1800);
  const protectedUrl=store.signUpload('key','md5',1800,true);
  assert.notEqual(new URL(ordinary).searchParams.get('Signature'),new URL(protectedUrl).searchParams.get('Signature'));
});

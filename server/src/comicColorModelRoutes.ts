import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { CloudObjectStore } from './cloudObjectStore.js';
import { COMIC_COLOR_MODELS, comicColorObjectKey } from './comicColorModels.js';

export function registerComicColorModelRoutes(app: FastifyInstance, store: CloudObjectStore | null, deps: {
  authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  userId: (request: FastifyRequest) => string;
  limit: (userId: string) => Promise<void>;
}) {
  app.post<{ Params: { file: string } }>('/v1/ai/color-models/:file/download-ticket', {
    preHandler: async (request, reply) => {
      reply.header('Cache-Control', 'no-store');
      await deps.authenticate(request, reply);
      if (!reply.sent) await deps.limit(deps.userId(request));
    }, bodyLimit: 4096
  }, async (request, reply) => {
    const model = COMIC_COLOR_MODELS.find(item => item.file === request.params.file);
    if (!model) return reply.code(404).send({ code: 'MODEL_NOT_FOUND', message: '未找到着色模型' });
    if (!store) return reply.code(503).send({ code: 'MODEL_UNAVAILABLE', message: '模型下载暂不可用，请稍后重试' });
    const key = comicColorObjectKey(model);
    try {
      if ((await store.head(key)).bytes !== model.bytes) throw new Error('Invalid model size');
      return { ...model, url: store.signDownload(key, 1800) };
    } catch {
      // Do not log SDK errors: they can contain signed URLs or credentials.
      return reply.code(503).send({ code: 'MODEL_UNAVAILABLE', message: '模型下载暂不可用，请稍后重试' });
    }
  });
}

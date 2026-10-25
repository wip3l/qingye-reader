import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { CloudFileService, CloudPrepare, CloudRemoveReason, CloudUploadChunk } from './cloudFileService.js';

export function registerCloudFileRoutes(app: FastifyInstance, service: CloudFileService, deps: {
  authenticate: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  userId: (request: FastifyRequest) => string;
  limit: (userId: string) => Promise<void>;
}) {
  const guard = async (request: FastifyRequest, reply: FastifyReply) => {
    reply.header('Cache-Control', 'no-store');
    await deps.authenticate(request, reply);
    if (!reply.sent) await deps.limit(deps.userId(request));
  };
  app.get('/v1/cloud-files/summary', { preHandler: guard }, request => service.summary(deps.userId(request)));
  app.get<{ Querystring: { after?: string } }>('/v1/cloud-files', { preHandler: guard }, request =>
    service.list(deps.userId(request), request.query.after));
  app.post<{ Body: CloudPrepare }>('/v1/cloud-files/prepare', { preHandler: guard }, request =>
    service.prepare(deps.userId(request), request.body));
  app.get<{ Params: { id: string } }>('/v1/cloud-files/:id', { preHandler: guard }, request =>
    service.manifest(deps.userId(request), request.params.id));
  app.post<{ Params: { id: string }; Body: { meta?: unknown } }>('/v1/cloud-files/:id/metadata',
    { preHandler: guard, bodyLimit: 4096 }, request =>
      service.fillMetadata(deps.userId(request), request.params.id, request.body?.meta));
  app.post<{ Params: { id: string }; Body: CloudUploadChunk }>('/v1/cloud-files/:id/upload-ticket',
    { preHandler: guard, bodyLimit: 4096 }, request =>
      service.uploadTicket(deps.userId(request), request.params.id, request.body));
  app.post<{ Params: { id: string; index: string } }>('/v1/cloud-files/:id/chunks/:index/confirm',
    { preHandler: guard }, request =>
      service.confirmChunk(deps.userId(request), request.params.id, Number(request.params.index)));
  app.post<{ Params: { id: string; index: string }; Body: { requestId: string } }>('/v1/cloud-files/:id/chunks/:index/download-ticket',
    { preHandler: guard, bodyLimit: 4096 }, request =>
      service.downloadTicket(deps.userId(request), request.params.id, Number(request.params.index), request.body?.requestId));
  app.post<{ Params: { id: string } }>('/v1/cloud-files/:id/complete', { preHandler: guard }, request =>
    service.complete(deps.userId(request), request.params.id));
  app.post<{ Params: { id: string }; Body: { reason?: CloudRemoveReason } }>('/v1/cloud-files/:id/delete',
    { preHandler: guard, bodyLimit: 4096 }, request =>
      service.remove(deps.userId(request), request.params.id, request.body?.reason ?? 'DETACHED'));
  app.get('/v1/cloud-files/tombstones', { preHandler: guard }, request => service.tombstones(deps.userId(request)));
}

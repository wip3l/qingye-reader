import { AccountCommerceApi } from './AccountCommerceApi';
import { AccountApiError } from './AccountCommerceModels';
import { AccountSessionStore } from './AccountSessionStore';
import { AppDatabase, ReadStatsDeviceOption } from '../model/data/AppDatabase';
import { CloudSyncDevice } from './CloudSyncModels';
import { ReadStatsSyncRequest, ReadStatsSyncResponse, ReadStatsPendingUpload,
  ReadStatsSyncOperation, ReadStatsSyncAck } from '../core/stats/ReadStatsSyncModels';

export class ReadStatsCloudSyncResult {
  uploaded: number = 0;
  downloaded: number = 0;
}

/** Uses the cloud-sync scheduler, but its own durable cursor/outbox and immutable event protocol. */
export class ReadStatsCloudSync {
  static readonly STORAGE_REVISION: string = 'readingStatsCloudRevision';
  private static readonly DEVICE_REFRESH_INTERVAL_MS: number = 30 * 60 * 1000;
  private static deviceRefreshUserId: string = '';
  private static deviceRefreshToken: string = '';
  private static deviceRefreshAt: number = 0;

  static assertSession(userId: string, token: string): void {
    if (!AccountSessionStore.isLoggedIn() || AccountSessionStore.account().userId !== userId ||
      AccountSessionStore.token() !== token) throw new Error('账号已切换，请重新同步');
  }

  static async run(db: AppDatabase, userId: string,
    deviceId: string, token: string, refreshDevices: boolean = false): Promise<ReadStatsCloudSyncResult> {
    ReadStatsCloudSync.assertSession(userId, token);
    const boundary = await db.getReadStatsUploadBoundary();
    let cursor = await db.getReadStatsSyncCursor(userId);
    const result = new ReadStatsCloudSyncResult();
    let uploads = await db.getPendingReadStats(userId, deviceId, boundary);
    for (let page = 0; page < 20000; page++) {
      ReadStatsCloudSync.assertSession(userId, token);
      const request = new ReadStatsSyncRequest();
      request.deviceId = deviceId;
      request.cursor = cursor;
      request.operations = uploads.map((upload: ReadStatsPendingUpload): ReadStatsSyncOperation => upload.operation);
      const response = await ReadStatsCloudSync.exchange(request, userId, token);
      ReadStatsCloudSync.validate(response, request);
      ReadStatsCloudSync.assertSession(userId, token);
      // Apply before advancing the cursor. Replaying any partially applied page is safe.
      await db.applyReadStatsChanges(userId, response.changes);
      await db.acknowledgeReadStats(userId, uploads, response.acknowledgements);
      await db.setReadStatsSyncCursor(userId, response.nextCursor);
      cursor = response.nextCursor;
      result.uploaded += uploads.length;
      result.downloaded += response.changes.length;
      if (response.changes.length > 0 || response.acknowledgements.some((ack: ReadStatsSyncAck): boolean => ack.deleted)) {
        AppStorage.setOrCreate(ReadStatsCloudSync.STORAGE_REVISION,
          (AppStorage.get<number>(ReadStatsCloudSync.STORAGE_REVISION) || 0) + 1);
      }
      // The response already contains the pull page. Check the durable outbox
      // locally instead of sending an extra empty exchange after the last upload.
      uploads = await db.getPendingReadStats(userId, deviceId, boundary);
      if (uploads.length === 0 && !response.hasMore) {
        await ReadStatsCloudSync.refreshDeviceNames(db, userId, token, refreshDevices);
        return result;
      }
    }
    throw new Error('统计同步数据量较大，请再次同步以继续');
  }

  private static async refreshDeviceNames(db: AppDatabase, userId: string,
    token: string, force: boolean): Promise<void> {
    ReadStatsCloudSync.assertSession(userId, token);
    if (!force && ReadStatsCloudSync.deviceRefreshUserId === userId &&
      ReadStatsCloudSync.deviceRefreshToken === token && ReadStatsCloudSync.deviceRefreshAt > 0 &&
      Date.now() - ReadStatsCloudSync.deviceRefreshAt < ReadStatsCloudSync.DEVICE_REFRESH_INTERVAL_MS) return;
    const devices = await AccountCommerceApi.fetchSyncDevices(token);
    ReadStatsCloudSync.assertSession(userId, token);
    await db.updateReadStatsDeviceNames(userId, devices.devices.map((device: CloudSyncDevice): ReadStatsDeviceOption => {
      const option = new ReadStatsDeviceOption();
      option.deviceId = device.deviceId;
      option.deviceName = device.deviceName;
      return option;
    }));
    ReadStatsCloudSync.assertSession(userId, token);
    ReadStatsCloudSync.deviceRefreshUserId = userId;
    ReadStatsCloudSync.deviceRefreshToken = token;
    ReadStatsCloudSync.deviceRefreshAt = Date.now();
    AppStorage.setOrCreate(ReadStatsCloudSync.STORAGE_REVISION,
      (AppStorage.get<number>(ReadStatsCloudSync.STORAGE_REVISION) || 0) + 1);
  }

  private static async exchange(request: ReadStatsSyncRequest, userId: string,
    token: string): Promise<ReadStatsSyncResponse> {
    for (let attempt = 0; ; attempt++) {
      ReadStatsCloudSync.assertSession(userId, token);
      try {
        return await AccountCommerceApi.exchangeReadStats(request, token);
      } catch (error) {
        if (error instanceof AccountApiError && error.statusCode === 404) {
          throw new Error('服务端尚未启用阅读统计同步，请先更新服务端');
        }
        if (!(error instanceof AccountApiError) || error.statusCode !== 429 ||
          error.errorCode !== 'RATE_LIMITED' || attempt >= 3) {
          throw error instanceof Error ? error : new Error(String(error));
        }
        await new Promise<void>((resolve): void => {
          setTimeout(resolve, Math.min(120, Math.max(1, error.retryAfterSeconds || 60)) * 1000 + 250);
        });
      }
    }
  }

  private static validate(response: ReadStatsSyncResponse, request: ReadStatsSyncRequest): void {
    if (!response || response.protocolVersion !== 1 || !Array.isArray(response.changes) ||
      !Array.isArray(response.acknowledgements) || !Number.isSafeInteger(response.nextCursor) ||
      response.nextCursor < request.cursor || typeof response.hasMore !== 'boolean' ||
      response.acknowledgements.length !== request.operations.length) throw new Error('统计同步响应无效');
    let previous = request.cursor;
    for (const change of response.changes) {
      if (!change || !change.recordId || typeof change.deleted !== 'boolean' ||
        !Number.isSafeInteger(change.sequenceId) || change.sequenceId <= previous ||
        (!change.deleted && (!change.payload || !change.payload.bookKey ||
          !Number.isSafeInteger(change.payload.durationMs) || change.payload.durationMs <= 0))) {
        throw new Error('统计同步记录无效');
      }
      previous = change.sequenceId;
    }
    if (response.nextCursor !== previous || (response.hasMore && previous === request.cursor)) {
      throw new Error('统计同步游标未推进');
    }
    for (const operation of request.operations) {
      const matches = response.acknowledgements.filter((ack: ReadStatsSyncAck): boolean => ack.recordId === operation.recordId);
      if (matches.length !== 1 || typeof matches[0].deleted !== 'boolean') throw new Error('统计同步回执不完整');
    }
  }
}

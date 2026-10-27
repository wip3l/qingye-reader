import { Context } from '@kit.AbilityKit';
import { ReadStatsDevice } from '../core/stats/ReadStatsDevice';
import { appDb } from '../model/data/AppDatabase';
import preferences from '@ohos.data.preferences';

export class CloudSyncEntityState {
  revision: number = 0;
  contentHash: string = '';
  localKey: string = '';
  deleted: boolean = false;
}

export class CloudSyncLocalState {
  cursor: number = 0;
  entities: Record<string, CloudSyncEntityState> = {};
}

export class CloudSyncStateStore {
  private static readonly STORE_NAME: string = 'account_cloud_sync_state';
  private static readonly KEY_STATE_PREFIX: string = 'state_';
  private static writeQueue: Promise<void> = Promise.resolve();

  static async deviceId(context: Context): Promise<string> {
    return ReadStatsDevice.id(context);
  }

  static async load(context: Context, userId: string): Promise<CloudSyncLocalState> {
    const store = await preferences.getPreferences(context, CloudSyncStateStore.STORE_NAME);
    const raw = await store.get(CloudSyncStateStore.stateKey(userId), '');
    if (typeof raw !== 'string' || !raw) {
      return new CloudSyncLocalState();
    }
    try {
      return CloudSyncStateStore.normalize(JSON.parse(raw) as CloudSyncLocalState);
    } catch (e) {
      return new CloudSyncLocalState();
    }
  }

  static async save(context: Context, userId: string, state: CloudSyncLocalState): Promise<void> {
    const normalized = CloudSyncStateStore.normalize(state);
    const previous = CloudSyncStateStore.writeQueue.catch(() => {
    });
    const next = previous.then(async () => {
      const store = await preferences.getPreferences(context, CloudSyncStateStore.STORE_NAME);
      await store.put(CloudSyncStateStore.stateKey(userId), JSON.stringify(normalized));
      await store.flush();
    });
    CloudSyncStateStore.writeQueue = next;
    await next;
  }

  static async resetCursor(context: Context, userId: string): Promise<void> {
    await appDb.init(context);
    await appDb.setReadStatsSyncCursor(userId, 0);
    const state = await CloudSyncStateStore.load(context, userId);
    state.cursor = 0;
    await CloudSyncStateStore.save(context, userId, state);
  }

  static entityKey(entityType: string, entityId: string): string {
    return `${entityType}:${entityId}`;
  }

  private static stateKey(userId: string): string {
    const normalized = (userId || '').trim().replace(/[^a-zA-Z0-9_-]/g, '_') || 'guest';
    return `${CloudSyncStateStore.KEY_STATE_PREFIX}${normalized}`;
  }

  private static normalize(source: CloudSyncLocalState | null | undefined): CloudSyncLocalState {
    const result = new CloudSyncLocalState();
    if (!source) {
      return result;
    }
    result.cursor = Math.max(0, Math.floor(Number(source.cursor) || 0));
    result.entities = {};
    const entities = source.entities || {};
    for (const key of Object.keys(entities)) {
      const sourceState = entities[key];
      if (!sourceState) {
        continue;
      }
      const entity = new CloudSyncEntityState();
      entity.revision = Math.max(0, Math.floor(Number(sourceState.revision) || 0));
      entity.contentHash = sourceState.contentHash || '';
      entity.localKey = sourceState.localKey || '';
      entity.deleted = sourceState.deleted === true;
      result.entities[key] = entity;
    }
    return result;
  }
}

export class CloudSyncOperation {
  opId: string = '';
  entityType: string = '';
  entityId: string = '';
  operation: string = 'upsert';
  baseRevision: number = 0;
  payload: Object | null = null;
}

export class CloudSyncExchangeRequest {
  protocolVersion: number = 1;
  deviceId: string = '';
  deviceName: string = '';
  platform: string = 'HarmonyOS';
  appVersion: string = '';
  deviceKind: string = 'unknown';
  conflictPolicy: string = 'cloud';
  cursor: number = 0;
  operations: CloudSyncOperation[] = [];
}

export class CloudSyncConflict {
  payload: Object | null = null;
  deleted: boolean = false;
}

export class CloudSyncAcknowledgement {
  error: CloudSyncOperationError | null = null;
  opId: string = '';
  accepted: boolean = false;
  revision: number = 0;
  sequenceId: number | null = null;
  conflict: CloudSyncConflict | null = null;
}

export class CloudSyncOperationError {
  code: string = '';
  message: string = '';
}

export class CloudSyncChange {
  sequenceId: number = 0;
  entityType: string = '';
  entityId: string = '';
  revision: number = 0;
  operation: string = '';
  payload: Object | null = null;
  deviceId: string = '';
  createdAt: number = 0;
}

export class CloudSyncExchangeResponse {
  protocolVersion: number = 1;
  acknowledgements: CloudSyncAcknowledgement[] = [];
  changes: CloudSyncChange[] = [];
  nextCursor: number = 0;
  hasMore: boolean = false;
  serverTime: number = 0;
}

export class CloudSyncDevice {
  deviceId: string = '';
  deviceName: string = '';
  platform: string = '';
  appVersion: string = '';
  deviceKind: string = 'unknown';
  createdAt: number = 0;
  lastSeenAt: number = 0;
  revokedAt: number | null = null;
}

export class CloudSyncDeviceListResponse {
  devices: CloudSyncDevice[] = [];
}

/** 云端设置历史的一项（只有元数据）。 */
export class CloudSyncHistoryItem {
  historyId: string = '';
  entityType: string = '';
  entityId: string = '';
  deleted: boolean = false;
}

/** 同一台设备同一次替换的云端设置历史。reason：local_first 本地为主强制替换；restore 恢复设置历史。 */
export class CloudSyncHistoryGroup {
  groupId: string = '';
  replacedAt: number = 0;
  deviceId: string = '';
  deviceName: string = '';
  reason: string = '';
  items: CloudSyncHistoryItem[] = [];
}

export class CloudSyncHistoryList {
  groups: CloudSyncHistoryGroup[] = [];
}

export class CloudSyncHistoryRestoreBody {
  deviceId: string = '';
  historyIds: string[] = [];
}

export class CloudSyncHistoryRestoreResult {
  restored: number = 0;
}

export class CloudSyncSummary {
  activeEntityCount: number = 0;
  sourceCount: number = 0;
  membershipLimitsEnabled: boolean = false;
}

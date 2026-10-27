/** Wire data contains no account ID or device-local book URI. Owner comes from authentication. */
export class ReadStatsSyncPayload {
  deviceId: string = '';
  deviceName: string = '';
  bookKey: string = '';
  name: string = '';
  author: string = '';
  coverUrl: string = '';
  dayKey: string = '';
  durationMs: number = 0;
  startedAt: number = 0;
  lastReadAt: number = 0;
  timezoneOffset: number = 0;
}

export class ReadStatsSyncOperation {
  recordId: string = '';
  deleted: boolean = false;
  payload: ReadStatsSyncPayload | null = null;
}

/** Local optimistic acknowledgement token; never used as a server ordering clock. */
export class ReadStatsPendingUpload {
  operation: ReadStatsSyncOperation = new ReadStatsSyncOperation();
  version: number = 0;
}

export class ReadStatsSyncRequest {
  protocolVersion: number = 1;
  deviceId: string = '';
  cursor: number = 0;
  operations: ReadStatsSyncOperation[] = [];
}

export class ReadStatsSyncAck {
  recordId: string = '';
  deleted: boolean = false;
}

export class ReadStatsSyncChange {
  recordId: string = '';
  sequenceId: number = 0;
  deleted: boolean = false;
  payload: ReadStatsSyncPayload | null = null;
}

export class ReadStatsSyncResponse {
  protocolVersion: number = 1;
  acknowledgements: ReadStatsSyncAck[] = [];
  changes: ReadStatsSyncChange[] = [];
  nextCursor: number = 0;
  hasMore: boolean = false;
}

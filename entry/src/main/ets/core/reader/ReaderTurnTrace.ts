export class ReaderTurnTraceEvent {
  turn: number;
  stage: string;
  elapsedMs: number;

  constructor(turn: number, stage: string, elapsedMs: number) {
    this.turn = turn;
    this.stage = stage;
    this.elapsedMs = elapsedMs;
  }
}

/** Opt-in diagnostics. Marks describe application stages, never physical display/presentation times. */
export class ReaderTurnTrace {
  enabled: boolean = false;
  private turn: number = 0;
  private startedAt: number = 0;
  private events: ReaderTurnTraceEvent[] = [];

  begin(): void {
    if (!this.enabled) return;
    this.turn++;
    this.startedAt = Date.now();
    this.mark('input');
  }

  mark(stage: string): void {
    if (!this.enabled || this.turn === 0) return;
    const event = new ReaderTurnTraceEvent(this.turn, stage, Math.max(0, Date.now() - this.startedAt));
    if (this.events.length >= 128) this.events.shift();
    this.events.push(event);
    console.info(`[ReaderTurn] id=${event.turn} stage=${event.stage} elapsedMs=${event.elapsedMs}`);
  }

  snapshot(): ReaderTurnTraceEvent[] { return this.events.slice(); }

  reset(): void { this.events = []; this.turn = 0; this.startedAt = 0; }
}

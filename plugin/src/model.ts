import { randomUUID } from 'node:crypto';

export type State = 'idle' | 'working' | 'waiting' | 'success' | 'error';
export type Reason = 'question' | 'approval' | 'plan_review';
export interface Wait { actionId: string; reason: Reason }
export interface SessionRecord {
  sessionId: string; title: string; runId: string; state: State; activeWaits: Wait[];
  updatedAt: number; lastOutcome?: string;
}
export interface CompanionEvent extends SessionRecord {
  protocolVersion: '1.0'; eventId: string; source: 'deepseek-harness'; instanceId: string;
  sourceEpoch: string; sequence: number; type: string; occurredAt: string; summary: string;
  notify: boolean;
}

const wording: Record<Reason, string> = { question: '有一个问题等你回答', approval: '有一项操作需要你确认', plan_review: '计划已生成，等你审阅' };

/** Only normalized facts enter this model; it never answers a DSH interaction. */
export class EventModel {
  readonly epoch = randomUUID();
  readonly records = new Map<string, SessionRecord>();
  readonly history: CompanionEvent[] = [];
  sequence = 0;
  onChange: () => void = () => {};
  constructor(readonly instanceId: string) {}

  ensure(id: string, title?: string): SessionRecord {
    let record = this.records.get(id);
    if (!record) {
      record = { sessionId: id, title: title || `会话 ${id.slice(0, 8)}`, runId: randomUUID(), state: 'idle', activeWaits: [], updatedAt: Date.now() };
      this.records.set(id, record);
      this.onChange();
    } else if (title && record.title !== title.slice(0, 200)) {
      record.title = title.slice(0, 200); this.onChange();
    }
    return record;
  }

  emit(record: SessionRecord, type: string, summary = '', notify = false): void {
    record.updatedAt = Date.now();
    const event: CompanionEvent = {
      ...structuredClone(record), protocolVersion: '1.0', eventId: randomUUID(),
      source: 'deepseek-harness', instanceId: this.instanceId, sourceEpoch: this.epoch,
      sequence: ++this.sequence, type, occurredAt: new Date().toISOString(), summary, notify,
    };
    this.history.push(event);
    while (this.history.length > 500 || (this.history[0] && Date.now() - this.history[0].updatedAt > 600_000)) this.history.shift();
    this.onChange();
  }

  running(id: string, running: boolean, outcome?: string): void {
    const r = this.ensure(id);
    if (running) {
      if (r.state !== 'working' && r.state !== 'waiting') { r.runId = randomUUID(); delete r.lastOutcome; }
      if (r.activeWaits.length) return;
      if (r.state !== 'working') { r.state = 'working'; this.emit(r, 'session.started'); }
      return;
    }
    if (r.activeWaits.length) { r.state = 'waiting'; return; }
    if (!outcome || r.lastOutcome === outcome) {
      if (r.state === 'working') { r.state = 'idle'; this.emit(r, 'session.stopped'); }
      return;
    }
    r.lastOutcome = outcome;
    if (outcome === 'completed') { r.state = 'success'; this.emit(r, 'task.succeeded', '任务已完成', true); }
    else if (outcome === 'error' || outcome === 'max-tokens' || outcome === 'blocked') {
      r.state = 'error';
      this.emit(r, 'task.failed', outcome === 'max-tokens' ? '执行因输出上限结束' : outcome === 'blocked' ? '执行被阻塞，点这里查看' : '任务失败了，点这里查看', true);
    } else { r.state = 'idle'; this.emit(r, 'session.stopped', '执行已停止'); }
  }

  waits(id: string, waits: Wait[], running: boolean, baseline = false): void {
    const r = this.ensure(id);
    const previous = new Set(r.activeWaits.map(w => w.actionId));
    const next = [...new Map(waits.map(w => [w.actionId, w])).values()];
    if (JSON.stringify(next) === JSON.stringify(r.activeWaits)) return;
    r.activeWaits = next;
    r.state = next.length ? 'waiting' : running ? 'working' : 'idle';
    if (baseline) r.updatedAt = Date.now();
    const added = next.filter(w => !previous.has(w.actionId));
    if (!baseline) this.emit(r, next.length ? 'session.waiting' : running ? 'session.resumed' : 'session.stopped',
      next.length > 1 ? `这个会话有 ${next.length} 项等待处理` : next.length ? wording[next[0].reason] : '', added.length > 0);
  }

  feed(after: number, epoch: string): { protocolVersion: string; sourceEpoch: string; instanceId: string; throughSequence: number; sessions: SessionRecord[]; events: CompanionEvent[]; reset: boolean } {
    const reset = epoch !== this.epoch || after < 0 || after > this.sequence || (after < this.sequence && after < (this.history[0]?.sequence ?? this.sequence + 1) - 1);
    return { protocolVersion: '1.0', sourceEpoch: this.epoch, instanceId: this.instanceId, throughSequence: this.sequence,
      sessions: [...this.records.values()].map(r => structuredClone(r)), events: reset ? [] : this.history.filter(e => e.sequence > after), reset };
  }
}

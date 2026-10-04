import { createServer, type ServerResponse } from 'node:http';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { mkdir, writeFile, rename, readFile, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import type { EventModel } from './model.js';
import { normalizeView, type ViewStatus, type ViewCommand } from './view.js';

export interface OpenCommand { requestId: string; sessionId: string; expiresAt: number }

export class LocalBridge {
  readonly token = randomBytes(32).toString('hex');
  readonly pending = new Map<string, { command: OpenCommand; finish: (status: string) => void }>();
  readonly feedWaiters = new Set<() => void>();
  readonly commandWaiters = new Set<() => void>();
  lastClientSeen = 0;
  viewStatus?: ViewStatus;
  readonly views = new Map<string, { command: ViewCommand; finish: (status: string) => void }>();
  reportView(payload: any): ViewCommand[] {
    const view = normalizeView(payload?.view);
    if (!view) return [];
    const changed = !this.viewStatus || ['sessionId', 'visible', 'focused', 'loaded'].some(key => (view as any)[key] !== (this.viewStatus as any)[key]);
    this.viewStatus = view;
    this.lastClientSeen = Date.now();
    if (changed) this.wake(this.feedWaiters);
    const receipt = payload?.receipt;
    const pending = this.views.get(receipt?.requestId);
    if (pending && receipt?.status === 'viewed' && pending.command.expiresAt > Date.now() &&
        ['sessionId', 'instanceId', 'sourceEpoch', 'throughSequence'].every(key => receipt[key] === (pending.command as any)[key]) &&
        view.sessionId === pending.command.sessionId && view.visible && view.focused && view.loaded) pending.finish('viewed');
    return [...this.views.values()].map(v => v.command).filter(c => c.expiresAt > Date.now());
  }
  private server = createServer((req, res) => { void this.handle(req, res).catch(() => this.json(res, 500, { error: 'bridge_failure' })); });
  constructor(readonly model: EventModel, readonly directory: string) { model.onChange = () => this.wake(this.feedWaiters); }
  private wake(waiters: Set<() => void>): void { for (const wake of [...waiters]) wake(); }
  private json(res: ServerResponse, status: number, body: unknown): void {
    if (res.writableEnded || res.destroyed) return;
    res.writeHead(status, { 'content-type': 'application/json', 'cache-control': 'no-store' }); res.end(JSON.stringify(body));
  }
  async start(): Promise<void> {
    await mkdir(this.directory, { recursive: true, mode: 0o700 });
    await new Promise<void>((resolve, reject) => { this.server.once('error', reject); this.server.listen(0, '127.0.0.1', resolve); });
    const address = this.server.address(); if (!address || typeof address === 'string') throw new Error('Missing endpoint');
    const file = join(this.directory, 'endpoint.json'); const temp = `${file}.${process.pid}.tmp`;
    await writeFile(temp, JSON.stringify({ protocolVersion: '1.0', port: address.port, token: this.token, sourceEpoch: this.model.epoch, instanceId: this.model.instanceId }), { mode: 0o600 });
    await rename(temp, file);
  }
  async stop(): Promise<void> {
    for (const p of this.pending.values()) p.finish('disconnected');
    for (const p of this.views.values()) p.finish('disconnected');
    this.views.clear();
    this.pending.clear(); this.wake(this.feedWaiters); this.wake(this.commandWaiters);
    this.server.closeAllConnections(); this.server.close();
    const file = join(this.directory, 'endpoint.json');
    try { if (JSON.parse(await readFile(file, 'utf8')).sourceEpoch === this.model.epoch) await unlink(file); } catch { /* Already removed or replaced. */ }
  }
  private async handle(req: import('node:http').IncomingMessage, res: ServerResponse): Promise<void> {
    const auth = req.headers.authorization?.replace(/^Bearer /, '') ?? '';
    const expected = Buffer.from(this.token); const received = Buffer.from(auth);
    if (received.length !== expected.length || !timingSafeEqual(received, expected) || req.headers.origin) { this.json(res, 401, { error: 'unauthorized' }); return; }
    const url = new URL(req.url ?? '/', 'http://127.0.0.1');
    if (url.pathname === '/poll' && req.method === 'GET') {
      const after = Number(url.searchParams.get('after') ?? -1); const epoch = url.searchParams.get('epoch') ?? '';
      if (!Number.isSafeInteger(after)) { this.json(res, 400, { error: 'invalid_cursor' }); return; }
      if (epoch === this.model.epoch && after === this.model.sequence) await this.wait(this.feedWaiters, 20_000, res);
      this.json(res, 200, { ...this.model.feed(after, epoch), clientConnected: Date.now() - this.lastClientSeen < 45_000, viewStatus: this.viewStatus }); return;
    }
    if (url.pathname === '/view-state' && req.method === 'GET') {
      this.json(res, 200, { viewStatus: this.viewStatus }); return;
    }
    if (url.pathname === '/view' && req.method === 'POST') {
      let text = ''; for await (const chunk of req) { text += chunk; if (text.length > 8192) { this.json(res, 413, { error: 'too_large' }); return; } }
      let body: any; try { body = JSON.parse(text); } catch { this.json(res, 400, { error: 'invalid_json' }); return; }
      if (!body || typeof body.requestId !== 'string' || !body.requestId || body.requestId.length > 100 ||
          typeof body.sessionId !== 'string' || body.sessionId.length > 200 || body.instanceId !== this.model.instanceId ||
          body.sourceEpoch !== this.model.epoch || !Number.isSafeInteger(body.throughSequence) || body.throughSequence < 0 || body.throughSequence > this.model.sequence) {
        this.json(res, 400, { error: 'invalid_view_boundary' }); return;
      }
      if (this.views.size >= 20 || this.views.has(body.requestId)) { this.json(res, 409, { error: 'view_busy' }); return; }
      const record = this.model.records.get(body.sessionId);
      const command: ViewCommand = { requestId: body.requestId, sessionId: body.sessionId, instanceId: body.instanceId,
        sourceEpoch: body.sourceEpoch, throughSequence: body.throughSequence, expiresAt: Date.now() + 2400,
        state: record?.state ?? 'idle', reasons: record?.activeWaits.map(v => v.reason) ?? [] };
      const status = await new Promise<string>(resolve => {
        const timer = setTimeout(() => { this.views.delete(command.requestId); resolve('unconfirmed'); }, 2400);
        this.views.set(command.requestId, { command, finish: result => { clearTimeout(timer); this.views.delete(command.requestId); resolve(result); } });
        res.once('close', () => this.views.get(command.requestId)?.finish('disconnected'));
      });
      this.json(res, 200, { ...command, status }); return;
    }
    if (url.pathname === '/open' && req.method === 'POST') {
      let text = ''; for await (const chunk of req) { text += chunk; if (text.length > 8192) { this.json(res, 413, { error: 'too_large' }); return; } }
      let body: { requestId?: string; sessionId?: string }; try { body = JSON.parse(text); } catch { this.json(res, 400, { error: 'invalid_json' }); return; }
      if (typeof body.sessionId !== 'string' || typeof body.requestId !== 'string' || body.requestId.length > 100 || body.sessionId.length > 200) { this.json(res, 400, { error: 'invalid_target' }); return; }
      if (this.pending.size >= 20 || this.pending.has(body.requestId)) { this.json(res, 409, { status: 'failed' }); return; }
      if (Date.now() - this.lastClientSeen > 45_000) { this.json(res, 200, { requestId: body.requestId, status: 'disconnected' }); return; }
      const command: OpenCommand = { requestId: body.requestId, sessionId: body.sessionId, expiresAt: Date.now() + 7000 };
      const status = await new Promise<string>(resolve => {
        const timer = setTimeout(() => { this.pending.delete(command.requestId); resolve('unconfirmed'); }, 7000);
        this.pending.set(command.requestId, { command, finish: result => { clearTimeout(timer); this.pending.delete(command.requestId); resolve(result); } });
        this.wake(this.commandWaiters);
      });
      this.json(res, 200, { requestId: command.requestId, status }); return;
    }
    this.json(res, 404, { error: 'not_found' });
  }
  private wait(set: Set<() => void>, ms: number, response?: ServerResponse, signal?: AbortSignal): Promise<void> {
    return new Promise(resolve => {
      const done = () => { clearTimeout(timer); set.delete(done); response?.off('close', done); signal?.removeEventListener('abort', done); resolve(); };
      const timer = setTimeout(done, ms); set.add(done); response?.once('close', done); signal?.addEventListener('abort', done, { once: true });
      if (signal?.aborted) done();
    });
  }
  async pollCommands(signal: AbortSignal): Promise<OpenCommand[]> {
    this.lastClientSeen = Date.now();
    if (!this.pending.size) await this.wait(this.commandWaiters, 20_000, undefined, signal);
    this.lastClientSeen = Date.now();
    return [...this.pending.values()].map(v => v.command).filter(c => c.expiresAt > Date.now());
  }
  complete(requestId: string, status: string): void {
    if (['opened', 'unconfirmed', 'not_found', 'disconnected', 'unsupported', 'failed'].includes(status)) this.pending.get(requestId)?.finish(status);
  }
}

import { homedir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { EventModel, type Wait, type Reason } from './model.js';
import { LocalBridge } from './bridge.js';

// Structural API contracts verified against installed DSH 0.2.0-rc.2.
interface Session { id: string; header: { origin?: string; cwd?: string }; }
interface Agent { id: string; session: Session; status: string }
interface DshEvent { type: string; data: Record<string, any>; seq: number }
interface Context {
  sessions: { list(): Session[] }; agents: { get(id: string): Agent | undefined };
  sessionProjections: { snapshot(session: Session, keys?: string[]): { values: Record<string, any> } };
  connection: { fetch: { register(route: { path: string; methods: string[]; requestBody: 'buffered'; fetch(req: Request): Promise<Response> }): unknown } };
  on(name: string, callback: (...args: any[]) => any, options?: { global?: boolean; prepend?: boolean }): unknown;
  effect(callback: () => (() => unknown), label?: string): unknown;
}
export const name = 'dsh-always-on';
export const inject = ['sessions', 'agents', 'sessionProjections', 'connection'];

export async function apply(ctx: Context): Promise<void> {
  const directory = process.env.DSH_ALWAYS_ON_DATA_DIR || join(homedir(), 'Library', 'Application Support', 'DSH Always On');
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const instanceFile = join(directory, 'instance-id');
  let instanceId: string;
  try { instanceId = (await readFile(instanceFile, 'utf8')).trim(); }
  catch { instanceId = randomUUID(); await writeFile(instanceFile, instanceId, { mode: 0o600 }); }
  const model = new EventModel(instanceId);
  const bridge = new LocalBridge(model, directory);
  const finalReasons = new Map<string, string>();
  const approvals = new Map<string, Map<string, Wait>>();
  const legacyQuestions = new Map<string, Map<string, Wait>>();
  const clientWaits = new Map<string, Wait>();
  const root = (session: Session) => session.header.origin !== 'subagent';
  const running = (id: string) => ctx.agents.get(id)?.status === 'running';
  const reconcile = (session: Session, baseline = false) => {
    if (!root(session)) return;
    const values = ctx.sessionProjections.snapshot(session, ['title', 'userQuestions']).values;
    const title = typeof values.title === 'string' ? values.title : values.title?.title;
    model.ensure(session.id, title);
    const projected: Wait[] = (values.userQuestions?.active ?? []).map((q: any) => ({ actionId: `question:${q.callId}`, reason: q.questions?.some((v: any) => v.intent?.kind === 'plan-review') ? 'plan_review' : 'question' }));
    const waits = [...(approvals.get(session.id)?.values() ?? []), ...(legacyQuestions.get(session.id)?.values() ?? []), ...projected];
    const recovered = clientWaits.get(session.id);
    if (recovered && !waits.some(wait => wait.reason === recovered.reason)) waits.push(recovered);
    model.waits(session.id, waits, running(session.id), baseline);
  };
  for (const session of ctx.sessions.list()) {
    if (!root(session)) continue;
    model.ensure(session.id).state = running(session.id) ? 'working' : 'idle';
    reconcile(session, true);
  }
  ctx.on('session/created', (session: Session) => reconcile(session, true), { global: true });
  ctx.on('session/event', (session: Session, event: DshEvent) => {
    if (!root(session)) return;
    const id = session.id;
    if (event.type === 'approval/asked') {
      const map = approvals.get(id) ?? new Map<string, Wait>();
      map.set(event.data.id, { actionId: `approval:${event.data.id}`, reason: 'approval' }); approvals.set(id, map);
    }
    if (event.type === 'approval/decided') approvals.get(id)?.delete(event.data.id);
    if (event.type === 'turn/end') finalReasons.set(id, event.data.reason.kind);
    if (event.type === 'session/title') model.ensure(id, event.data.title);
    // Projection readers see the committed event after all synchronous observers finish.
    if (['approval/asked', 'approval/decided', 'tool/call', 'tool/result', 'tool/ptc-dispatch', 'user/message', 'session/title'].includes(event.type)) queueMicrotask(() => reconcile(session));
  }, { global: true });
  ctx.on('agent/status', ({ agent, status }: { agent: Agent; status: string }) => {
    if (!root(agent.session)) return;
    if (status === 'running') finalReasons.delete(agent.id);
    reconcile(agent.session);
    model.running(agent.id, status === 'running', status === 'idle' ? finalReasons.get(agent.id) : undefined);
    if (status === 'idle') finalReasons.delete(agent.id);
  }, { global: true });
  // This listener delegates to DSH's existing answerer; it never claims the question.
  ctx.on('user-questions/request', async (request: any, next: () => Promise<unknown>) => {
    const session = request.agent?.session as Session | undefined;
    if (!session || !root(session)) return next();
    const actionId = request.wait?.callId ? `question:${request.wait.callId}` : `question:${randomUUID()}`;
    const reason: Reason = request.questions?.some((q: any) => q.intent?.kind === 'plan-review') ? 'plan_review' : 'question';
    const map = legacyQuestions.get(session.id) ?? new Map<string, Wait>();
    map.set(actionId, { actionId, reason }); legacyQuestions.set(session.id, map); reconcile(session);
    try { return await next(); }
    finally { map.delete(actionId); queueMicrotask(() => reconcile(session)); }
  }, { global: true, prepend: true });
  for (const endpoint of ['poll', 'complete', 'status', 'view']) {
    ctx.connection.fetch.register({ path: `/api/always-on/${endpoint}`, methods: ['POST'], requestBody: 'buffered', fetch: async request => {
      const envelope = await request.json() as { rpcId: string; payload: any };
      let value: unknown;
      if (endpoint === 'poll') value = await bridge.pollCommands(request.signal);
      else if (endpoint === 'view') value = bridge.reportView(envelope.payload);
      else if (endpoint === 'status') {
        if (!Array.isArray(envelope.payload?.pending) || envelope.payload.pending.length > 2000) return new Response('Invalid status', { status: 400 });
        clientWaits.clear();
        for (const pending of envelope.payload.pending) {
          const reasons: Record<string, Reason> = { question: 'question', approval: 'approval', 'plan-review': 'plan_review' };
          if (typeof pending.sessionId === 'string' && typeof pending.key === 'string' && reasons[pending.kind]) {
            clientWaits.set(pending.sessionId, { actionId: `ui:${pending.key}`, reason: reasons[pending.kind] });
          }
        }
        // UI reports recover requests that existed before the host observer was mounted.
        for (const session of ctx.sessions.list()) reconcile(session, true);
        bridge.model.onChange(); value = null;
      }
      else { bridge.complete(envelope.payload?.requestId, envelope.payload?.status); value = null; }
      return Response.json({ type: 'server-response', rpcId: envelope.rpcId, result: { ok: true, value } });
    } });
  }
  ctx.effect(() => () => { void bridge.stop(); }, 'always-on: local bridge');
  await bridge.start();
}

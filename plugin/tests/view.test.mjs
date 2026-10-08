import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { EventModel } from '../lib/model.js';
import { LocalBridge } from '../lib/bridge.js';
import { canConfirm, normalizeView, viewSnapshot } from '../lib/view.js';
function context() {
  const session = { openState: 'open', running: false }, state = { byId: { a: { retainedBy: { mainView: 1 } } } };
  const panel = { activePanelId: null }, statuses = new Map();
  return { state, panel, session, statuses, ctx: {
    sessions: { list: { getSnapshot: () => state }, binding: () => ({ session: { getSnapshot: () => session } }) },
    layout: { panelInfo: { getSnapshot: () => panel } }, uiSession: { sessionStatus: { getSnapshot: () => statuses } }
  } };
}
const doc = { visibilityState: 'visible', hasFocus: () => true };
const command = { sessionId: 'a', expiresAt: 1000, state: 'success', reasons: [] };
test('only one loaded conversation with window focus can confirm a view', () => {
  const f = context(); assert.equal(canConfirm(f.ctx, doc, command, 0), true);
  f.panel.activePanelId = 'settings'; assert.equal(canConfirm(f.ctx, doc, command, 0), false);
  f.panel.activePanelId = null; f.session.openState = 'loading'; assert.equal(canConfirm(f.ctx, doc, command, 0), false);
  f.session.openState = 'open'; f.state.byId.b = { retainedBy: { mainView: 1 } };
  assert.equal(viewSnapshot(f.ctx, doc).sessionId, undefined); delete f.state.byId.b;
  assert.equal(canConfirm(f.ctx, { ...doc, hasFocus: () => false }, command, 0), false);
  assert.equal(canConfirm(f.ctx, { ...doc, visibilityState: 'hidden' }, command, 0), false);
  assert.equal(canConfirm(f.ctx, doc, command, 1000), false);
});
test('running projection cannot confirm completion; waiting matches the displayed interaction', () => {
  const f = context(); f.session.running = true; assert.equal(canConfirm(f.ctx, doc, command, 0), false);
  f.statuses.set('a', { pendingInteraction: { kind: 'approval' } });
  assert.equal(canConfirm(f.ctx, doc, { ...command, state: 'waiting', reasons: ['question'] }, 0), false);
  assert.equal(canConfirm(f.ctx, doc, { ...command, state: 'waiting', reasons: ['approval'] }, 0), true);
  f.statuses.set('a', { pendingInteraction: { kind: 'plan-review' } });
  assert.equal(canConfirm(f.ctx, doc, { ...command, state: 'waiting', reasons: ['plan_review'] }, 0), true);
});
test('bridge timestamps reports and rejects malformed snapshots', () => {
  assert.equal(normalizeView({ visible: true }), undefined);
  assert.equal(normalizeView({ visible: true, focused: true, loaded: true, reportedAt: 999999 }, 10).reportedAt, 10);
});
async function fixture(t) {
  const dir = await mkdtemp(join(tmpdir(), 'always-on-view-'));
  const model = new EventModel('i'); model.running('a', true); model.running('a', false, 'completed');
  const bridge = new LocalBridge(model, dir); await bridge.start();
  const e = JSON.parse(await readFile(join(dir, 'endpoint.json'), 'utf8'));
  t.after(async () => { await bridge.stop(); await rm(dir, { recursive: true, force: true }); });
  const post = body => fetch(`http://127.0.0.1:${e.port}/view`, { method: 'POST', headers: { Authorization: `Bearer ${e.token}` }, body: JSON.stringify(body) });
  return { bridge, model, post };
}
const validView = { sessionId: 'a', visible: true, focused: true, loaded: true };
test('receipts keep a fixed boundary and never become navigation commands', async t => {
  const f = await fixture(t), body = { requestId: 'r1', sessionId: 'a', instanceId: 'i', sourceEpoch: f.model.epoch, throughSequence: f.model.sequence };
  const pending = f.post(body); while (!f.bridge.views.size) await new Promise(r => setTimeout(r, 5));
  assert.equal(f.bridge.pending.size, 0);
  const [probe] = f.bridge.reportView({ view: validView }); assert.equal(probe.requestId, 'r1');
  f.model.running('a', true);
  f.bridge.reportView({ view: validView, receipt: { ...probe, throughSequence: probe.throughSequence + 1, status: 'viewed' } });
  assert.equal(f.bridge.views.size, 1);
  f.bridge.reportView({ view: { ...validView, sessionId: 'b' }, receipt: { ...probe, status: 'viewed' } });
  assert.equal(f.bridge.views.size, 1);
  f.bridge.reportView({ view: validView, receipt: { ...probe, status: 'viewed' } });
  const result = await (await pending).json(); assert.equal(result.status, 'viewed'); assert.equal(result.throughSequence, body.throughSequence);
});
test('wrong epochs and future boundaries rejected; disconnect keeps view unconfirmed', async t => {
  const f = await fixture(t), body = { requestId: 'r', sessionId: 'a', instanceId: 'i', sourceEpoch: f.model.epoch, throughSequence: f.model.sequence };
  assert.equal((await f.post({ ...body, sourceEpoch: 'old' })).status, 400);
  assert.equal((await f.post({ ...body, throughSequence: 100000 })).status, 400);
  const pending = f.post(body); while (!f.bridge.views.size) await new Promise(r => setTimeout(r, 5));
  f.bridge.views.get('r').finish('disconnected');
  assert.equal((await (await pending).json()).status, 'disconnected'); assert.equal(f.bridge.views.size, 0);
});
test('unconfirmed view expires with no command to replay', async t => {
  const f = await fixture(t);
  const result = await (await f.post({ requestId: 'r', sessionId: 'a', instanceId: 'i', sourceEpoch: f.model.epoch, throughSequence: f.model.sequence })).json();
  assert.equal(result.status, 'unconfirmed'); assert.equal(f.bridge.views.size, 0); assert.equal(f.bridge.pending.size, 0);
});

import vm from 'node:vm';
async function runClient({ switchDuringFrames = false, resumeAfterFailure = false } = {}) {
  let loaded, dispose, frames = 0, receipts = 0, navigations = 0, reports = 0;
  const f = context(), listeners = new Map();
  f.ctx.sessions.refresh = async () => {};
  f.ctx.uiWorkspace = { openSession: () => { navigations++; } };
  f.ctx.uiSession.sessionStatus.subscribe = () => () => {};
  f.ctx.effect = callback => { dispose = callback(); };
  f.ctx.connection = { rpc: { call: async (_channel, endpoint, payload, signal) => {
    if (endpoint.endsWith('/status')) { reports++; if (resumeAfterFailure && reports === 1) throw new Error('sleep disconnect'); }
    if (endpoint.endsWith('/poll')) return new Promise((_, reject) => signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }));
    if (endpoint.endsWith('/view')) {
      if (payload.receipt) { receipts++; return { ok: true, value: [] }; }
      return { ok: true, value: [{ ...command, expiresAt: Date.now() + 10000, requestId: 'r', instanceId: 'i', sourceEpoch: 'e', throughSequence: 1 }] };
    }
    return { ok: true, value: null };
  } } };
  const target = { addEventListener: (name, fn) => listeners.set(name, fn), removeEventListener: name => listeners.delete(name) };
  const sandbox = { window: { ...target, __ModuleLoader__: { load: mod => { loaded = mod.factory(() => {}); } } },
    document: { ...doc, ...target }, setTimeout, clearTimeout, setInterval, clearInterval, AbortController,
    requestAnimationFrame: callback => setTimeout(() => { frames++; if (switchDuringFrames) f.panel.activePanelId = 'settings'; callback(); }, 0), cancelAnimationFrame: clearTimeout };
  vm.runInNewContext(await readFile(new URL('../lib/client.js', import.meta.url), 'utf8'), sandbox);
  loaded.apply(f.ctx); await new Promise(r => setTimeout(r, 30));
  if (resumeAfterFailure) {
    assert.equal(reports, 1);
    listeners.get('pageshow')(); await new Promise(r => setTimeout(r, 10));
    listeners.get('online')(); await new Promise(r => setTimeout(r, 10));
  }
  dispose(); await new Promise(r => setTimeout(r, 5));
  return { receipts, navigations, frames, listeners, reports };
}
test('bundled client confirms after rendered frames without navigating; cleanup removes listeners', async () => {
  const result = await runClient(); assert.equal(result.receipts, 1); assert.equal(result.navigations, 0); assert.equal(result.frames, 2); assert.equal(result.listeners.size, 0);
});
test('selection changing during rendered frames prevents bundled client receipt', async () => {
  const result = await runClient({ switchDuringFrames: true }); assert.equal(result.receipts, 0); assert.equal(result.navigations, 0); assert.equal(result.listeners.size, 0);
});
test('page restoration and reconnect resend status without waiting for the command long poll', async () => {
  const result = await runClient({ resumeAfterFailure: true });
  assert.equal(result.reports, 3); assert.equal(result.navigations, 0); assert.equal(result.listeners.size, 0);
});

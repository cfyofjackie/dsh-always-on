import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { apply } from '../lib/index.js';

// Exercise the mounted observer through the same context and RPC contracts as DSH.
// This fixture never runs a model, executes an approval, or touches a user profile.
async function fixture(t, initialWaits = []) {
  const directory = await mkdtemp(join(tmpdir(), 'always-on-observer-'));
  const previous = process.env.DSH_ALWAYS_ON_DATA_DIR;
  process.env.DSH_ALWAYS_ON_DATA_DIR = directory;
  const session = { id: 'session-a', header: {} };
  const agent = { id: session.id, session, status: 'idle' };
  const callbacks = new Map(); const routes = new Map(); const disposers = [];
  let projected = initialWaits;
  const ctx = {
    sessions: { list: () => [session] }, agents: { get: id => id === agent.id ? agent : undefined },
    sessionProjections: { snapshot: () => ({ values: { title: { title: '测试会话' }, userQuestions: { active: projected } } }) },
    connection: { fetch: { register: route => routes.set(route.path, route.fetch) } },
    on: (name, callback) => callbacks.set(name, callback), effect: callback => disposers.push(callback()),
  };
  await apply(ctx);
  const endpoint = JSON.parse(await readFile(join(directory, 'endpoint.json'), 'utf8'));
  const feed = async () => {
    await new Promise(resolve => setImmediate(resolve));
    return (await fetch(`http://127.0.0.1:${endpoint.port}/poll`, { headers: { Authorization: `Bearer ${endpoint.token}` } })).json();
  };
  const events = async () => {
    const baseline = await feed();
    return (await fetch(`http://127.0.0.1:${endpoint.port}/poll?after=0&epoch=${baseline.sourceEpoch}`, { headers: { Authorization: `Bearer ${endpoint.token}` } })).json();
  };
  t.after(async () => {
    for (const dispose of disposers) dispose();
    await new Promise(resolve => setTimeout(resolve, 20));
    if (previous === undefined) delete process.env.DSH_ALWAYS_ON_DATA_DIR; else process.env.DSH_ALWAYS_ON_DATA_DIR = previous;
    await rm(directory, { recursive: true, force: true });
  });
  return { session, agent, callbacks, routes, feed, events, project: value => { projected = value; } };
}

test('whole execution completion follows idle, not an individual tool result', async t => {
  const f = await fixture(t); f.agent.status = 'running';
  f.callbacks.get('agent/status')({ agent: f.agent, status: 'running' });
  f.callbacks.get('session/event')(f.session, { type: 'tool/result', data: {}, seq: 1 });
  assert.equal((await f.feed()).sessions[0].state, 'working');
  f.callbacks.get('session/event')(f.session, { type: 'turn/end', data: { reason: { kind: 'completed' } }, seq: 2 });
  assert.equal((await f.feed()).sessions[0].state, 'working');
  f.agent.status = 'idle'; f.callbacks.get('agent/status')({ agent: f.agent, status: 'idle' });
  const result = await f.events();
  assert.equal(result.sessions[0].state, 'success');
  assert.equal(result.events.filter(e => e.notify).length, 1);
});
test('approval auditing observes pending and resolution without deciding it', async t => {
  const f = await fixture(t);
  f.callbacks.get('session/event')(f.session, { type: 'approval/asked', data: { id: 'approval-a' }, seq: 1 });
  const pending = await f.feed(); assert.equal(pending.sessions[0].activeWaits[0].reason, 'approval');
  assert.equal((await f.events()).events.filter(e => e.notify).length, 1);
  f.callbacks.get('session/event')(f.session, { type: 'approval/decided', data: { id: 'approval-a' }, seq: 2 });
  assert.equal((await f.feed()).sessions[0].activeWaits.length, 0);
});
test('plan review delegates unchanged to the existing answerer', async t => {
  const f = await fixture(t); let finish; let calls = 0;
  const answer = { answers: ['user choice'] };
  const task = f.callbacks.get('user-questions/request')({ agent: f.agent, wait: { callId: 'plan-a' }, questions: [{ intent: { kind: 'plan-review' } }] }, () => { calls++; return new Promise(resolve => { finish = resolve; }); });
  assert.equal((await f.feed()).sessions[0].activeWaits[0].reason, 'plan_review');
  finish(answer); assert.equal(await task, answer); assert.equal(calls, 1);
  assert.equal((await f.feed()).sessions[0].state, 'idle');
});
test('timed-out questions stay waiting while their durable projection remains active', async t => {
  const f = await fixture(t);
  const task = f.callbacks.get('user-questions/request')({ agent: f.agent, wait: { callId: 'question-a' }, questions: [] }, async () => {
    f.project([{ callId: 'question-a', questions: [] }]); return { timedOut: true };
  });
  await task;
  assert.equal((await f.feed()).sessions[0].activeWaits[0].actionId, 'question:question-a');
  assert.equal((await f.events()).events.filter(e => e.notify).length, 1);
});
test('existing question and UI approval recover as baselines without replay', async t => {
  const f = await fixture(t, [{ callId: 'existing', questions: [] }]);
  assert.equal((await f.feed()).throughSequence, 0);
  f.project([]);
  const response = await f.routes.get('/api/always-on/status')(new Request('http://localhost/api/always-on/status', {
    method: 'POST', body: JSON.stringify({ rpcId: 'baseline', payload: { pending: [{ sessionId: 'session-a', key: 'approval-existing', kind: 'approval' }] } }),
  }));
  assert.equal(response.status, 200);
  const recovered = await f.feed(); assert.equal(recovered.sessions[0].activeWaits[0].reason, 'approval');
  assert.equal(recovered.throughSequence, 0);
});
test('subagent status does not create a duplicate parent notification', async t => {
  const f = await fixture(t);
  f.callbacks.get('agent/status')({ agent: { id: 'child', session: { id: 'child', header: { origin: 'subagent' } } }, status: 'running' });
  assert.equal((await f.feed()).sessions.length, 1); assert.equal((await f.feed()).throughSequence, 0);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { EventModel } from '../lib/model.js';
import { LocalBridge } from '../lib/bridge.js';

async function fixture(t) {
  const dir = await mkdtemp(join(tmpdir(), 'always-on-bridge-'));
  const model = new EventModel('installation'); const bridge = new LocalBridge(model, dir); await bridge.start();
  const endpoint = JSON.parse(await readFile(join(dir, 'endpoint.json'), 'utf8'));
  t.after(async () => { await bridge.stop(); await rm(dir, { recursive: true, force: true }); });
  return { dir, bridge, model, base: `http://127.0.0.1:${endpoint.port}`, headers: { Authorization: `Bearer ${endpoint.token}` } };
}
test('loopback HTTP requires the application token and rejects browser origins', async t => {
  const f = await fixture(t);
  assert.equal((await fetch(f.base + '/poll')).status, 401);
  assert.equal((await fetch(f.base + '/poll', { headers: { ...f.headers, Origin: 'http://example.com' } })).status, 401);
  const result = await fetch(f.base + '/poll', { headers: f.headers }); assert.equal(result.status, 200); assert.equal((await result.json()).reset, true);
});
test('open remains pending until the client confirms the exact request', async t => {
  const f = await fixture(t); f.bridge.lastClientSeen = Date.now();
  const pending = fetch(f.base + '/open', { method: 'POST', headers: f.headers, body: JSON.stringify({ requestId: 'r1', sessionId: 's1' }) });
  const commands = await f.bridge.pollCommands(new AbortController().signal);
  assert.equal(commands[0].sessionId, 's1'); assert.equal(commands[0].requestId, 'r1');
  f.bridge.complete('wrong-request', 'opened'); assert.equal(f.bridge.pending.size, 1);
  f.bridge.complete('r1', 'opened'); assert.equal((await (await pending).json()).status, 'opened');
});
test('malformed targets and absent DSH client fail visibly', async t => {
  const f = await fixture(t);
  assert.equal((await fetch(f.base + '/open', { method: 'POST', headers: f.headers, body: '{}' })).status, 400);
  const response = await fetch(f.base + '/open', { method: 'POST', headers: f.headers, body: JSON.stringify({ requestId: 'r', sessionId: 'a' }) });
  assert.equal((await response.json()).status, 'disconnected');
});
test('long-poll wakes on an event and retains a consistent snapshot boundary', async t => {
  const f = await fixture(t);
  const response = fetch(`${f.base}/poll?after=0&epoch=${f.model.epoch}`, { headers: f.headers });
  setTimeout(() => f.model.running('a', true), 30);
  const body = await (await response).json(); assert.equal(body.throughSequence, 1); assert.equal(body.events[0].sequence, 1); assert.equal(body.sessions[0].state, 'working');
});
test('unloading a bridge removes its endpoint and preserves other files', async t => {
  const f = await fixture(t);
  const retained = join(f.dir, 'state.json');
  await writeFile(retained, '{"fixture":"keep"}');
  await f.bridge.stop();
  await assert.rejects(readFile(join(f.dir, 'endpoint.json')), { code: 'ENOENT' });
  assert.equal(await readFile(retained, 'utf8'), '{"fixture":"keep"}');
});
test('an old plugin disposal cannot remove an already published replacement endpoint', async t => {
  const f = await fixture(t);
  const replacement = new LocalBridge(new EventModel('installation'), f.dir);
  await replacement.start();
  try {
    const endpoint = JSON.parse(await readFile(join(f.dir, 'endpoint.json'), 'utf8'));
    assert.notEqual(endpoint.sourceEpoch, f.model.epoch);
    await f.bridge.stop();
    assert.equal(JSON.parse(await readFile(join(f.dir, 'endpoint.json'), 'utf8')).sourceEpoch, endpoint.sourceEpoch);
    const response = await fetch(`http://127.0.0.1:${endpoint.port}/poll`, { headers: { Authorization: `Bearer ${endpoint.token}` } });
    assert.equal(response.status, 200);
    const feed = await response.json();
    assert.equal(feed.sourceEpoch, endpoint.sourceEpoch); assert.equal(feed.reset, true);
  } finally { await replacement.stop(); }
});

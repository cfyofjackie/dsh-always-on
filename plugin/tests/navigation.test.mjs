import test from 'node:test';
import assert from 'node:assert/strict';
import { navigate } from '../lib/navigation.js';

function fixture({ exists = true, state = 'open' } = {}) {
  const row = { retainedBy: {} }; let selected;
  return { get selected() { return selected; },
    sessions: { refresh: async () => {}, list: { getSnapshot: () => ({ byId: exists ? { target: row } : {} }) }, binding: () => ({ session: { getSnapshot: () => ({ openState: state, removed: false }) } }) },
    uiWorkspace: { openSession: id => { selected = id; row.retainedBy.mainView = 1; } } };
}
test('exact session selection and opened history are both required', async () => {
  const ctx = fixture(); assert.equal(await navigate(ctx, 'target', new AbortController().signal), 'opened'); assert.equal(ctx.selected, 'target');
});
test('deleted targets are not substituted with a different session', async () => {
  const ctx = fixture({ exists: false }); assert.equal(await navigate(ctx, 'target', new AbortController().signal), 'not_found'); assert.equal(ctx.selected, undefined);
});
test('history errors are not reported as opened', async () => {
  assert.equal(await navigate(fixture({ state: 'error' }), 'target', new AbortController().signal), 'failed');
});
test('cancelled lifetime cannot perform navigation', async () => {
  const ctx = fixture(); const lifetime = new AbortController(); lifetime.abort();
  await assert.rejects(navigate(ctx, 'target', lifetime.signal)); assert.equal(ctx.selected, undefined);
});

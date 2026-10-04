import test from 'node:test';
import assert from 'node:assert/strict';
import { EventModel } from '../lib/model.js';

test('completion happens once at whole-agent idle, not at intermediate turns', () => {
  const m = new EventModel('installation'); m.running('a', true);
  assert.equal(m.history.filter(e => e.notify).length, 0);
  m.running('a', false, 'completed'); m.running('a', false, 'completed');
  assert.equal(m.history.filter(e => e.notify).length, 1);
  const first = m.records.get('a').runId;
  m.running('a', true); m.running('a', false, 'completed');
  assert.notEqual(m.records.get('a').runId, first);
  assert.equal(m.history.filter(e => e.notify).length, 2);
});
test('waiting identity deduplicates updates and does not end on idle', () => {
  const m = new EventModel('i'); m.running('a', true);
  m.waits('a', [{ actionId: 'q1', reason: 'question' }], true);
  m.waits('a', [{ actionId: 'q1', reason: 'question' }], true);
  m.running('a', false, 'completed');
  assert.equal(m.records.get('a').state, 'waiting');
  assert.equal(m.history.filter(e => e.notify).length, 1);
  m.waits('a', [], false); assert.equal(m.records.get('a').state, 'idle');
});
test('multiple waits remain until every action resolves', () => {
  const m = new EventModel('i'); m.running('a', true);
  m.waits('a', [{ actionId: 'q', reason: 'question' }, { actionId: 'p', reason: 'plan_review' }], true);
  m.waits('a', [{ actionId: 'p', reason: 'plan_review' }], true);
  assert.equal(m.records.get('a').state, 'waiting');
  assert.equal(m.history.filter(e => e.notify).length, 1);
  m.waits('a', [], true); assert.equal(m.records.get('a').state, 'working');
});
test('cancel and unknown outcomes do not falsely report success', () => {
  for (const outcome of ['aborted', 'interrupted', 'forked', 'unknown']) {
    const m = new EventModel('i'); m.running('a', true); m.running('a', false, outcome);
    assert.equal(m.records.get('a').state, 'idle'); assert.equal(m.history.some(e => e.notify), false);
  }
});
test('error, blocked and token ceiling provide distinct failure summaries', () => {
  for (const outcome of ['error', 'blocked', 'max-tokens']) {
    const m = new EventModel('i'); m.running('a', true); m.running('a', false, outcome);
    assert.equal(m.records.get('a').state, 'error'); assert.equal(m.history.at(-1).notify, true);
  }
});
test('first snapshot does not replay historical completions; valid cursor returns stable event IDs', () => {
  const m = new EventModel('i'); m.running('a', true); m.running('a', false, 'completed');
  assert.equal(m.feed(-1, '').events.length, 0);
  assert.equal(m.feed(0, m.epoch).events.length, 2);
  assert.equal(m.feed(0, m.epoch).events[1].eventId, m.history[1].eventId);
});
test('source restart and history overflow demand baseline without replay', () => {
  const m = new EventModel('i'); const r = m.ensure('a');
  for (let i = 0; i < 501; ++i) m.emit(r, 'session.progress');
  assert.equal(m.feed(0, m.epoch).reset, true);
  assert.equal(m.feed(400, 'old-epoch').reset, true);
});

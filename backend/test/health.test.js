const { test, before, after, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
process.env.NODE_ENV = 'test';
const mongoose = require('mongoose');
const app = require('../src/app');
const server = http.createServer(app);
let base;
before(async () => { await new Promise(r => server.listen(0, '127.0.0.1', r)); base = `http://127.0.0.1:${server.address().port}`; });
after(async () => { await new Promise(r => server.close(r)); mock.restoreAll(); });
test('liveness succeeds without MongoDB, while readiness fails closed', async () => {
  assert.equal((await fetch(base + '/health')).status, 200);
  const r = await fetch(base + '/ready'); assert.equal(r.status, 503);
  assert.deepEqual(await r.json(), { status: 'not_ready' });
});
test('readiness requires a successful bounded database ping and conceals errors', async () => {
  const conn = mongoose.connection, state = conn.readyState, db = conn.db;
  try {
    conn.readyState = 1;
    conn.db = { command: async (input, options) => { assert.deepEqual(input, { ping: 1 }); assert.equal(options.timeoutMS, 2000); } };
    assert.equal((await fetch(base + '/ready')).status, 200);
    conn.db = { command: async () => { throw new Error('private cluster diagnostics'); } };
    const r = await fetch(base + '/ready'); assert.equal(r.status, 503);
    assert.deepEqual(await r.json(), { status: 'not_ready' });
  } finally { conn.db = db; conn.readyState = state; }
});
test('read-only verification cannot accept mutation requests or claim traffic readiness', async () => {
  process.env.INFRA_READ_ONLY = 'true';
  try {
    for (const method of ['POST', 'PATCH', 'PUT', 'DELETE']) {
      assert.equal((await fetch(base + '/api/jobs', { method })).status, 503);
    }
    assert.equal((await fetch(base + '/ready')).status, 503);
  } finally { delete process.env.INFRA_READ_ONLY; }
});
test('development CORS permits both local admin origins without permitting arbitrary origins', async () => {
  for (const origin of ['http://localhost:3000', 'http://127.0.0.1:3000']) {
    const r = await fetch(base + '/api/admin/stats', { headers: { Origin: origin } });
    assert.equal(r.status, 401);
    assert.equal(r.headers.get('access-control-allow-origin'), origin);
  }
  const r = await fetch(base + '/api/admin/stats', { headers: { Origin: 'https://untrusted.invalid' } });
  assert.equal(r.headers.get('access-control-allow-origin'), null);
});

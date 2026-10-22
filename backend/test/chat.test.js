const { test, before, after, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = crypto.randomBytes(32).toString('hex');
const f = require('./fixtures');
f.install(mock);
const { ids } = f;
const Message = require('../src/models/Message');
const { signAccessToken } = require('../src/services/access.service');
const app = require('../src/app');
const server = http.createServer(app);
let base, saved;
mock.method(Message, 'create', async value => {
  const message = { ...value, _id: (saved.length + 200).toString(16).padStart(24, '0'), createdAt: new Date() };
  saved.push(message);
  return message;
});
mock.method(Message, 'find', filter => ({
  sort: () => ({ limit: async count => saved.filter(m => String(m.jobId) === String(filter.jobId) &&
    (!filter._id || m._id < filter._id.$lt)).slice().reverse().slice(0, count) }),
}));
before(async () => { await new Promise(resolve => server.listen(0, '127.0.0.1', resolve)); base = `http://127.0.0.1:${server.address().port}`; });
after(async () => { await new Promise(resolve => server.close(resolve)); mock.restoreAll(); });
beforeEach(() => {
  f.reset('unused-hash'); saved = [];
  require('../src/middleware/rate-limit.middleware').apiLimiter.resetKey('127.0.0.1');
});
function assigned() {
  Object.assign(f.data().Job[0], { status: 'accepted', acceptedBidId: ids.bid, mechanicId: ids.mechanic });
  f.data().Bid.push({ _id: ids.bid, jobId: ids.job, mechanicId: ids.mechanic,
    status: 'accepted', labourCost: 500, partsCost: 0, totalCost: 500, eta: 10 });
}
async function request(actor, method = 'GET', body, suffix = '') {
  const user = f.data().User.find(item => item._id === actor);
  const result = await fetch(`${base}/api/jobs/${ids.job}/messages${suffix}`, {
    method, headers: { Authorization: `Bearer ${signAccessToken(user)}`, 'Content-Type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  return { status: result.status, body: await result.json() };
}
test('chat is unavailable before confirmed assignment and to nonparticipants', async () => {
  assert.equal((await request(ids.driver)).status, 409);
  assigned();
  assert.equal((await request(ids.foreign)).status, 403);
  assert.equal((await request(ids.otherMechanicUser, 'POST', { text: 'Hello' })).status, 403);
  assert.equal((await request(ids.admin)).status, 403);
  assert.equal(saved.length, 0);
});
test('assigned driver and approved mechanic share persisted history', async () => {
  assigned();
  const sent = await request(ids.driver, 'POST', { text: '  Hello  ' });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.data.text, 'Hello');
  assert.equal(sent.body.data.senderId, ids.driver);
  assert.ok(sent.body.data.createdAt);
  const history = await request(ids.mechanicUser);
  assert.equal(history.status, 200);
  assert.deepEqual(history.body.data.map(m => m._id), [sent.body.data._id]);
  assert.equal((await request(ids.mechanicUser, 'POST', { text: 'On my way' })).status, 201);
  assert.equal((await request(ids.driver)).body.data.length, 2);
  const page = await request(ids.driver, 'GET', undefined, '?limit=1');
  assert.equal(page.body.data.length, 1);
  assert.equal(page.body.nextBefore, page.body.data[0]._id);
  const older = await request(ids.driver, 'GET', undefined, `?limit=1&before=${page.body.nextBefore}`);
  assert.equal(older.body.data[0]._id, sent.body.data._id);
});
test('chat validates content and pagination and rejects revoked mechanic', async () => {
  assigned();
  for (const text of ['', ' '.repeat(3), 'x'.repeat(2001)]) {
    assert.equal((await request(ids.driver, 'POST', { text })).status, 400);
  }
  assert.equal((await request(ids.driver, 'GET', undefined, '?limit=51')).status, 400);
  assert.equal((await request(ids.driver, 'GET', undefined, '?before=invalid')).status, 400);
  f.data().Mechanic[0].isApproved = false;
  assert.equal((await request(ids.mechanicUser)).status, 403);
  assert.equal(saved.length, 0);
});

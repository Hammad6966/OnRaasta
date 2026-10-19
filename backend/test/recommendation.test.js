const { test, before, after, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = require('node:crypto').randomBytes(32).toString('hex');
process.env.JWT_REFRESH_SECRET = require('node:crypto').randomBytes(32).toString('hex');
const f = require('./fixtures'); f.install(mock); const { ids } = f;
const { signAccessToken } = require('../src/services/access.service');
const { apiLimiter } = require('../src/middleware/rate-limit.middleware');
const presence = require('../src/services/presence.service');
const service = require('../src/services/recommendation.service');
const originalScore = service.client.score;
const axios = require('axios');
const server = http.createServer(require('../src/app')); let base, inputs, response;
function scored(input) {
  return { policyVersion: 'weighted_rules_v1', mechanics: input.mechanics.map(c => {
    const distanceKm = presence.haversine(input.job.location.lat, input.job.location.lng, c.lat, c.lng);
    const components = { skillMatch: 0, distanceScore: Math.max(0, 1 - distanceKm / 15), ratingScore: (c.rating ?? 0) / 5, priceScore: Math.max(0, 1 - c.totalMinor / 5000000) };
    return { bidId: c.bidId, mechanicId: c.mechanicId, totalMinor: c.totalMinor, distanceKm, ratingMissing: c.rating === null, matchedSkills: [], components,
      score: Number((0.25 * components.distanceScore + 0.25 * components.ratingScore + 0.15 * components.priceScore).toFixed(12)) };
  }).sort((a, b) => b.score - a.score || a.bidId.localeCompare(b.bidId)) };
}
mock.method(service.client, 'score', async input => { inputs.push(structuredClone(input)); return response(input); });
before(async () => { await new Promise(r => server.listen(0, '127.0.0.1', r)); base = `http://127.0.0.1:${server.address().port}`; });
after(async () => { await new Promise(r => server.close(r)); presence.clear(); mock.restoreAll(); });
beforeEach(() => { f.reset('fixture-only'); presence.clear(); inputs = []; response = scored; apiLimiter.resetKey('127.0.0.1'); });
function seed() {
  Object.assign(f.data().Job[0], { aiDiagnosis: { fault_class: 'dead_battery', confidence: 0.85, skill_required: 'Auto Electrician' } });
  Object.assign(f.data().Mechanic[0], { skills: ['Battery'], serviceRadius: 15, documents: { cnic_front: 'PRIVATE' } });
  f.data().Bid.push({ _id: ids.bid, jobId: ids.job, mechanicId: ids.mechanic, status: 'pending', labourCost: 500, partsCost: 0, totalCost: 500, eta: 10 });
}
async function online(userId = ids.mechanicUser, location = { lat: 31, lng: 74 }) {
  const user = f.data().User.find(u => u._id === userId);
  const socket = { id: userId, connected: true, handshake: { auth: { token: signAccessToken(user) } }, join: async () => {}, leave() {}, emit() {} };
  await presence.online(socket, { id: userId, role: 'mechanic' }, location); return socket;
}
async function request({ id = ids.driver, job = ids.job, query = '', token } = {}) {
  const r = await fetch(`${base}/api/jobs/${job}/recommendations${query}`, { headers: id || token ? { Authorization: `Bearer ${token || signAccessToken(f.data().User.find(u => u._id === id))}` } : {} });
  return { status: r.status, body: await r.json() };
}
test('owner recommendation maps actual Job/Bid/Mechanic IDs and exact quote', async () => {
  seed(); await online(); const r = await request(); assert.equal(r.status, 200);
  const row = r.body.data.rankings[0]; assert.equal(row.bidId, ids.bid); assert.equal(row.mechanicId, ids.mechanic); assert.equal(row.totalMinor, 50000); assert.equal(row.distanceKm, 0);
  assert.equal(r.body.data.jobId, ids.job); assert.equal(r.body.data.locationSource, 'foreground_presence'); assert.ok(Date.parse(r.body.data.expiresAt));
  assert.equal(inputs[0].mechanics[0].labourMinor, 50000); assert.equal(inputs[0].job.aiDiagnosis.fault_class, 'dead_battery');
  for (const privateField of ['PRIVATE', 'passwordHash', 'phone', 'documents', 'refreshToken']) assert.equal(JSON.stringify(r.body).includes(privateField), false);
});
test('missing/invalid auth, wrong Job and foreign owner rejected before scoring', async () => {
  seed(); await online();
  assert.equal((await request({ id: null })).status, 401); assert.equal((await request({ id: null, token: 'invalid' })).status, 401);
  assert.equal((await request({ job: 'invalid' })).status, 400); assert.equal((await request({ job: ids.otherJob })).status, 404);
  for (const id of [ids.foreign, ids.mechanicUser, ids.admin]) assert.equal((await request({ id })).status, 403);
  assert.equal(inputs.length, 0);
});
test('client cannot supply fabricated candidates or identity through query', async () => {
  seed(); await online();
  for (const query of ['?mechanicId=' + ids.otherMechanic, '?price=0', '?candidates=[]']) assert.equal((await request({ query })).status, 400);
  assert.equal(inputs.length, 0);
});
test('only pending bids on this Job are candidates', async () => {
  seed(); await online();
  for (const status of ['declined', 'expired', 'accepted']) { f.data().Bid[0].status = status; assert.deepEqual((await request()).body.data.rankings, []); }
  f.data().Bid[0].status = 'pending'; f.data().Bid[0].jobId = ids.otherJob; assert.deepEqual((await request()).body.data.rankings, []);
  assert.equal(inputs.length, 0);
});
test('assigned/completed/cancelled Job never recommends losing offers', async () => {
  seed(); await online();
  for (const status of ['accepted', 'en_route', 'arrived', 'in_progress', 'completed', 'cancelled']) { f.data().Job[0].status = status; assert.equal((await request()).status, 409); }
  assert.equal(inputs.length, 0);
});
test('unapproved and inactive accounts cannot remain candidates', async () => {
  seed(); await online(); f.data().Mechanic[0].isApproved = false;
  assert.deepEqual((await request()).body.data.rankings, []);
  f.data().Mechanic[0].isApproved = true; await online(); f.data().User.find(u => u._id === ids.mechanicUser).isActive = false;
  assert.deepEqual((await request()).body.data.rankings, []); assert.equal(inputs.length, 0);
});
test('offline profiles and stored shop coordinates are never GPS substitutes', async () => {
  seed(); Object.assign(f.data().Mechanic[0], { isOnline: true, lat: 31, lng: 74 });
  assert.deepEqual((await request()).body.data.rankings, []); assert.equal(inputs.length, 0);
});
test('stale presence lease excludes mechanic', async () => {
  seed(); await online(); const now = Date.now(); mock.method(Date, 'now', () => now + 91000);
  try { assert.deepEqual((await request()).body.data.rankings, []); assert.equal(inputs.length, 0); } finally { Date.now.mock.restore(); }
});
test('configured radius and real Haversine distance govern inclusion', async () => {
  seed(); f.data().Mechanic[0].serviceRadius = 1; await online(ids.mechanicUser, { lat: 31.02, lng: 74 });
  assert.deepEqual((await request()).body.data.rankings, []);
  f.data().Mechanic[0].serviceRadius = 15; const r = await request(); assert.equal(r.body.data.rankings.length, 1); assert.ok(Math.abs(r.body.data.rankings[0].distanceKm - 2.223898532891) < 1e-8);
});
test('missing persisted rating stays null and contributes zero', async () => {
  seed(); delete f.data().Mechanic[0].rating; await online(); const r = await request();
  assert.equal(inputs[0].mechanics[0].rating, null); assert.equal(r.body.data.rankings[0].rating, null); assert.equal(r.body.data.rankings[0].components.ratingScore, 0);
});
test('invalid quotes are excluded rather than receiving free-price scores', async () => {
  seed(); await online();
  for (const changes of [{ labourCost: 0, totalCost: 0 }, { totalCost: 0 }, { partsCost: -1 }, { totalCost: 500.001 }, { partsCost: 10, totalCost: 500 }]) {
    Object.assign(f.data().Bid[0], { labourCost: 500, partsCost: 0, totalCost: 500 }, changes); assert.deepEqual((await request()).body.data.rankings, []);
  }
  assert.equal(inputs.length, 0);
});
test('upstream failure returns controlled unavailable state without changing real bid', async () => {
  seed(); await online();
  response = async () => { const e = require('../src/utils/http-error')(503, 'Recommendations are unavailable. Real bids remain available; please retry.'); throw e; };
  const r = await request(); assert.equal(r.status, 503); assert.equal(r.body.success, false); assert.equal(f.data().Bid[0].status, 'pending');
});
test('malformed scorer response cannot inject foreign bids, prices or scores', async () => {
  seed(); await online();
  for (const patch of [{ bidId: ids.otherBid }, { mechanicId: ids.otherMechanic }, { totalMinor: 1 }, { score: 2 }, { distanceKm: 2 }, { matchedSkills: ['Invented skill'] }, { components: { skillMatch: 1, distanceScore: 1, ratingScore: 1, priceScore: 1 } }]) {
    response = input => { const r = scored(input); Object.assign(r.mechanics[0], patch); return r; };
    assert.equal((await request()).status, 503);
  }
});
test('availability/job changes during scoring invalidate the result', async () => {
  seed(); const socket = await online(); response = input => { socket.connected = false; return scored(input); };
  assert.equal((await request()).status, 409);
});
test('new bid during scoring cannot be hidden by an old ranking snapshot', async () => {
  seed(); await online(); await online(ids.otherMechanicUser);
  response = input => { f.data().Bid.push({ ...f.data().Bid[0], _id: ids.otherBid, mechanicId: ids.otherMechanic }); return scored(input); };
  assert.equal((await request()).status, 409);
});
test('scoring is read-only for diagnosis and financial snapshots', async () => {
  seed(); await online(); const job = structuredClone(f.data().Job[0]), bid = structuredClone(f.data().Bid[0]);
  await request(); assert.deepEqual(f.data().Job[0], job); assert.deepEqual(f.data().Bid[0], bid);
});
test('internal HTTP client has bounded timeout and never forwards user credentials', async () => {
  const oldUrl = process.env.AI_SERVICE_URL, oldTimeout = process.env.AI_RECOMMEND_TIMEOUT_MS;
  process.env.AI_SERVICE_URL = 'http://fixture.internal:8000'; process.env.AI_RECOMMEND_TIMEOUT_MS = '500';
  const calls = []; mock.method(axios, 'post', async (...args) => { calls.push(args); throw Object.assign(new Error('private transport'), { code: 'ECONNABORTED' }); });
  try {
    await assert.rejects(originalScore({ job: {}, mechanics: [] }), e => e.status === 503 && !e.message.includes('private'));
    assert.equal(calls[0][0], 'http://fixture.internal:8000/recommend'); assert.equal(calls[0][2].timeout, 500); assert.equal(calls[0][2].maxRedirects, 0); assert.equal(calls[0][2].headers.Authorization, undefined);
    process.env.AI_RECOMMEND_TIMEOUT_MS = '999999'; await assert.rejects(originalScore({}), e => e.status === 503); assert.equal(calls.length, 1);
    delete process.env.AI_SERVICE_URL; await assert.rejects(originalScore({}), e => e.status === 503);
  } finally { axios.post.mock.restore(); if (oldUrl === undefined) delete process.env.AI_SERVICE_URL; else process.env.AI_SERVICE_URL = oldUrl; if (oldTimeout === undefined) delete process.env.AI_RECOMMEND_TIMEOUT_MS; else process.env.AI_RECOMMEND_TIMEOUT_MS = oldTimeout; }
});

test('candidate scoring list is bounded and truncation is explicit', async () => {
  seed(); await online();
  for (let i = 0; i < 101; i++) {
    const id = (200 + i).toString(16).padStart(24, '0');
    const mechanicId = (500 + i).toString(16).padStart(24, '0'), userId = (1000 + i).toString(16).padStart(24, '0');
    f.data().User.push({ ...f.data().User.find(u => u._id === ids.mechanicUser), _id: userId });
    f.data().Mechanic.push({ ...f.data().Mechanic[0], _id: mechanicId, userId });
    await online(userId);
    f.data().Bid.push({ ...f.data().Bid[0], _id: id, mechanicId });
  }
  const r = await request(); assert.equal(r.status, 200); assert.equal(r.body.data.rankings.length, 100); assert.equal(r.body.data.truncated, true); assert.equal(inputs[0].mechanics.length, 100);
});
test('local Node-to-FastAPI HTTP integration with controlled Mongo fixtures', {
  skip: process.env.ONRAASTA_TEST_AI_HTTP !== 'true' && 'Set ONRAASTA_TEST_AI_HTTP=true to run the local Python service integration', timeout: 15000,
}, async () => {
  const { spawn } = require('node:child_process');
  const reserve = require('node:net').createServer(); await new Promise(r => reserve.listen(0, '127.0.0.1', r)); const port = reserve.address().port; await new Promise(r => reserve.close(r));
  const child = spawn('python', ['-m', 'uvicorn', 'main:app', '--host', '127.0.0.1', '--port', String(port), '--log-level', 'warning'], { cwd: require('node:path').resolve(__dirname, '../../ai-service'), windowsHide: true, stdio: 'ignore' });
  let startupError; child.on('error', e => { startupError = e; });
  const oldUrl = process.env.AI_SERVICE_URL, oldTimeout = process.env.AI_RECOMMEND_TIMEOUT_MS;
  try {
    let ready = false; const deadline = Date.now() + 8000;
    while (Date.now() < deadline && !startupError && child.exitCode === null) {
      try { ready = (await fetch(`http://127.0.0.1:${port}/health`, { signal: AbortSignal.timeout(300) })).ok; } catch { /* Process startup. */ }
      if (ready) break;
      await new Promise(r => setTimeout(r, 50));
    }
    assert.ok(ready, 'Local FastAPI fixture failed to start');
    process.env.AI_SERVICE_URL = `http://127.0.0.1:${port}`; process.env.AI_RECOMMEND_TIMEOUT_MS = '2000';
    seed(); await online(); response = input => originalScore(input);
    const r = await request(); assert.equal(r.status, 200); assert.equal(r.body.data.rankings[0].score, 0.9485);
    assert.deepEqual(r.body.data.rankings[0].matchedSkills, ['Battery']); assert.equal(r.body.data.rankings[0].bidId, ids.bid);
  } finally {
    if (oldUrl === undefined) delete process.env.AI_SERVICE_URL; else process.env.AI_SERVICE_URL = oldUrl;
    if (oldTimeout === undefined) delete process.env.AI_RECOMMEND_TIMEOUT_MS; else process.env.AI_RECOMMEND_TIMEOUT_MS = oldTimeout;
    const exited = new Promise(resolve => child.once('exit', resolve)); child.kill(); if (child.exitCode === null) await Promise.race([exited, new Promise(r => setTimeout(r, 1000))]);
  }
});

const { test, before, after, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = crypto.randomBytes(32).toString('hex');
process.env.JWT_REFRESH_SECRET = crypto.randomBytes(32).toString('hex');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const f = require('./fixtures');
f.install(mock);
const { ids } = f;
const { signAccessToken } = require('../src/services/access.service');
const { authLimiter, apiLimiter } = require('../src/middleware/rate-limit.middleware');
const app = require('../src/app');
const sockets = require('../src/socket/socket');
const server = http.createServer(app);
const io = sockets.initSocket(server);
let base;
const hash = bcrypt.hashSync('fixture-password-only', 4);
before(async () => { await new Promise(r => server.listen(0, '127.0.0.1', r)); base = `http://127.0.0.1:${server.address().port}`; });
after(async () => { await new Promise(r => io.close(r)); mock.restoreAll(); });
beforeEach(() => { f.reset(hash); authLimiter.resetKey('127.0.0.1'); apiLimiter.resetKey('127.0.0.1'); });
const token = id => signAccessToken(f.data().User.find(u => u._id === id));
async function request(method, path, id, body, overrideToken) {
  const headers = { 'Content-Type': 'application/json' };
  if (id || overrideToken) headers.Authorization = `Bearer ${overrideToken || token(id)}`;
  const response = await fetch(`${base}/api${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: response.status, body: await response.json() };
}
const jobBody = () => ({ description: 'Battery failed', location: { lat: 31, lng: 74 },
  aiDiagnosis: { fault_class: 'dead_battery', confidence: 0.85, cost_min: 800, cost_max: 3000, skill_required: 'Auto Electrician' } });
const bidBody = () => ({ jobId: ids.job, labourCost: 500, partsCost: 200, totalCost: 700, eta: 10 });
function bids() {
  f.data().Bid.push({ _id: ids.bid, jobId: ids.job, mechanicId: ids.mechanic, status: 'pending', labourCost: 500, partsCost: 0, totalCost: 500, eta: 10 },
    { _id: ids.otherBid, jobId: ids.job, mechanicId: ids.otherMechanic, status: 'pending', labourCost: 500, partsCost: 0, totalCost: 500, eta: 10 });
}

test('registration rejects admin, invalid and non-string roles before writes', async () => {
  for (const role of ['admin', 'superuser', '', null, { $ne: 'user' }]) {
    const r = await request('POST', '/auth/register', null, { name: 'Test User', phone: '3111234567', password: 'test-password', role });
    assert.equal(r.status, 400); assert.equal(f.data().User.length, 6);
    assert.equal(JSON.stringify(r.body).includes('test-password'), false);
  }
});
test('only driver can create a job, preserving supported input and R01 response', async () => {
  assert.equal((await request('POST', '/jobs', ids.mechanicUser, jobBody())).status, 403);
  const r = await request('POST', '/jobs', ids.driver, { ...jobBody(), vehicleId: ids.vehicle, photos: ['https://example.test/image.png'] });
  assert.equal(r.status, 201); assert.ok(r.body.data._id); assert.equal(r.body.data.userId, ids.driver);
  assert.deepEqual(r.body.data.aiDiagnosis, jobBody().aiDiagnosis); assert.equal(r.body.data.vehicleId, ids.vehicle);
});
test('job creation rejects all protected fields and foreign vehicle', async () => {
  for (const field of ['userId', 'mechanicId', 'status', 'acceptedBidId', 'review', 'finalCost']) {
    assert.equal((await request('POST', '/jobs', ids.driver, { ...jobBody(), [field]: ids.foreign })).status, 400);
  }
  assert.equal((await request('POST', '/jobs', ids.foreign, { ...jobBody(), vehicleId: ids.vehicle })).status, 403);
});
test('job payload bounds reject malformed coordinates/photos/diagnosis/description', async () => {
  for (const body of [{ ...jobBody(), location: { lat: 91, lng: 74 } },
    { ...jobBody(), photos: ['file:///private.png'] }, { ...jobBody(), photos: Array(4).fill('https://example.test/a.png') },
    { ...jobBody(), description: ' ' }, { ...jobBody(), aiDiagnosis: { fault_class: 'invented' } }]) {
    assert.equal((await request('POST', '/jobs', ids.driver, body)).status, 400);
  }
});
test('owner/admin/assigned mechanic may view; other driver/mechanic cannot', async () => {
  f.data().Job[0].mechanicId = ids.mechanic;
  for (const id of [ids.driver, ids.admin, ids.mechanicUser]) assert.equal((await request('GET', `/jobs/${ids.job}`, id)).status, 200);
  for (const id of [ids.foreign, ids.otherMechanicUser]) assert.equal((await request('GET', `/jobs/${ids.job}`, id)).status, 403);
  assert.equal((await request('GET', '/jobs/not-an-id', ids.driver)).status, 400);
  assert.equal((await request('GET', `/jobs/${ids.otherJob}`, ids.driver)).status, 404);
});
test('driver and unassigned/unapproved mechanics cannot advance lifecycle', async () => {
  Object.assign(f.data().Job[0], { status: 'accepted', mechanicId: ids.mechanic });
  for (const id of [ids.driver, ids.otherMechanicUser, ids.unapprovedUser, ids.admin]) {
    assert.equal((await request('PATCH', `/jobs/${ids.job}/status`, id, { status: 'arrived' })).status, 403);
  }
});
test('valid lifecycle requires all R06 stages in order', async () => {
  Object.assign(f.data().Job[0], { status: 'accepted', mechanicId: ids.mechanic, acceptedBidId: ids.bid });
  f.data().Bid.push({ _id: ids.bid, jobId: ids.job, mechanicId: ids.mechanic, status: 'accepted', labourCost: 500, partsCost: 0, totalCost: 500, eta: 10 });
  assert.equal((await request('PATCH', `/jobs/${ids.job}/status`, ids.mechanicUser, { status: 'completed' })).status, 409);
  for (const status of ['en_route', 'arrived', 'in_progress', 'completed']) {
    assert.equal((await request('PATCH', `/jobs/${ids.job}/status`, ids.mechanicUser, { status })).status, 200);
  }
  assert.equal((await request('PATCH', `/jobs/${ids.job}/status`, ids.mechanicUser, { status: 'en_route' })).status, 409);
  assert.equal((await request('PATCH', `/jobs/${ids.job}/status`, ids.admin, { status: 'cancelled' })).status, 409);
});
test('only owner/admin can cancel and closed jobs cannot reopen', async () => {
  assert.equal((await request('PATCH', `/jobs/${ids.job}/status`, ids.foreign, { status: 'cancelled' })).status, 403);
  assert.equal((await request('PATCH', `/jobs/${ids.job}/status`, ids.driver, { status: 'cancelled' })).status, 200);
  Object.assign(f.data().Job[0], { mechanicId: ids.mechanic });
  assert.equal((await request('PATCH', `/jobs/${ids.job}/status`, ids.mechanicUser, { status: 'en_route' })).status, 409);
});
test('concurrent lifecycle updates do not overwrite a changed state', async () => {
  Object.assign(f.data().Job[0], { status: 'accepted', mechanicId: ids.mechanic });
  const results = await Promise.all([request('PATCH', `/jobs/${ids.job}/status`, ids.mechanicUser, { status: 'en_route' }),
    request('PATCH', `/jobs/${ids.job}/status`, ids.mechanicUser, { status: 'en_route' })]);
  assert.deepEqual(results.map(r => r.status).sort(), [200, 409]);
});
test('review authorization, completion and bounds are enforced without exposing profile security fields', async () => {
  assert.equal((await request('POST', `/jobs/${ids.job}/review`, ids.foreign, { stars: 5 })).status, 403);
  assert.equal((await request('POST', `/jobs/${ids.job}/review`, ids.driver, { stars: 5 })).status, 409);
  Object.assign(f.data().Job[0], { status: 'completed', mechanicId: ids.mechanic, acceptedBidId: ids.bid });
  f.data().Bid.push({ _id: ids.bid, jobId: ids.job, mechanicId: ids.mechanic, status: 'accepted' });
  assert.equal((await request('POST', `/jobs/${ids.job}/review`, ids.driver, { stars: 5, comment: 'x'.repeat(301) })).status, 400);
  assert.equal((await request('POST', `/jobs/${ids.job}/review`, ids.driver, { stars: 5, comment: 'Good service' })).status, 200);
  assert.equal(f.data().Mechanic[0].rating, 5);
  assert.equal((await request('POST', `/jobs/${ids.job}/review`, ids.driver, { stars: 4 })).status, 409);
  const profile = await request('GET', '/users/profile', ids.driver);
  assert.equal(profile.status, 200);
  assert.equal('passwordHash' in profile.body.data, false);
  assert.equal('failedLoginAttempts' in profile.body.data, false);
});
test('bids require approved mechanic and authenticated identity', async () => {
  assert.equal((await request('POST', '/bids', ids.driver, bidBody())).status, 403);
  assert.equal((await request('POST', '/bids', ids.unapprovedUser, bidBody())).status, 403);
  assert.equal((await request('POST', '/bids', ids.mechanicUser, { ...bidBody(), mechanicId: ids.otherMechanic })).status, 403);
  const r = await request('POST', '/bids', ids.mechanicUser, bidBody());
  assert.equal(r.status, 201); assert.equal(r.body.bid.mechanicId, ids.mechanic);
});
test('cost, total and ETA validation; closed jobs never return to bidding', async () => {
  for (const fields of [{ labourCost: 499 }, { partsCost: -1 }, { totalCost: 999 }, { eta: 0 }, { eta: 1.2 }]) {
    assert.equal((await request('POST', '/bids', ids.mechanicUser, { ...bidBody(), ...fields })).status, 400);
  }
  f.data().Job[0].status = 'completed';
  assert.equal((await request('POST', '/bids', ids.mechanicUser, bidBody())).status, 409);
  assert.equal(f.data().Job[0].status, 'completed');
});
test('concurrent duplicate submissions produce exactly one pending bid', async () => {
  const results = await Promise.all([request('POST', '/bids', ids.mechanicUser, bidBody()), request('POST', '/bids', ids.mechanicUser, bidBody())]);
  assert.deepEqual(results.map(r => r.status).sort(), [201, 409]); assert.equal(f.data().Bid.length, 1);
});
test('foreign driver cannot accept or list bids', async () => {
  bids(); assert.equal((await request('PATCH', `/bids/${ids.bid}/accept`, ids.foreign)).status, 403);
  assert.equal((await request('GET', `/bids?jobId=${ids.job}`, ids.foreign)).status, 403);
  assert.equal(f.data().Job[0].status, 'bidding');
});
test('concurrent acceptance yields one winner and declines competitor', async () => {
  bids();
  const results = await Promise.all([request('PATCH', `/bids/${ids.bid}/accept`, ids.driver), request('PATCH', `/bids/${ids.otherBid}/accept`, ids.driver)]);
  assert.deepEqual(results.map(r => r.status).sort(), [200, 409]);
  assert.equal(f.data().Bid.filter(b => b.status === 'accepted').length, 1);
  assert.equal(f.data().Bid.filter(b => b.status === 'declined').length, 1);
  assert.equal(f.data().Job[0].acceptedBidId, f.data().Bid.find(b => b.status === 'accepted')._id);
});
test('revoked mechanics and nonpending bids cannot be accepted', async () => {
  bids(); f.data().Mechanic[0].isApproved = false;
  assert.equal((await request('PATCH', `/bids/${ids.bid}/accept`, ids.driver)).status, 403);
  f.data().Bid[0].status = 'expired';
  assert.equal((await request('PATCH', `/bids/${ids.bid}/accept`, ids.driver)).status, 409);
});
test('acceptance rolls back all state when a later database write fails', async t => {
  bids();
  t.mock.method(f.models.Bid, 'updateMany', () => { throw new Error('Private database write failure'); });
  const r = await request('PATCH', `/bids/${ids.bid}/accept`, ids.driver);
  assert.equal(r.status, 500);
  assert.equal(f.data().Job[0].status, 'bidding');
  assert.equal(f.data().Job[0].acceptedBidId, undefined);
  assert.equal(f.data().Bid.every(b => b.status === 'pending'), true);
});
test('missing, malformed, expired and refresh JWTs cannot authenticate', async () => {
  assert.equal((await request('GET', `/jobs/${ids.job}`)).status, 401);
  for (const t of ['invalid', jwt.sign({ id: ids.driver, tokenUse: 'access' }, process.env.JWT_SECRET, { expiresIn: -1 }),
    jwt.sign({ id: [ids.driver], tokenUse: 'access' }, process.env.JWT_SECRET, { expiresIn: '15m' }),
    jwt.sign({ id: ids.driver, tokenUse: 'refresh' }, process.env.JWT_SECRET, { expiresIn: '7d' }),
    jwt.sign({ id: ids.driver, tokenUse: 'access' }, crypto.randomBytes(32).toString('hex'), { expiresIn: '15m' })]) {
    assert.equal((await request('GET', `/jobs/${ids.job}`, null, undefined, t)).status, 401);
  }
});
test('live account status and role override token claims', async () => {
  const t = token(ids.driver); f.data().User[0].isActive = false;
  assert.equal((await request('GET', `/jobs/${ids.job}`, null, undefined, t)).status, 403);
  f.data().User[0].isActive = true; f.data().User[0].isVerified = false;
  assert.equal((await request('GET', `/jobs/${ids.job}`, null, undefined, t)).status, 403);
  f.data().User.shift();
  assert.equal((await request('GET', `/jobs/${ids.job}`, null, undefined, t)).status, 401);
});
test('demoted admin JWT cannot retain admin access', async () => {
  const t = token(ids.admin);
  f.data().User.find(u => u._id === ids.admin).role = 'user';
  assert.equal((await request('GET', '/admin/stats', null, undefined, t)).status, 403);
});
test('regular login preserves response, token lifetimes and token separation', async () => {
  const r = await request('POST', '/auth/login', null, { phone: '3001234567', password: 'fixture-password-only' });
  assert.equal(r.status, 200); assert.equal(r.body.user.id, ids.driver);
  const access = jwt.decode(r.body.accessToken); const refresh = jwt.decode(r.body.refreshToken);
  assert.equal(access.exp - access.iat, 900); assert.equal(refresh.exp - refresh.iat, 604800);
  assert.equal(refresh.tokenUse, 'refresh'); assert.equal('passwordHash' in r.body.user, false);
  assert.equal((await request('GET', `/jobs/${ids.job}`, null, undefined, r.body.refreshToken)).status, 401);
  assert.equal((await request('POST', '/auth/refresh', null, { refreshToken: r.body.accessToken })).status, 401);
  assert.equal((await request('POST', '/auth/refresh', null, { refreshToken: r.body.refreshToken })).status, 200);
  f.data().User[0].isActive = false;
  assert.equal((await request('POST', '/auth/refresh', null, { refreshToken: r.body.refreshToken })).status, 403);
});
test('development OTP remains local while production never uses the bypass', async () => {
  const original = Object.fromEntries(['NODE_ENV', 'DEV_OTP', 'TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN'].map(k => [k, process.env[k]]));
  const service = require('../src/services/twilio.service');
  try {
    process.env.DEV_OTP = String(crypto.randomInt(100000, 999999));
    process.env.NODE_ENV = 'development';
    assert.equal((await service.verifyOtp('3001234567', process.env.DEV_OTP)).status, 'approved');
    assert.equal((await service.verifyOtp('3001234567', 'wrong')).status, 'rejected');
    process.env.NODE_ENV = 'production';
    process.env.TWILIO_ACCOUNT_SID = ''; process.env.TWILIO_AUTH_TOKEN = '';
    await assert.rejects(service.verifyOtp('3001234567', process.env.DEV_OTP));
  } finally {
    for (const [key, value] of Object.entries(original)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
});
test('admin endpoints reject public/nonadmin access; admin has redacted listings', async () => {
  for (const route of ['stats', 'jobs-chart', 'faults-chart', 'recent-jobs', 'users', 'verification']) {
    assert.equal((await request('GET', `/admin/${route}`)).status, 401);
    assert.equal((await request('GET', `/admin/${route}`, ids.driver)).status, 403);
    const r = await request('GET', `/admin/${route}`, ids.admin); assert.equal(r.status, 200);
    for (const field of ['passwordHash', 'failedLoginAttempts', 'lockoutUntil']) assert.equal(JSON.stringify(r.body).includes(field), false);
  }
});
test('admin login works with typed access JWT and rejects inactive administrator', async () => {
  let r = await request('POST', '/admin/login', null, { email: 'admin@example.test', password: 'fixture-password-only' });
  assert.equal(r.status, 200); assert.equal(jwt.decode(r.body.token).tokenUse, 'access');
  assert.equal((await request('GET', '/admin/stats', null, undefined, r.body.token)).status, 200);
  f.data().User.find(u => u._id === ids.admin).isActive = false;
  r = await request('POST', '/admin/login', null, { email: 'admin@example.test', password: 'fixture-password-only' });
  assert.equal(r.status, 403);
});
test('verification rejects invalid decisions, revokes approval and blocks future bids', async () => {
  assert.equal((await request('PATCH', `/admin/verification/${ids.mechanic}`, ids.admin, { status: 'anything' })).status, 400);
  assert.equal((await request('PATCH', `/admin/verification/${ids.mechanic}`, ids.driver, { status: 'rejected' })).status, 403);
  assert.equal((await request('PATCH', `/admin/verification/${ids.mechanic}`, ids.admin, { action: 'revoke', reason: 'Manual approval withdrawn', expectedVersion: 0 })).status, 200);
  assert.equal(f.data().Mechanic[0].isApproved, false);
  assert.equal((await request('POST', '/bids', ids.mechanicUser, bidBody())).status, 403);
});
test('safe errors conceal database details and unsupported transactions fail closed', async t => {
  const stub = t.mock.method(f.models.Job, 'findById', () => { throw new Error('private database details'); });
  let r = await request('GET', `/jobs/${ids.job}`, ids.driver);
  assert.equal(r.status, 500); assert.equal(JSON.stringify(r.body).includes('private database'), false);
  stub.mock.restore();
  const mongoose = require('mongoose');
  t.mock.method(mongoose, 'startSession', async () => ({
    withTransaction: async () => { throw Object.assign(new Error('Transaction unsupported'), { code: 20 }); },
    endSession: async () => {},
  }));
  r = await request('POST', '/bids', ids.mechanicUser, bidBody());
  assert.equal(r.status, 503); assert.equal(f.data().Bid.length, 0);
});
test('admin login uses auth rate limit and general API limiter is enforced', async () => {
  for (let i = 0; i < 10; i++) assert.equal((await request('POST', '/admin/login', null, {})).status, 400);
  assert.equal((await request('POST', '/admin/login', null, {})).status, 429);
  apiLimiter.resetKey('127.0.0.1');
  for (let i = 0; i < 100; i++) await request('GET', `/jobs/${ids.job}`);
  assert.equal((await request('GET', `/jobs/${ids.job}`)).status, 429);
});

// Native WebSocket speaks the small Engine.IO/Socket.IO framing needed here;
// tests use the actual server handshake and listeners without another dependency.
function connect(t) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(base.replace('http:', 'ws:') + '/socket.io/?EIO=4&transport=websocket');
    let sequence = 0; const pending = new Map();
    const timeout = setTimeout(() => { ws.close(); reject(new Error('Socket handshake timeout')); }, 3000);
    ws.addEventListener('message', e => {
      const packet = String(e.data);
      if (packet.startsWith('0')) ws.send('40' + JSON.stringify({ token: t }));
      else if (packet === '2') ws.send('3');
      else if (packet.startsWith('44')) { clearTimeout(timeout); ws.close(); reject(new Error('Unauthorized')); }
      else if (packet.startsWith('40')) {
        clearTimeout(timeout);
        resolve({ ws, async emit(event, payload) {
          const id = sequence++;
          return new Promise((done, fail) => {
            const timer = setTimeout(() => fail(new Error('Missing acknowledgment')), 3000);
            pending.set(String(id), data => { clearTimeout(timer); done(data[0]); });
            ws.send('42' + id + JSON.stringify([event, payload]));
          });
        } });
      } else if (packet.startsWith('43')) {
        const match = /^43(\d+)(\[.*)$/.exec(packet);
        if (match) { pending.get(match[1])?.(JSON.parse(match[2])); pending.delete(match[1]); }
      }
    });
    ws.addEventListener('error', () => { clearTimeout(timeout); reject(new Error('Socket connection failed')); });
  });
}
test('Socket.IO rejects missing/invalid/expired/inactive handshakes', async () => {
  for (const t of [undefined, 'invalid', jwt.sign({ id: ids.driver, tokenUse: 'access' }, process.env.JWT_SECRET, { expiresIn: -1 })]) await assert.rejects(connect(t));
  const t = token(ids.driver); f.data().User[0].isActive = false; await assert.rejects(connect(t));
});
test('Socket.IO joins own room and forbids foreign/arbitrary/job room access', async () => {
  const c = await connect(token(ids.foreign));
  try {
    assert.equal((await c.emit('join_room', { room: `user_${ids.foreign}` })).success, true);
    for (const room of [`user_${ids.driver}`, 'admin', `job_${ids.job}`]) assert.equal((await c.emit('join_room', { room })).status, 403);
    const connected = [...io.sockets.sockets.values()].find(s => s.data.user.id === ids.foreign);
    assert.equal(connected.rooms.has(`user_${ids.driver}`), false);
  } finally { c.ws.close(); }
});
test('owner/assigned mechanic/admin can join legitimate job room', async () => {
  f.data().Job[0].mechanicId = ids.mechanic;
  for (const id of [ids.driver, ids.mechanicUser, ids.admin]) {
    const c = await connect(token(id));
    try { assert.equal((await c.emit('join_room', { room: `job_${ids.job}` })).success, true); }
    finally { c.ws.close(); }
  }
});
test('Socket.IO rejects forged events and spoofed/unapproved presence', async () => {
  const c = await connect(token(ids.mechanicUser));
  try {
    assert.equal((await c.emit('mechanic:go_online', { mechanicId: ids.otherMechanic, lat: 31, lng: 74 })).status, 403);
    assert.equal((await c.emit('mechanic:go_online', { mechanicId: ids.mechanic, lat: 91, lng: 74 })).status, 400);
    assert.equal((await c.emit('mechanic:go_online', { mechanicId: ids.mechanic, lat: 31, lng: 74 })).success, true);
    for (const event of ['job:created', 'job:new_request', 'bid:new', 'bid:accepted', 'job:status_changed', 'job:mechanic_location', 'doc:status_update', 'mechanic:approval_changed']) {
      assert.equal((await c.emit(event, { jobId: ids.job, status: 'completed' })).status, 403);
    }
    assert.equal(f.data().Job[0].status, 'bidding');
    f.data().Mechanic[0].isApproved = false;
    assert.equal((await c.emit('mechanic:update_location', { lat: 31, lng: 74 })).status, 403);
  } finally { c.ws.close(); }
  const unapproved = await connect(token(ids.unapprovedUser));
  try { assert.equal((await unapproved.emit('mechanic:go_online', { lat: 31, lng: 74 })).status, 403); }
  finally { unapproved.ws.close(); }
});
test('dispatch rechecks approval and administrative revocation removes presence', async t => {
  const c = await connect(token(ids.mechanicUser));
  try {
    assert.equal((await c.emit('mechanic:go_online', { mechanicId: ids.mechanic, lat: 31, lng: 74 })).success, true);
    const targets = [];
    const original = io.to.bind(io);
    t.mock.method(io, 'to', room => { const target = original(room); return { emit(event, payload) { if (event === 'job:new_request') targets.push(room); return target.emit(event, payload); } }; });
    await sockets.broadcastJobToMechanics({ jobId: ids.job, lat: 31, lng: 74 });
    assert.equal(targets.length, 1);
    assert.equal((await request('PATCH', `/admin/verification/${ids.mechanic}`, ids.admin, { action: 'revoke', reason: 'Approval withdrawn', expectedVersion: 0 })).status, 200);
    await sockets.broadcastJobToMechanics({ jobId: ids.job, lat: 31, lng: 74 });
    assert.equal(targets.length, 1);
    assert.equal((await c.emit('mechanic:go_online', { lat: 31, lng: 74 })).status, 403);
  } finally { c.ws.close(); }
});

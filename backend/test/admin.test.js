const { test, before, after, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = require('node:crypto').randomBytes(32).toString('hex');
process.env.JWT_REFRESH_SECRET = require('node:crypto').randomBytes(32).toString('hex');
const f = require('./fixtures'); f.install(mock); const { ids } = f;
const { signAccessToken, authenticateAccessToken } = require('../src/services/access.service');
const { apiLimiter } = require('../src/middleware/rate-limit.middleware');
const presence = require('../src/services/presence.service');
const sockets = require('../src/socket/socket');
const server = http.createServer(require('../src/app')); const io = sockets.initSocket(server); let base;
before(async () => { await new Promise(r => server.listen(0, '127.0.0.1', r)); base = `http://127.0.0.1:${server.address().port}`; });
after(async () => { await new Promise(r => io.close(r)); mock.restoreAll(); });
beforeEach(() => { f.reset('fixture-only'); presence.clear(); apiLimiter.resetKey('127.0.0.1'); });
async function request(path, method = 'GET', body, id = ids.admin, override) {
  const token = override || (id ? signAccessToken(f.data().User.find(u => u._id === id)) : null);
  const r = await fetch(base + '/api' + path, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text(); return { status: r.status, body: text.startsWith('{') ? JSON.parse(text) : {} };
}
const decide = (id, action, version = 0, reason = 'Controlled manual profile review') => request(`/admin/verification/${id}`, 'PATCH', { action, expectedVersion: version, reason });
const suspend = (id, active = false, version = 0) => request(`/admin/users/${id}/status`, 'PATCH', { isActive: active, expectedVersion: version, reason: 'Controlled account decision' });
test('all management endpoints reject public and non-admin access', async () => {
  for (const path of ['/admin/users', `/admin/users/${ids.driver}`, '/admin/verification', '/admin/audit-logs']) {
    assert.equal((await request(path, 'GET', undefined, null)).status, 401);
    for (const id of [ids.driver, ids.mechanicUser]) assert.equal((await request(path, 'GET', undefined, id)).status, 403);
  }
});
test('listings paginate safely, search literal prefixes and filter accounts', async () => {
  let r = await request('/admin/users?role=mechanic&limit=1&page=2');
  assert.equal(r.status, 200); assert.equal(r.body.data.length, 1); assert.equal(r.body.pagination.total, 3); assert.equal(r.body.pagination.hasMore, true);
  f.data().User[0].name = 'A.* literal';
  r = await request('/admin/users?search=A.%2A'); assert.equal(r.body.data.length, 1); assert.equal(r.body.data[0]._id, ids.driver);
  assert.equal((await request('/admin/users?search=mechanic')).body.pagination.total, 3);
  assert.equal((await request('/admin/users?approval=pending')).body.data[0]._id, ids.unapprovedUser);
  await suspend(ids.driver);
  assert.equal((await request('/admin/users?active=false')).body.data[0]._id, ids.driver);
});
test('invalid queries, object injection and excessive pagination rejected', async () => {
  for (const query of ['limit=51', 'page=201', 'role=admin', 'active=no', 'approval=verified', 'search[$ne]=x', 'sort=passwordHash']) assert.equal((await request('/admin/users?' + query)).status, 400);
});
test('safe summaries and details redact security fields, contacts and document URLs', async () => {
  Object.assign(f.data().User[0], { passwordHash: 'private-hash', otp: 'private-otp', emergencyContacts: [{ phone: 'private-contact' }] });
  f.data().Mechanic[0].documents = { cnic_front: 'private-front', cnic_back: 'private-back', permit_url: 'private-permit', status: 'pending' };
  for (const path of ['/admin/users', `/admin/users/${ids.driver}`, '/admin/verification', `/admin/users/${ids.mechanicUser}`]) {
    const r = await request(path); assert.equal(r.status, 200);
    for (const secret of ['private-hash', 'private-otp', 'private-contact', 'private-front', 'private-back', 'private-permit', 'passwordHash', 'failedLoginAttempts', 'lockoutUntil', 'tokenHash']) assert.equal(JSON.stringify(r.body).includes(secret), false);
  }
});
test('suspension is persisted with audit, invalidates access/refresh and preserves job history', async () => {
  const old = signAccessToken(f.data().User[0]);
  f.data().RefreshSession.push({ _id: ids.bid, userId: ids.driver, revokedAt: null });
  const jobs = structuredClone(f.data().Job);
  const r = await suspend(ids.driver); assert.equal(r.status, 200); assert.equal(r.body.data.isActive, false);
  assert.equal((await request('/users/profile', 'GET', undefined, null, old)).status, 403);
  assert.ok(f.data().RefreshSession[0].revokedAt); assert.deepEqual(f.data().Job, jobs);
  assert.equal(f.data().AdminLog[0].action, 'account_suspended');
  assert.equal(f.data().AdminLog[0].adminId, ids.admin);
  assert.deepEqual(f.data().AdminLog[0].previous, { isActive: true });
});
test('reactivation retains history and never restores revoked refresh sessions', async () => {
  await suspend(ids.driver); const r = await suspend(ids.driver, true, 1);
  assert.equal(r.status, 200); assert.equal(r.body.data.isActive, true); assert.equal(f.data().AdminLog.length, 2);
  assert.equal((await request('/users/profile', 'GET', undefined, ids.driver)).status, 200);
});
test('administrator accounts cannot be suspended or edited through account management', async () => {
  assert.equal((await suspend(ids.admin)).status, 403);
  assert.equal((await request(`/admin/users/${ids.admin}`)).status, 404);
  assert.equal(f.data().AdminLog.length, 0);
});
test('malformed mutations and actor/credential mass assignment rejected', async () => {
  for (const extra of [{ role: 'admin' }, { adminId: ids.foreign }, { passwordHash: 'x' }, { reason: '' }, { reason: '<script>' }, { expectedVersion: -1 }, { isActive: 'false' }]) {
    const r = await request(`/admin/users/${ids.driver}/status`, 'PATCH', { isActive: false, expectedVersion: 0, reason: 'Valid reason', ...extra }); assert.equal(r.status, 400);
  }
  assert.equal(f.data().AdminLog.length, 0);
});
test('pending mechanic approved manually without promoting missing documents', async () => {
  const r = await decide(ids.unapproved, 'approve'); assert.equal(r.status, 200);
  assert.equal(r.body.data.isApproved, true); assert.equal(r.body.data.accountApprovalStatus, 'approved');
  assert.equal(r.body.data.documents.status, 'draft'); assert.equal(r.body.data.documents.evidenceAvailable, false);
  assert.equal(r.body.data.documents.verificationAvailable, true);
  assert.equal(r.body.data.approval.method, 'manual_profile_review'); assert.equal(r.body.data.approval.decidedBy, ids.admin);
  assert.equal(f.data().AdminLog[0].targetId, ids.unapproved);
});
test('rejection and revocation require explicit reasons and legitimate transitions', async () => {
  assert.equal((await decide(ids.unapproved, 'reject', 0, '')).status, 400);
  assert.equal((await decide(ids.mechanic, 'reject')).status, 409);
  assert.equal((await decide(ids.unapproved, 'revoke')).status, 409);
  assert.equal((await decide(ids.unapproved, 'reject')).body.data.accountApprovalStatus, 'rejected');
  assert.equal((await decide(ids.unapproved, 'reject', 1)).status, 409);
  assert.equal((await decide(ids.mechanic, 'revoke')).body.data.accountApprovalStatus, 'revoked');
  assert.equal((await decide(ids.unapproved, 'approve', 1)).status, 200);
});
test('legacy document verification input is rejected instead of fabricating evidence', async () => {
  for (const status of ['verified', 'rejected']) assert.equal((await request(`/admin/verification/${ids.unapproved}`, 'PATCH', { status, rejectionReason: 'Old client' })).status, 400);
  assert.equal(f.data().Mechanic[2].isApproved, false); assert.equal(f.data().AdminLog.length, 0);
});
test('approval cannot activate inactive/unverified mechanics', async () => {
  const u = f.data().User.find(u => u._id === ids.unapprovedUser); u.isActive = false;
  assert.equal((await decide(ids.unapproved, 'approve')).status, 409);
  u.isActive = true; u.isVerified = false;
  assert.equal((await decide(ids.unapproved, 'approve')).status, 409); assert.equal(f.data().AdminLog.length, 0);
});
test('existing document verification evidence is preserved through manual decisions', async () => {
  f.data().Mechanic[0].documents = { status: 'verified', cnic_front: 'recorded-front', cnic_back: 'recorded-back' };
  await decide(ids.mechanic, 'revoke'); await decide(ids.mechanic, 'approve', 1);
  assert.equal(f.data().Mechanic[0].documents.status, 'verified'); assert.equal(f.data().Mechanic[0].documents.cnic_front, 'recorded-front');
});
test('critical qualification edit invalidates stale approval and can be manually reapproved', async () => {
  f.data().Mechanic[0].documents = { status: 'rejected', cnic_front: 'existing-front', cnic_back: 'existing-back' };
  const r = await request('/mechanics/profile', 'PATCH', { skills: ['Battery'] }, ids.mechanicUser); assert.equal(r.status, 200);
  assert.equal(r.body.data.isApproved, false); assert.equal(r.body.data.accountApprovalStatus, 'pending');
  assert.equal(r.body.data.documents.status, 'rejected');
  assert.equal((await decide(ids.mechanic, 'approve', 0)).status, 409);
  assert.equal((await decide(ids.mechanic, 'approve', f.data().Mechanic[0].__v)).status, 200);
});
test('concurrent admin decisions yield one winner and one audit record', async () => {
  const r = await Promise.all([decide(ids.unapproved, 'approve'), decide(ids.unapproved, 'reject')]);
  assert.deepEqual(r.map(v => v.status).sort(), [200, 409]); assert.equal(f.data().AdminLog.length, 1);
});
test('concurrent account updates conflict rather than creating duplicate audit records', async () => {
  const r = await Promise.all([suspend(ids.driver), suspend(ids.driver)]);
  assert.deepEqual(r.map(v => v.status).sort(), [200, 409]); assert.equal(f.data().AdminLog.length, 1);
});
test('audit write failure rolls back all account and approval changes', async () => {
  const stub = mock.method(f.models.AdminLog, 'create', async () => { throw new Error('private persistence failure'); });
  try {
    let r = await suspend(ids.driver); assert.equal(r.status, 500); assert.equal(f.data().User[0].isActive, true); assert.equal(JSON.stringify(r.body).includes('private persistence'), false);
    r = await decide(ids.unapproved, 'approve'); assert.equal(r.status, 500); assert.equal(f.data().Mechanic[2].isApproved, false);
    assert.equal(f.data().AdminLog.length, 0);
  } finally { stub.mock.restore(); }
});
test('audit endpoint is bounded, target scoped, append-only and records server actor/time', async () => {
  await suspend(ids.driver); await decide(ids.unapproved, 'approve');
  const r = await request(`/admin/audit-logs?targetId=${ids.driver}&limit=1`); assert.equal(r.status, 200);
  assert.equal(r.body.data.length, 1); assert.equal(r.body.data[0].adminId, ids.admin); assert.ok(r.body.data[0].createdAt);
  assert.equal((await request('/admin/audit-logs?limit=51')).status, 400);
  assert.equal((await request('/admin/audit-logs?targetId=bad')).status, 400);
  assert.equal((await request(`/admin/audit-logs/${r.body.data[0]._id}`, 'PATCH', { reason: 'overwrite' })).status, 404);
  const Model = require('../src/models/AdminLog');
  assert.ok(new Model({ adminId: ids.admin, targetId: ids.driver, targetType: 'User', action: 'account_suspended', reason: 'Valid', previous: { isActive: true }, next: { isActive: false } }).validateSync() === undefined);
  assert.throws(() => new Model({ passwordHash: 'never log' }));
});
test('applications show accurate pending/rejected/revoked counts and filters', async () => {
  f.data().Mechanic[2].documents = { status: 'rejected' };
  const pending = await request('/admin/verification?approval=pending');
  assert.equal(pending.body.counts.pending, 1); assert.equal(pending.body.data[0].accountApprovalStatus, 'pending');
  await decide(ids.unapproved, 'reject'); await decide(ids.mechanic, 'revoke');
  const r = await request('/admin/verification?approval=rejected'); assert.equal(r.status, 200);
  assert.equal(r.body.data.length, 1); assert.equal(r.body.counts.rejected, 1); assert.equal(r.body.counts.revoked, 1); assert.equal(r.body.counts.approved, 1);
  assert.equal((await request('/admin/verification?approval=pending')).body.data.length, 0);
});
test('dashboard counts eligible approved mechanics and canonical active states', async () => {
  f.data().User.find(u => u._id === ids.otherMechanicUser).isActive = false;
  f.data().Job[0].status = 'arrived';
  const r = await request('/admin/stats'); assert.equal(r.status, 200);
  assert.equal(r.body.data.totalUsers, 2); assert.equal(r.body.data.approvedMechanics, 1); assert.equal(r.body.data.activeJobs, 1); assert.equal(r.body.data.pendingVerifications, 1);
  assert.equal(r.body.data.jobsByStatus.arrived, 1); assert.equal(Object.keys(r.body.data.jobsByStatus).length, 8);
});
test('dashboard finances use only valid completed R12 snapshots, never quotes or missing history', async () => {
  const money = require('../src/services/accounting.service');
  Object.assign(f.data().Job[0], { status: 'completed', acceptedBidId: ids.bid, mechanicId: ids.mechanic, accounting: money.completedSnapshot(money.pricing({ _id: ids.bid, labourCost: 500.1, partsCost: 0, totalCost: 500.1 }), new Date()) });
  f.data().Job.push({ _id: ids.otherJob, status: 'completed' }, { _id: ids.otherBid, status: 'pending', finalCost: 99999 });
  const r = await request('/admin/stats'); assert.equal(r.body.data.bookedTotals.grossMinor, '50010');
  assert.equal(r.body.data.bookedCommissionMinor, '7502'); assert.equal(r.body.data.bookedTotals.unpricedJobs, 1); assert.equal(r.body.data.revenueBasis, 'booked_not_paid');
});
async function onlineMechanic() {
  const token = signAccessToken(f.data().User.find(u => u._id === ids.mechanicUser)); const events = [];
  const socket = { id: 'admin-presence-fixture', connected: true, handshake: { auth: { token } }, join: async () => {}, leave: () => {}, emit: (name, payload) => events.push({ name, payload }) };
  await presence.online(socket, await authenticateAccessToken(token), { lat: 31, lng: 74 });
  return { socket, events };
}
test('suspension and approval revocation immediately remove mechanic discovery presence', async () => {
  const { events } = await onlineMechanic(); assert.equal(presence.isOnline(ids.mechanic), true);
  assert.equal((await suspend(ids.mechanicUser)).status, 200); assert.equal(presence.isOnline(ids.mechanic), false); assert.ok(events.some(e => e.name === 'mechanic:availability'));
  assert.equal((await presence.nearby(31, 74)).length, 0);
  await suspend(ids.mechanicUser, true, 1); await onlineMechanic();
  assert.equal((await decide(ids.mechanic, 'revoke', 2)).status, 200); assert.equal(presence.isOnline(ids.mechanic), false);
});
test('suspension disconnects all live account socket namespaces', () => {
  let disconnected = 0; const notices = [];
  const fake = { data: { user: { id: ids.driver } }, id: 'fake-driver', emit: (e, p) => notices.push(p), disconnect: () => disconnected++ };
  io.sockets.sockets.set(fake.id, fake);
  try { sockets.revokeAccount(ids.driver); assert.equal(disconnected, 1); assert.equal(notices[0].status, 403); }
  finally { io.sockets.sockets.delete(fake.id); }
});
test('approval publication is private, carries no document evidence and clients cannot determine actor', async () => {
  const captured = []; const stub = mock.method(io, 'to', room => ({ emit: (event, payload) => captured.push({ room, event, payload }) }));
  try {
    await decide(ids.unapproved, 'approve');
    assert.equal(captured[0].room, `user_${ids.unapprovedUser}`); assert.equal(captured[0].event, 'mechanic:approval_changed');
    assert.deepEqual(Object.keys(captured[0].payload).sort(), ['accountApprovalStatus', 'isApproved', 'mechanicId']);
  } finally { stub.mock.restore(); }
});

test('suspension between middleware authentication and transaction rejects in-flight bid mutations', async () => {
  const mongoose = require('mongoose');
  const original = mongoose.startSession.bind(mongoose);
  f.data().Bid.push({ _id: ids.bid, jobId: ids.job, mechanicId: ids.mechanic, status: 'pending', labourCost: 500, partsCost: 0, totalCost: 500, eta: 10 });
  let target = ids.mechanicUser;
  const stub = mock.method(mongoose, 'startSession', async () => {
    f.data().User.find(u => u._id === target).isActive = false;
    return original();
  });
  try {
    const r = await request('/bids', 'POST', { jobId: ids.job, labourCost: 500, partsCost: 0, totalCost: 500, eta: 10 }, ids.mechanicUser);
    assert.equal(r.status, 403); assert.equal(f.data().Bid.length, 1);
    target = ids.driver;
    const accepted = await request(`/bids/${ids.bid}/accept`, 'PATCH', undefined, ids.driver);
    assert.equal(accepted.status, 403); assert.equal(f.data().Job[0].status, 'bidding'); assert.equal(f.data().Bid[0].status, 'pending');
  } finally { stub.mock.restore(); }
});

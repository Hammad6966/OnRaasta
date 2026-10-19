const { test, before, after, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = require('node:crypto').randomBytes(32).toString('hex');
process.env.JWT_REFRESH_SECRET = require('node:crypto').randomBytes(32).toString('hex');
const f = require('./fixtures'); f.install(mock); const { ids } = f;
const money = require('../src/services/accounting.service');
const { signAccessToken } = require('../src/services/access.service');
const { apiLimiter } = require('../src/middleware/rate-limit.middleware');
const server = http.createServer(require('../src/app')); let base;
before(async () => { await new Promise(r => server.listen(0, '127.0.0.1', r)); base = `http://127.0.0.1:${server.address().port}`; });
after(async () => { await new Promise(r => server.close(r)); mock.restoreAll(); });
beforeEach(() => { f.reset('fixture-only'); apiLimiter.resetKey('127.0.0.1'); });
async function request(path, id = ids.driver, method = 'GET', body) {
  const r = await fetch(base + '/api' + path, { method, headers: { 'Content-Type': 'application/json', ...(id ? { Authorization: `Bearer ${signAccessToken(f.data().User.find(u => u._id === id))}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: r.status, body: await r.json() };
}
function assigned({ status = 'in_progress', total = 1100.75, parts = 200.25, labour = 900.5, frozen = true } = {}) {
  const bid = { _id: ids.bid, jobId: ids.job, mechanicId: ids.mechanic, status: 'accepted', labourCost: labour, partsCost: parts, totalCost: total, eta: 10 };
  f.data().Bid.push(bid);
  Object.assign(f.data().Job[0], { status, mechanicId: ids.mechanic, acceptedBidId: ids.bid, statusVersion: 0, createdAt: new Date('2026-01-01T10:00:00Z'), ...(frozen ? { agreedPricing: money.pricing(bid) } : {}) });
}
const complete = () => request(`/jobs/${ids.job}/status`, ids.mechanicUser, 'PATCH', { status: 'completed' });
const earnings = (query = '') => request('/mechanics/earnings' + query, ids.mechanicUser);
function booked(id, date, amount = 1000, actor = ids.driver, mech = ids.mechanic) {
  const bidId = (BigInt('0x' + id) + 1000n).toString(16).padStart(24, '0');
  return { _id: id, userId: actor, mechanicId: mech, acceptedBidId: bidId, status: 'completed', description: 'Persisted repair', createdAt: new Date(date), completedAt: new Date(date), accounting: money.completedSnapshot(money.pricing({ _id: bidId, labourCost: amount, partsCost: 0, totalCost: amount }), new Date(date)) };
}
test('decimal PKR converts to integer paisa without binary rounding', () => {
  assert.equal(money.minor(900.5), 90050); assert.equal(money.minor(200.25), 20025); assert.equal(money.minor(0.1), 10);
  for (const value of [-1, NaN, Infinity, '500', 500.001, 0.1 + 0.2]) assert.throws(() => money.minor(value));
});
for (const [gross, commission, net] of [[500, 7500, 42500], [500.01, 7500, 42501], [500.03, 7500, 42503], [500.1, 7502, 42508], [1100.75, 16511, 93564]]) {
  test(`15% commission half-up and remainder net for PKR ${gross}`, () => {
    const p = money.completedSnapshot(money.pricing({ _id: ids.bid, labourCost: gross, partsCost: 0, totalCost: gross }), new Date());
    assert.equal(p.commissionMinor, commission); assert.equal(p.netMinor, net); assert.equal(p.totalMinor, commission + net);
  });
}
test('inconsistent components and subminimum labour cannot be snapshotted', () => {
  assert.throws(() => money.pricing({ labourCost: 499, totalCost: 499 }));
  assert.throws(() => money.pricing({ labourCost: 500, partsCost: 20, totalCost: 501 }));
});
test('completion atomically records agreed amount and preserves financial meaning', async () => {
  assigned(); const r = await complete(); assert.equal(r.status, 200);
  const snapshot = r.body.job.accounting;
  assert.equal(snapshot.totalMinor, 110075); assert.equal(snapshot.labourMinor, 90050); assert.equal(snapshot.partsMinor, 20025);
  assert.equal(snapshot.acceptedBidId, ids.bid); assert.equal(snapshot.commissionBps, 1500);
  assert.equal(snapshot.recordedAt, r.body.job.completedAt); assert.equal(r.body.job.finalCost, undefined);
  const totals = (await earnings()).body.data.summary;
  assert.equal(totals.completedJobs, 1); assert.equal(totals.grossMinor, '110075'); assert.equal(totals.netMinor, '93564');
});
test('new acceptance freezes authoritative prices within single-winner transaction', async () => {
  f.data().Bid.push({ _id: ids.bid, jobId: ids.job, mechanicId: ids.mechanic, status: 'pending', labourCost: 500, partsCost: 100.1, totalCost: 600.1, eta: 9 });
  const accepted = await request(`/bids/${ids.bid}/accept`, ids.driver, 'PATCH', {}); assert.equal(accepted.status, 200);
  assert.equal(f.data().Job[0].agreedPricing.totalMinor, 60010);
});
test('mutating original bid cannot change frozen completion or assignment amount', async () => {
  assigned(); Object.assign(f.data().Bid[0], { labourCost: 2000, partsCost: 0, totalCost: 2000 });
  assert.equal((await complete()).status, 200); assert.equal(f.data().Job[0].accounting.totalMinor, 110075);
  const assignment = await request(`/jobs/${ids.job}/assignment`); assert.equal(assignment.body.data.totalCost, 1100.75);
});
test('legacy active assignment with intact accepted bid can complete with genuine price', async () => {
  assigned({ frozen: false }); assert.equal((await complete()).status, 200);
  f.data().Bid[0].totalCost = 3000; assert.equal((await request(`/jobs/${ids.job}/assignment`)).body.data.totalCost, 1100.75);
});
test('completion refuses missing or foreign accepted pricing; no partial completion', async () => {
  assigned(); f.data().Bid[0].jobId = ids.otherJob;
  assert.equal((await complete()).status, 409); assert.equal(f.data().Job[0].status, 'in_progress'); assert.equal(f.data().Job[0].accounting, undefined);
});
test('existing valid snapshot is preserved without repricing', async () => {
  assigned(); const at = new Date('2026-01-02'); f.data().Job[0].accounting = money.completedSnapshot(f.data().Job[0].agreedPricing, at);
  assert.equal((await complete()).status, 200); assert.deepEqual(f.data().Job[0].accounting.recordedAt, at);
});
test('repeated and concurrent completion produce one accounting record', async () => {
  assigned(); const results = await Promise.all([complete(), complete()]); assert.deepEqual(results.map(r => r.status).sort(), [200, 409]);
  assert.equal((await complete()).status, 409); const totals = (await earnings()).body.data.summary;
  assert.equal(totals.completedJobs, 1); assert.equal(totals.netMinor, '93564'); assert.equal(f.data().Job[0].statusVersion, 1);
});
test('interrupted transaction rolls back completion and accounting together', async () => {
  assigned(); const original = f.models.Job.findOneAndUpdate;
  mock.method(f.models.Job, 'findOneAndUpdate', async (...args) => { await original(...args); throw new Error('fixture interruption'); });
  assert.equal((await complete()).status, 500); f.models.Job.findOneAndUpdate.mock.restore();
  assert.equal(f.data().Job[0].status, 'in_progress'); assert.equal(f.data().Job[0].accounting, undefined);
  assert.equal((await complete()).status, 200);
});
test('all incomplete/cancelled states excluded even with a stale snapshot', async () => {
  for (const status of ['pending', 'bidding', 'accepted', 'en_route', 'arrived', 'in_progress', 'cancelled']) {
    const job = booked((200 + f.data().Job.length).toString(16).padStart(24, '0'), '2026-01-10'); job.status = status; f.data().Job.push(job);
  }
  assert.equal((await earnings()).body.data.summary.completedJobs, 0);
});
test('legacy completed amount never fabricated from finalCost or live bid', async () => {
  assigned({ status: 'completed', frozen: false }); f.data().Job[0].finalCost = 12345;
  const data = (await earnings()).body.data;
  assert.equal(data.summary.unpricedJobs, 1); assert.equal(data.summary.pricedJobs, 0); assert.equal(data.jobs[0].pricingStatus, 'unavailable'); assert.equal(data.jobs[0].pricing, undefined); assert.equal(data.undatedCompletedJobs, 1);
});
test('driver history is owned, ordered, paginated and redacted', async () => {
  for (let i = 0; i < 4; i++) f.data().Job.push(booked((300 + i).toString(16).padStart(24, '0'), `2026-01-0${i + 2}`));
  f.data().Job.push(booked('000000000000000000000999', '2026-02-01', 500, ids.foreign));
  const page = await request('/jobs?page=1&limit=2&status=completed'); assert.equal(page.status, 200); assert.equal(page.body.data.length, 2); assert.equal(page.body.pagination.total, 4);
  assert.equal(page.body.data[0]._id, (303).toString(16).padStart(24, '0')); assert.equal(page.body.pagination.hasMore, true);
  const next = await request('/jobs?page=2&limit=2&status=completed'); assert.equal(next.body.data.length, 2);
  assert.equal(JSON.stringify(page.body).includes('passwordHash'), false); assert.equal(JSON.stringify(page.body).includes('3001234567'), false);
  assert.equal((await request('/jobs', ids.foreign)).body.data.length, 1);
});
test('mechanic history and earnings resolve profile identity rather than user ID', async () => {
  f.data().Job.push(booked('000000000000000000000100', '2026-01-02'));
  f.data().Job.push(booked('000000000000000000000101', '2026-01-03', 2000, ids.foreign, ids.otherMechanic));
  const h = await request('/mechanics/history', ids.mechanicUser); assert.equal(h.body.data.length, 1); assert.equal(h.body.data[0].mechanicId, ids.mechanic);
  assert.equal((await earnings()).body.data.summary.grossMinor, '100000');
  assert.equal((await request('/mechanics/earnings', ids.driver)).status, 403); assert.equal((await request('/mechanics/history', null)).status, 401);
  assert.equal((await earnings('?mechanicId=' + ids.otherMechanic)).status, 400);
});
test('UTC date filters and actual monthly totals agree with individual jobs', async () => {
  f.data().Job.push(booked('000000000000000000000100', '2026-01-31T23:59:59Z', 500));
  f.data().Job.push(booked('000000000000000000000101', '2026-02-01T00:00:00Z', 1000));
  const jan = (await earnings('?from=2026-01-01&to=2026-01-31')).body.data;
  assert.equal(jan.summary.completedJobs, 1); assert.equal(jan.summary.grossMinor, '50000'); assert.equal(jan.summary.months[0].month, '2026-01');
  const both = (await earnings()).body.data.summary; assert.equal(both.grossMinor, '150000'); assert.equal(both.commissionMinor, '22500'); assert.equal(both.months.length, 2);
});
test('invalid date/status/pagination and untrusted financial fields rejected', async () => {
  for (const query of ['?limit=51', '?page=0', '?from=2026-02-30', '?from=2026-03-01&to=2026-01-01', '?status=paid', '?from=2000-01-01&to=2026-01-01']) assert.equal((await earnings(query)).status, 400);
  assigned(); for (const field of ['accounting', 'agreedPricing', 'platformCommission', 'mechanicEarning', 'finalCost']) assert.equal((await request(`/jobs/${ids.job}/status`, ids.mechanicUser, 'PATCH', { status: 'completed', [field]: 1 })).status, 400);
});
test('driver profile reports canonical completed jobs without changing R08 reputation', async () => {
  f.data().Job.push(booked('000000000000000000000100', '2026-01-02'));
  const p = await request('/users/profile'); assert.equal(p.body.data.statistics.completedJobs, 1); assert.equal(p.body.data.statistics.grossMinor, '100000');
  const m = await request('/mechanics/profile', ids.mechanicUser); assert.equal(m.body.data.totalJobs, 1); assert.equal(m.body.data.rating, 4);
});

test('admin booked statistics use the same snapshot source and ignore arbitrary finalCost', async () => {
  f.data().Job.push(booked('000000000000000000000100', '2026-01-02'));
  f.data().Job.push({ _id: ids.otherJob, userId: ids.driver, mechanicId: ids.mechanic, status: 'completed', finalCost: 999999 });
  const r = await request('/admin/stats', ids.admin); assert.equal(r.status, 200);
  assert.equal(r.body.data.totalRevenue, 1000); assert.equal(r.body.data.revenueBasis, 'booked_not_paid'); assert.equal(r.body.data.bookedTotals.unpricedJobs, 1);
  assert.equal(r.body.data.bookedTotals.commissionMinor, '15000');
});
test('monthly report is bounded while totals include every priced job', async () => {
  for (let i = 0; i < 25; i++) f.data().Job.push(booked((400 + i).toString(16).padStart(24, '0'), new Date(Date.UTC(2024 + Math.floor(i / 12), i % 12, 1)).toISOString(), 500));
  const r = (await earnings()).body.data;
  assert.equal(r.summary.completedJobs, 25); assert.equal(r.summary.months.length, 24); assert.equal(r.summary.moreMonths, true);
  assert.equal(r.summary.grossMinor, '1250000'); assert.equal(r.jobs.length, 20); assert.equal(r.pagination.hasMore, true);
});

test('actual Mongoose schema validates snapshots as integer minor units', () => {
  const Job = require('../src/models/Job');
  const doc = new Job({ userId: ids.driver, mechanicId: ids.mechanic, acceptedBidId: ids.bid, status: 'completed', description: 'Schema fixture', location: { lat: 31, lng: 74 }, accounting: money.completedSnapshot(money.pricing({ _id: ids.bid, labourCost: 500, partsCost: 0, totalCost: 500 }), new Date()) });
  assert.equal(doc.validateSync(), undefined);
  doc.accounting.totalMinor = 50000.5; assert.ok(doc.validateSync().errors['accounting.totalMinor']);
});

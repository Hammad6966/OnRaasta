// Optional real MongoDB transaction coverage. No application .env is loaded.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const http = require('node:http');

test('MongoDB transactions enforce a single bid winner, duplicate review exclusion, concurrent reputation updates and refresh rotation', {
  skip: !process.env.ONRAASTA_TEST_MONGO_URI && 'Set ONRAASTA_TEST_MONGO_URI to an isolated replica-set test server',
  timeout: 60000,
}, async () => {
  process.env.NODE_ENV = 'test';
  process.env.JWT_SECRET = crypto.randomBytes(32).toString('hex');
  process.env.JWT_REFRESH_SECRET = crypto.randomBytes(32).toString('hex');
  const mongoose = require('mongoose');
  const User = require('../src/models/User');
  const Mechanic = require('../src/models/Mechanic');
  const Job = require('../src/models/Job');
  const Bid = require('../src/models/Bid');
  const RefreshSession = require('../src/models/RefreshSession');
  const Vehicle = require('../src/models/Vehicle');
  const AdminLog = require('../src/models/AdminLog');
  const refreshSessions = require('../src/services/refresh-session.service');
  const { signAccessToken } = require('../src/services/access.service');
  const dbName = `onraasta_r02_test_${crypto.randomBytes(8).toString('hex')}`;
  let server;
  await mongoose.connect(process.env.ONRAASTA_TEST_MONGO_URI, { dbName, autoIndex: false, serverSelectionTimeoutMS: 10000 });
  try {
    for (const model of [User, Mechanic, Job, Bid, RefreshSession, Vehicle, AdminLog]) await model.createCollection();
    await User.createIndexes();
    await Vehicle.createIndexes();
    await Bid.createIndexes();
    await RefreshSession.createIndexes();
    await AdminLog.createIndexes();
    const createUser = (phone, role) => User.create({ name: 'Security fixture', phone, role,
      passwordHash: 'unused-test-fixture', isActive: true, isVerified: true });
    const driver = await createUser('3110000001', 'user');
    const login = await refreshSessions.issue(driver);
    const rotations = await Promise.allSettled([refreshSessions.rotate(login.refreshToken), refreshSessions.rotate(login.refreshToken)]);
    assert.equal(rotations.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal(rotations.find(r => r.status === 'rejected').reason.status, 409);
    const current = rotations.find(r => r.status === 'fulfilled').value;
    await refreshSessions.revoke(current.refreshToken);
    await assert.rejects(refreshSessions.rotate(current.refreshToken), err => err.status === 401);
    const m1User = await createUser('3110000002', 'mechanic');
    const m2User = await createUser('3110000003', 'mechanic');
    const m1 = await Mechanic.create({ userId: m1User._id, isApproved: true });
    const m2 = await Mechanic.create({ userId: m2User._id, isApproved: true });
    const job = await Job.create({ userId: driver._id, description: 'Battery fixture', location: { lat: 31, lng: 74 } });
    server = http.createServer(require('../src/app'));
    await new Promise(r => server.listen(0, '127.0.0.1', r));
    const api = `http://127.0.0.1:${server.address().port}/api`;
    const send = async (method, path, user, body) => {
      const r = await fetch(api + path, { method, headers: { Authorization: `Bearer ${signAccessToken(user)}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      return { status: r.status, body: await r.json() };
    };
    // R11: real replica-set serialization of primary selection and reference deletion.
    const car = { make: 'Suzuki', model: 'Alto', plate: 'TEST-1' };
    const car1 = await send('POST', '/users/vehicles', driver, car);
    const car2 = await send('POST', '/users/vehicles', driver, { ...car, plate: 'TEST-2' });
    assert.equal(car1.status, 201); assert.equal(car2.status, 201);
    const selected = await Promise.all([car1, car2].map(c => send('PATCH', `/users/vehicles/${c.body.data._id}`, driver, { isPrimary: true })));
    assert.ok(selected.every(r => r.status === 200));
    assert.equal(await Vehicle.countDocuments({ userId: driver._id, isPrimary: true }), 1);
    const referenceRace = await Promise.all([
      send('POST', '/jobs', driver, { description: 'Vehicle reference race', location: { lat: 31, lng: 74 }, vehicleId: car1.body.data._id }),
      send('DELETE', `/users/vehicles/${car1.body.data._id}`, driver),
    ]);
    assert.ok([[201, 409], [404, 200]].some(pair => pair.every((code, i) => referenceRace[i].status === code)));
    for (const j of await Job.find({ vehicleId: car1.body.data._id })) assert.ok(await Vehicle.exists({ _id: j.vehicleId }));
    const payload = { jobId: String(job._id), labourCost: 500, partsCost: 0, totalCost: 500, eta: 10 };
    const duplicates = await Promise.all([send('POST', '/bids', m1User, payload), send('POST', '/bids', m1User, payload)]);
    assert.deepEqual(duplicates.map(r => r.status).sort(), [201, 409]);
    const first = duplicates.find(r => r.status === 201).body.bid;
    const second = await send('POST', '/bids', m2User, payload);
    assert.equal(second.status, 201);
    const winners = await Promise.all([send('PATCH', `/bids/${first._id}/accept`, driver),
      send('PATCH', `/bids/${second.body.bid._id}/accept`, driver)]);
    assert.deepEqual(winners.map(r => r.status).sort(), [200, 409]);
    assert.equal(await Bid.countDocuments({ jobId: job._id, status: 'accepted' }), 1);
    assert.equal(await Bid.countDocuments({ jobId: job._id, status: 'declined' }), 1);
    const assigned = await Job.findById(job._id);
    const winner = await Bid.findById(assigned.acceptedBidId);
    assert.equal(String(assigned.mechanicId), String(winner.mechanicId));
    assert.ok([String(m1._id), String(m2._id)].includes(String(winner.mechanicId)));
    // R08: real transaction retries must serialize reviews of the same profile,
    // not merely duplicate review writes on one Job.
    const mechanicUser = String(winner.mechanicId) === String(m1._id) ? m1User : m2User;
    for (const status of ['en_route', 'arrived', 'in_progress']) {
      assert.equal((await send('PATCH', `/jobs/${job._id}/status`, mechanicUser, { status })).status, 200);
    }
    const completions = await Promise.all([send('PATCH', `/jobs/${job._id}/status`, mechanicUser, { status: 'completed' }), send('PATCH', `/jobs/${job._id}/status`, mechanicUser, { status: 'completed' })]);
    assert.deepEqual(completions.map(r => r.status).sort(), [200, 409]);
    const finished = await Job.findById(job._id);
    assert.equal(finished.accounting.totalMinor, 50000);
    assert.equal(finished.accounting.commissionMinor, 7500);
    assert.equal(finished.accounting.netMinor, 42500);
    assert.equal(finished.statusVersion, 4);
    const report = await send('GET', '/mechanics/earnings', mechanicUser);
    assert.equal(report.body.data.summary.netMinor, '42500');
    const reviews = await Promise.all([send('POST', `/jobs/${job._id}/review`, driver, { stars: 5 }),
      send('POST', `/jobs/${job._id}/review`, driver, { stars: 5 })]);
    assert.deepEqual(reviews.map(r => r.status).sort(), [200, 409]);
    const driver2 = await createUser('3110000004', 'user');
    const reviewFixture = async (owner) => {
      const j = await Job.create({ userId: owner._id, mechanicId: winner.mechanicId, status: 'completed',
        description: 'Completed review fixture', location: { lat: 31, lng: 74 } });
      const b = await Bid.create({ jobId: j._id, mechanicId: winner.mechanicId, status: 'accepted',
        labourCost: 500, partsCost: 0, totalCost: 500, eta: 10 });
      j.acceptedBidId = b._id; await j.save(); return j;
    };
    const [reviewJob1, reviewJob2] = await Promise.all([reviewFixture(driver), reviewFixture(driver2)]);
    const concurrent = await Promise.all([send('POST', `/jobs/${reviewJob1._id}/review`, driver, { stars: 2 }),
      send('POST', `/jobs/${reviewJob2._id}/review`, driver2, { stars: 4 })]);
    assert.deepEqual(concurrent.map(r => r.status), [200, 200]);
    const reputation = await Mechanic.findById(winner.mechanicId);
    assert.equal(reputation.reviewCount, 3); assert.equal(reputation.rating, 3.67);

    // R15: real transaction conflicts and atomic audit insertion (isolated DB only).
    const admin = await createUser('3110000005', 'admin');
    const application = await Mechanic.findById(m1._id);
    const version = application.__v;
    const decisions = await Promise.all([
      send('PATCH', `/admin/verification/${application._id}`, admin, { action: 'revoke', expectedVersion: version, reason: 'Isolated transaction test' }),
      send('PATCH', `/admin/verification/${application._id}`, admin, { action: 'revoke', expectedVersion: version, reason: 'Concurrent isolated test' }),
    ]);
    assert.deepEqual(decisions.map(r => r.status).sort(), [200, 409]);
    assert.equal(await AdminLog.countDocuments({ targetId: application._id }), 1);
    assert.equal((await Mechanic.findById(application._id)).isApproved, false);
    const target = await User.findById(driver._id);
    const suspensions = await Promise.all([1, 2].map(() => send('PATCH', `/admin/users/${target._id}/status`, admin, { isActive: false, expectedVersion: target.__v, reason: 'Isolated suspension test' })));
    assert.deepEqual(suspensions.map(r => r.status).sort(), [200, 409]);
    assert.equal(await AdminLog.countDocuments({ targetId: target._id }), 1);

  } finally {
    if (server) await new Promise(r => server.close(r));
    // Only the randomly named database created by this test may be removed.
    if (mongoose.connection.name === dbName && /^onraasta_r02_test_[a-f0-9]{16}$/.test(dbName)) {
      await mongoose.connection.dropDatabase();
    }
    await mongoose.disconnect();
  }
});

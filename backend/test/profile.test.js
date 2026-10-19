const { test, before, after, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = require('node:crypto').randomBytes(32).toString('hex');
process.env.JWT_REFRESH_SECRET = require('node:crypto').randomBytes(32).toString('hex');
const f = require('./fixtures'); f.install(mock);
const { ids } = f;
const presence = require('../src/services/presence.service');
const { signAccessToken } = require('../src/services/access.service');
const { apiLimiter } = require('../src/middleware/rate-limit.middleware');
const app = require('../src/app');
const server = http.createServer(app); let base;
before(async () => { await new Promise(r => server.listen(0, '127.0.0.1', r)); base = `http://127.0.0.1:${server.address().port}`; });
after(async () => { await new Promise(r => server.close(r)); mock.restoreAll(); });
beforeEach(() => { f.reset('private-fixture'); presence.clear(); apiLimiter.resetKey('127.0.0.1'); });
async function request(method, path, id = ids.driver, data) {
  const headers = { 'Content-Type': 'application/json' };
  if (id) headers.Authorization = `Bearer ${signAccessToken(f.data().User.find(u => u._id === id))}`;
  const r = await fetch(`${base}/api${path}`, { method, headers, body: data === undefined ? undefined : JSON.stringify(data) });
  return { status: r.status, body: await r.json() };
}
const vehicle = { make: 'Suzuki', model: 'Alto', plate: 'abc-123', year: 2020 };
test('authenticated profile is real and excludes security fields', async () => {
  const r = await request('GET', '/users/profile'); assert.equal(r.status, 200);
  assert.equal(r.body.data._id, ids.driver); assert.equal(r.body.data.passwordHash, undefined); assert.equal(r.body.data.failedLoginAttempts, undefined);
  assert.equal((await request('GET', '/users/profile', null)).status, 401);
});
test('name/email persistence and normalisation', async () => {
  const r = await request('PATCH', '/users/profile', ids.driver, { name: ' Driver Name ', email: 'DRIVER@example.test' });
  assert.equal(r.status, 200); assert.equal(r.body.data.name, 'Driver Name'); assert.equal(r.body.data.email, 'driver@example.test');
  assert.equal((await request('GET', '/users/profile')).body.data.name, 'Driver Name');
});
test('protected fields and phone takeover rejected', async () => {
  for (const field of ['role', 'isVerified', 'isActive', 'passwordHash', 'userId', 'vehicleIds', 'phone']) {
    assert.equal((await request('PATCH', '/users/profile', ids.driver, { [field]: 'forged' })).status, 400);
  }
});
test('invalid name/email and duplicate identity rejected', async () => {
  for (const body of [{ name: 'x' }, { email: 'broken' }, { name: 'a'.repeat(101) }]) assert.equal((await request('PATCH', '/users/profile', ids.driver, body)).status, 400);
  assert.equal((await request('PATCH', '/users/profile', ids.driver, { email: 'admin@example.test' })).status, 409);
});
test('contact add/edit/remove persists without exposing security fields', async () => {
  for (const contacts of [[{ name: 'Contact', phone: '+923001234567' }], [{ name: 'Edited', phone: '+923111234567' }], []]) {
    const r = await request('PATCH', '/users/profile', ids.driver, { emergencyContacts: contacts });
    assert.equal(r.status, 200); assert.deepEqual(r.body.data.emergencyContacts, contacts);
  }
  assert.equal(f.data().User.find(u => u._id === ids.foreign).emergencyContacts, undefined);
});
test('contacts validate counts, duplicate numbers and nested whitelist', async () => {
  for (const contacts of [[{ name: '', phone: 'bad' }], [{ name: 'A', phone: '+923001234567', userId: ids.foreign }], Array(6).fill({ name: 'A', phone: '+923001234567' }), Array(2).fill({ name: 'A', phone: '+923001234567' })]) {
    assert.equal((await request('PATCH', '/users/profile', ids.driver, { emergencyContacts: contacts })).status, 400);
  }
});
test('vehicle CRUD persists with owner and normalised plate', async () => {
  const r = await request('POST', '/users/vehicles', ids.driver, vehicle); assert.equal(r.status, 201);
  const id = r.body.data._id; assert.equal(r.body.data.userId, ids.driver); assert.equal(r.body.data.plate, 'ABC-123');
  assert.equal((await request('GET', '/users/vehicles')).body.data.length, 2);
  assert.equal((await request('PATCH', `/users/vehicles/${id}`, ids.driver, { color: 'White' })).body.data.color, 'White');
  assert.equal((await request('DELETE', `/users/vehicles/${id}`)).status, 200);
  assert.deepEqual(f.data().User.find(u => u._id === ids.driver).vehicleIds, [ids.vehicle]);
});
test('vehicle role, body ownership, and cross-user mutations rejected', async () => {
  assert.equal((await request('POST', '/users/vehicles', ids.driver, { ...vehicle, userId: ids.foreign })).status, 400);
  for (const method of ['PATCH', 'DELETE']) assert.equal((await request(method, `/users/vehicles/${ids.vehicle}`, ids.foreign, method === 'PATCH' ? { plate: 'NEW' } : undefined)).status, 404);
  assert.deepEqual((await request('GET', '/users/vehicles', ids.foreign)).body.data, []);
  assert.equal((await request('GET', '/users/vehicles', ids.mechanicUser)).status, 403);
});
test('vehicle field bounds are validated', async () => {
  for (const body of [{ ...vehicle, year: 1899 }, { ...vehicle, plate: '<html>' }, { ...vehicle, make: '' }, { ...vehicle, isPrimary: 'yes' }]) assert.equal((await request('POST', '/users/vehicles', ids.driver, body)).status, 400);
});
test('concurrent primary selections leave one primary and consistent references', async () => {
  const a = await request('POST', '/users/vehicles', ids.driver, vehicle);
  const b = await request('POST', '/users/vehicles', ids.driver, { ...vehicle, plate: 'XYZ' });
  const results = await Promise.all([a, b].map(v => request('PATCH', `/users/vehicles/${v.body.data._id}`, ids.driver, { isPrimary: true })));
  assert.ok(results.every(r => r.status === 200));
  assert.equal(f.data().Vehicle.filter(v => v.userId === ids.driver && v.isPrimary).length, 1);
  assert.equal(f.data().User.find(u => u._id === ids.driver).vehicleIds.length, 3);
});
test('primary deletion chooses a remaining vehicle; primary cannot be unset alone', async () => {
  f.data().Vehicle[0].isPrimary = true;
  assert.equal((await request('PATCH', `/users/vehicles/${ids.vehicle}`, ids.driver, { isPrimary: false })).status, 409);
  await request('POST', '/users/vehicles', ids.driver, vehicle);
  assert.equal((await request('DELETE', `/users/vehicles/${ids.vehicle}`)).status, 200);
  assert.equal(f.data().Vehicle.filter(v => v.isPrimary).length, 1);
});
test('active and historical job vehicle references prevent deletion', async () => {
  for (const status of ['accepted', 'completed', 'cancelled']) {
    Object.assign(f.data().Job[0], { status, vehicleId: ids.vehicle });
    assert.equal((await request('DELETE', `/users/vehicles/${ids.vehicle}`)).status, 409);
    assert.equal(f.data().Vehicle.length, 1);
  }
});
test('vehicle transaction rolls back on failure', async () => {
  mock.method(f.models.Vehicle, 'create', async () => { throw new Error('fixture failure'); });
  const r = await request('POST', '/users/vehicles', ids.driver, { ...vehicle, isPrimary: true });
  assert.equal(r.status, 500); assert.equal(f.data().Vehicle.length, 1);
  f.models.Vehicle.create.mock.restore();
});
test('mechanic profile read redacts CNIC and returns persisted reputation', async () => {
  f.data().Mechanic[0].documents = { cnic_front: 'private', permit_number: 'private', status: 'verified' };
  const r = await request('GET', '/mechanics/profile', ids.mechanicUser);
  assert.equal(r.status, 200); assert.equal(r.body.data._id, ids.mechanic);
  assert.equal(r.body.data.documents.cnic_front, undefined); assert.equal(r.body.data.documents.permit_number, undefined);
  assert.equal(r.body.data.rating, 4);
});
test('mechanic radius/address/name save preserves approval and reputation', async () => {
  const r = await request('PATCH', '/mechanics/profile', ids.mechanicUser, { name: 'Real Mechanic', shopAddress: ' Workshop ', serviceRadius: 15 });
  assert.equal(r.status, 200); assert.equal(r.body.data.serviceRadius, 15); assert.equal(r.body.data.shopAddress, 'Workshop');
  assert.equal(f.data().User.find(u => u._id === ids.mechanicUser).name, 'Real Mechanic');
  assert.equal(r.body.data.isApproved, true); assert.equal(r.body.data.rating, 4);
});
test('changed skills require reapproval; unchanged skills preserve approval', async () => {
  assert.equal((await request('PATCH', '/mechanics/profile', ids.mechanicUser, { skills: [] })).body.data.isApproved, true);
  const r = await request('PATCH', '/mechanics/profile', ids.mechanicUser, { skills: ['Auto Electrician'] });
  assert.equal(r.status, 200); assert.equal(r.body.data.isApproved, false); assert.equal(r.body.data.documents.status, 'pending');
});
test('mechanic protected fields, unsupported skills, bad radii and coordinates rejected', async () => {
  for (const body of [{ isApproved: true }, { documents: { status: 'verified' } }, { rating: 5 }, { earnings: 99 }, { mechanicId: ids.otherMechanic }, { lat: 30, lng: 70 }, { serviceRadius: 0 }, { serviceRadius: 101 }, { skills: ['invented'] }, { skills: ['Battery', 'Battery'] }]) assert.equal((await request('PATCH', '/mechanics/profile', ids.mechanicUser, body)).status, 400);
  assert.equal((await request('PATCH', '/mechanics/profile', ids.driver, { serviceRadius: 15 })).status, 403);
});

test('vehicle deletion and breakdown creation serialize without dangling references', async () => {
  const results = await Promise.all([
    request('POST', '/jobs', ids.driver, { description: 'Battery failed', location: { lat: 31, lng: 74 }, vehicleId: ids.vehicle }),
    request('DELETE', `/users/vehicles/${ids.vehicle}`),
  ]);
  assert.ok([[201, 409], [404, 200]].some(pair => pair.every((code, i) => results[i].status === code)));
  for (const job of f.data().Job.filter(j => j.vehicleId)) assert.ok(f.data().Vehicle.find(v => v._id === job.vehicleId));
});
test('profile validation rejects malformed registration email before writes', async () => {
  assert.equal((await request('POST', '/auth/register', null, { name: 'Driver Name', phone: '3111234567', password: 'fixture-password', email: 'invalid', role: 'user' })).status, 400);
});

test('radius edits preserve valid availability; qualification edits revoke presence', async () => {
  const token = signAccessToken(f.data().User.find(u => u._id === ids.mechanicUser));
  const events = [];
  const socket = { id: 'profile-presence-fixture', connected: true, handshake: { auth: { token } }, join: async () => {}, leave: () => {}, emit: (name, data) => events.push({ name, data }) };
  await presence.online(socket, { id: ids.mechanicUser, role: 'mechanic' }, { lat: 31, lng: 74 });
  assert.equal((await request('PATCH', '/mechanics/profile', ids.mechanicUser, { serviceRadius: 8 })).body.data.isOnline, true);
  assert.equal((await presence.eligibleEntries())[0].entry.serviceRadius, 8);
  const changed = await request('PATCH', '/mechanics/profile', ids.mechanicUser, { skills: ['Battery'] });
  assert.equal(changed.body.data.isOnline, false); assert.equal(changed.body.data.isApproved, false);
  assert.equal(events.at(-1).name, 'mechanic:availability'); assert.equal(events.at(-1).data.isOnline, false);
});

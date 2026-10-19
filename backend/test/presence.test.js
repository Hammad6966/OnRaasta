const { test, before, after, beforeEach, afterEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = crypto.randomBytes(32).toString('hex');
process.env.JWT_REFRESH_SECRET = crypto.randomBytes(32).toString('hex');
const f = require('./fixtures');
f.install(mock);
const { ids } = f;
const { signAccessToken } = require('../src/services/access.service');
const presence = require('../src/services/presence.service');
const sockets = require('../src/socket/socket');
const app = require('../src/app');
const server = http.createServer(app);
const io = sockets.initSocket(server);
let base;
const clients = [];
before(async () => { await new Promise(r => server.listen(0, '127.0.0.1', r)); base = `http://127.0.0.1:${server.address().port}`; });
after(async () => { await new Promise(r => io.close(r)); mock.restoreAll(); });
beforeEach(() => { f.reset('unused-fixture-hash'); presence.clear(); });
afterEach(async () => {
  for (const client of clients.splice(0)) {
    if (client.ws.readyState === WebSocket.CLOSED) continue;
    await new Promise(resolve => { client.ws.addEventListener('close', resolve, { once: true }); client.ws.close(); });
  }
  presence.clear();
});
const token = id => signAccessToken(f.data().User.find(user => user._id === id));
function connect(id) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(base.replace('http:', 'ws:') + '/socket.io/?EIO=4&transport=websocket');
    const pending = new Map(), events = [];
    let sequence = 0;
    const timeout = setTimeout(() => { ws.close(); reject(new Error('Handshake timeout')); }, 3000);
    ws.addEventListener('message', e => {
      const packet = String(e.data);
      if (packet.startsWith('0')) ws.send('40' + JSON.stringify({ token: token(id) }));
      else if (packet === '2') ws.send('3');
      else if (packet.startsWith('44')) { clearTimeout(timeout); ws.close(); reject(new Error('Unauthorized')); }
      else if (packet.startsWith('40')) {
        clearTimeout(timeout);
        const client = { ws, events, socketId: JSON.parse(packet.slice(2)).sid,
          emit(event, payload) {
            return new Promise((done, fail) => {
              const n = sequence++;
              const timer = setTimeout(() => { pending.delete(String(n)); fail(new Error('Missing ack')); }, 3000);
              pending.set(String(n), data => { clearTimeout(timer); done(data[0]); });
              ws.send('42' + n + JSON.stringify([event, payload]));
            });
          } };
        clients.push(client); resolve(client);
      } else if (packet.startsWith('43')) {
        const match = /^43(\d+)(\[.*)$/.exec(packet);
        if (match) { pending.get(match[1])?.(JSON.parse(match[2])); pending.delete(match[1]); }
      } else if (packet.startsWith('42')) events.push(JSON.parse(packet.slice(2)));
    });
    ws.addEventListener('error', () => { clearTimeout(timeout); reject(new Error('Socket connection failed')); });
  });
}
async function request(path, id) {
  const response = await fetch(`${base}/api${path}`, { headers: id ? { Authorization: `Bearer ${token(id)}` } : {} });
  return { status: response.status, body: await response.json() };
}
const gps = { lat: 31, lng: 74 };
const online = client => client.emit('mechanic:go_online', gps);
async function close(client) {
  const serverSocket = io.sockets.sockets.get(client.socketId);
  const disconnected = serverSocket ? new Promise(resolve => serverSocket.once('disconnect', resolve)) : Promise.resolve();
  const closed = new Promise(resolve => client.ws.addEventListener('close', resolve, { once: true }));
  client.ws.close();
  await Promise.all([disconnected, closed]);
}

test('approved mechanic receives authoritative online/offline acknowledgments without stale database flags', async () => {
  const client = await connect(ids.mechanicUser);
  const ack = await online(client);
  assert.deepEqual(ack.data, { mechanicId: ids.mechanic, isOnline: true, ...gps, serviceRadius: 15 });
  assert.equal(presence.isOnline(ids.mechanic), true);
  assert.notEqual(f.data().Mechanic[0].isOnline, true);
  const offline = await client.emit('mechanic:go_offline', {});
  assert.deepEqual(offline.data, { mechanicId: ids.mechanic, isOnline: false });
  assert.equal(presence.isOnline(ids.mechanic), false);
  assert.equal((await client.emit('mechanic:go_offline', {})).success, true);
});
test('unapproved, suspended and unverified mechanics cannot register presence', async () => {
  const unapproved = await connect(ids.unapprovedUser);
  assert.equal((await online(unapproved)).status, 403);
  const client = await connect(ids.mechanicUser);
  f.data().User.find(u => u._id === ids.mechanicUser).isActive = false;
  assert.equal((await online(client)).status, 403);
  f.data().User.find(u => u._id === ids.mechanicUser).isActive = true;
  f.data().User.find(u => u._id === ids.mechanicUser).isVerified = false;
  assert.equal((await online(client)).status, 403);
  assert.equal(presence.isOnline(ids.mechanic), false);
});
test('invalid GPS, radius overrides and impersonation are rejected', async () => {
  const client = await connect(ids.mechanicUser);
  for (const payload of [{ lat: 0, lng: 0 }, { lat: 91, lng: 74 }, { lat: '31', lng: 74 }, {}, null,
    { ...gps, serviceRadius: 0 }, { ...gps, serviceRadius: 101 }, { ...gps, serviceRadius: 50 }]) {
    assert.equal((await client.emit('mechanic:go_online', payload)).status, 400);
  }
  assert.equal((await client.emit('mechanic:go_online', { ...gps, mechanicId: ids.otherMechanic })).status, 403);
  f.data().Mechanic[0].serviceRadius = 101;
  assert.equal((await online(client)).status, 409);
});
test('duplicate online registrations have one session and one dispatch target', async t => {
  const client = await connect(ids.mechanicUser);
  assert.equal((await online(client)).success, true);
  assert.equal((await online(client)).success, true);
  assert.equal((await presence.eligibleEntries()).length, 1);
  const targets = []; const original = io.to.bind(io);
  t.mock.method(io, 'to', room => { targets.push(room); return original(room); });
  await sockets.broadcastJobToMechanics({ jobId: ids.job });
  assert.deepEqual(targets, [client.socketId]);
});
test('replacement socket wins; old offline and disconnect cannot remove it', async t => {
  const old = await connect(ids.mechanicUser); await online(old);
  const current = await connect(ids.mechanicUser); await online(current);
  assert.equal((await old.emit('mechanic:go_offline', {})).status, 409);
  assert.equal((await old.emit('mechanic:update_location', gps)).status, 409);
  await close(old);
  assert.equal(presence.isOnline(ids.mechanic), true);
  const targets = []; const original = io.to.bind(io);
  t.mock.method(io, 'to', room => { targets.push(room); return original(room); });
  await sockets.broadcastJobToMechanics({ jobId: ids.job });
  assert.deepEqual(targets, [current.socketId]);
});
test('current socket disconnect removes availability', async () => {
  const client = await connect(ids.mechanicUser); await online(client); await close(client);
  assert.equal((await presence.nearby(31, 74)).length, 0);
});
test('Haversine is correct at zero, a known equatorial degree and antipodes', () => {
  assert.equal(presence.haversine(31, 74, 31, 74), 0);
  assert.ok(Math.abs(presence.haversine(0, 0, 0, 1) - 111.1949) < 0.001);
  assert.ok(Math.abs(presence.haversine(0, 0, 0, 180) - 20015.0868) < 0.01);
});
test('nearby respects configured radius and live coordinates rather than persisted online flags', async () => {
  f.data().Mechanic[0].serviceRadius = 5;
  Object.assign(f.data().Mechanic[1], { isOnline: true, lat:31, lng:74, documents:{cnic_front:'private'}, earnings:999 });
  const client = await connect(ids.mechanicUser); await online(client);
  const near = await request('/mechanics/nearby?lat=31.02&lng=74', ids.driver);
  assert.equal(near.status,200); assert.equal(near.body.data.length,1);
  assert.equal(near.body.data[0]._id,ids.mechanic);
  assert.ok(near.body.data[0].distance > 2 && near.body.data[0].distance < 3);
  assert.equal(near.body.data[0].serviceRadius,5);
  for (const field of ['documents','earnings','passwordHash','token','socket']) assert.equal(field in near.body.data[0],false);
  assert.equal((await request('/mechanics/nearby?lat=31.06&lng=74',ids.driver)).body.data.length,0);
  f.data().Mechanic[0].serviceRadius=10;
  assert.equal((await request('/mechanics/nearby?lat=31.06&lng=74',ids.driver)).body.data.length,1);
  await client.emit('mechanic:go_offline',{});
  assert.equal((await request('/mechanics/nearby?lat=31&lng=74',ids.driver)).body.data.length,0);
});
test('nearby rejects malformed driver coordinates', async () => {
  for (const query of ['lat=oops&lng=74','lat=91&lng=74','lat=0&lng=0','lat=31','lat=31&lng=74&extra=1']) {
    assert.equal((await request(`/mechanics/nearby?${query}`,ids.driver)).status,400);
  }
});
test('location updates change dispatch eligibility with server-confirmed coordinates', async () => {
  const client=await connect(ids.mechanicUser); await online(client);
  const ack=await client.emit('mechanic:update_location',{lat:32,lng:74});
  assert.equal(ack.data.lat,32); assert.equal(ack.data.isOnline,true);
  assert.equal((await presence.nearby(31,74)).length,0);
  assert.equal((await presence.nearby(32,74)).length,1);
});
test('dispatch reads saved job location, excludes offline/outside/inactive/revoked mechanics', async t => {
  f.data().Mechanic[0].serviceRadius=5;
  const first=await connect(ids.mechanicUser), outside=await connect(ids.otherMechanicUser);
  await online(first); await outside.emit('mechanic:go_online',{lat:32,lng:74});
  const sent=[]; const original=io.to.bind(io);
  t.mock.method(io,'to',room=>{sent.push(room);return original(room);});
  await sockets.broadcastJobToMechanics({jobId:ids.job,lat:32,lng:74}); // supplied location is ignored
  assert.deepEqual(sent,[first.socketId]);
  f.data().User.find(u=>u._id===ids.mechanicUser).isActive=false;
  await sockets.broadcastJobToMechanics({jobId:ids.job}); assert.equal(sent.length,1);
  assert.equal(presence.isOnline(ids.mechanic),false);
  f.data().Mechanic[1].isApproved=false;
  assert.equal((await presence.nearby(32,74)).length,0);
});
test('closed or nonexistent jobs never dispatch and payload preserves saved IDs/location', async t => {
  const client=await connect(ids.mechanicUser);await online(client);
  const sent=[];const original=io.to.bind(io);
  t.mock.method(io,'to',room=>{const target=original(room);return {emit:(event,payload)=>{sent.push({event,payload});target.emit(event,payload);}};});
  await sockets.broadcastJobToMechanics({jobId:ids.job});
  assert.equal(sent[0].event,'job:new_request'); assert.equal(sent[0].payload.jobId,ids.job);
  assert.deepEqual(sent[0].payload.location,{lat:31,lng:74});assert.equal(sent[0].payload.distance,0);
  f.data().Job[0].status='accepted';await sockets.broadcastJobToMechanics({jobId:ids.job});
  await sockets.broadcastJobToMechanics({jobId:ids.otherJob});assert.equal(sent.length,1);
});
test('expired presence leases are removed without database resets', async t => {
  const client=await connect(ids.mechanicUser);await online(client);
  const now=Date.now();t.mock.method(Date,'now',()=>now+presence.LEASE_MS+1);
  assert.equal(presence.isOnline(ids.mechanic),false);
  assert.equal((await presence.nearby(31,74)).length,0);
});
test('open request recovery requires approved live presence and returns eligible open saved jobs only', async () => {
  assert.equal((await request('/mechanics/requests')).status,401);
  assert.equal((await request('/mechanics/requests',ids.driver)).status,403);
  assert.equal((await request('/mechanics/requests',ids.unapprovedUser)).status,403);
  assert.equal((await request('/mechanics/requests',ids.mechanicUser)).status,409);
  const client=await connect(ids.mechanicUser);await online(client);
  f.data().Job.push({_id:ids.otherJob,userId:ids.foreign,status:'pending',location:{lat:32,lng:74},description:'Outside'});
  const result=await request('/mechanics/requests',ids.mechanicUser);
  assert.equal(result.status,200);assert.equal(result.body.data.length,1);
  assert.equal(result.body.data[0].jobId,ids.job);
  f.data().Job[0].status='completed';assert.equal((await request('/mechanics/requests',ids.mechanicUser)).body.data.length,0);
});

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
const { apiLimiter } = require('../src/middleware/rate-limit.middleware');
const presence = require('../src/services/presence.service');
const sockets = require('../src/socket/socket');
const app = require('../src/app');
const server = http.createServer(app);
const io = sockets.initSocket(server);
let base;
const clients = [];
before(async () => { await new Promise(r => server.listen(0, '127.0.0.1', r)); base = `http://127.0.0.1:${server.address().port}`; });
after(async () => { await new Promise(r => io.close(r)); mock.restoreAll(); });
beforeEach(() => { f.reset('unused-fixture-hash'); presence.clear(); apiLimiter.resetKey('127.0.0.1'); });
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
async function request(path, id, method='GET', body) {
  const response = await fetch(`${base}/api${path}`, { method, headers: {
    'Content-Type':'application/json', ...(id ? { Authorization: `Bearer ${token(id)}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: response.status, body: await response.json() };
}
function seed() {
  f.data().Bid.push({ _id: ids.bid, jobId: ids.job, mechanicId: ids.mechanic, status: 'pending', labourCost: 900.5, partsCost: 200.25, totalCost: 1100.75, eta: 12 },
    { _id: ids.otherBid, jobId: ids.job, mechanicId: ids.otherMechanic, status: 'pending', labourCost: 500, partsCost: 0, totalCost: 500, eta: 10 });
}
const accept=(bid=ids.bid)=>request(`/bids/${bid}/accept`,ids.driver,'PATCH');
const list=id=>request('/jobs/assignments',id);
const detail=(id,job=ids.job)=>request(`/jobs/${job}/assignment`,id);
const events=(client,event)=>client.events.filter(e=>e[0]===event).map(e=>e[1]);
async function roundTrip(client,id) {await client.emit('join_room',{room:`user_${id}`});}

test('committed assignment preserves distinct IDs, component prices, ETA and safe records for both participants',async()=>{
  seed(); const r=await accept(); assert.equal(r.status,200); assert.equal(r.body.data._id,ids.bid);
  for(const id of [ids.driver,ids.mechanicUser,ids.admin]) {
    const a=(await detail(id)).body.data;
    assert.deepEqual([a.jobId,a.acceptedBidId,a.mechanicId,a.mechanicUserId,a.userId],[ids.job,ids.bid,ids.mechanic,ids.mechanicUser,ids.driver]);
    assert.deepEqual([a.labourCost,a.partsCost,a.totalCost,a.eta,a.status],[900.5,200.25,1100.75,12,'accepted']);
    assert.equal(a.job.acceptedBidId,a.bid._id); assert.equal(a.bid.mechanicId.userId._id,ids.mechanicUser);
    assert.equal(a.driver._id,ids.driver); assert.equal(a.bid.mechanicId.isApproved,true);
  }
  assert.equal(f.data().Bid[1].status,'declined');
});
test('safe projection excludes documents, passwords, OTP, tokens and unrelated account fields',async()=>{
  seed(); Object.assign(f.data().Mechanic[0],{documents:['PRIVATE'],earnings:999,lat:31,lng:74});
  Object.assign(f.data().User[0],{refreshToken:'PRIVATE',otp:'PRIVATE',emergencyContacts:['PRIVATE']});
  await accept(); const text=JSON.stringify((await detail(ids.driver)).body);
  for(const field of ['PRIVATE','passwordHash','refreshToken','otp','documents','earnings','emergencyContacts']) assert.equal(text.includes(field),false);
});
test('HTTP recovery is authenticated, owner scoped and assigned-approved-mechanic scoped',async()=>{
  seed();await accept();
  assert.equal((await list()).status,401);
  for(const id of [ids.driver,ids.mechanicUser]) assert.equal((await list(id)).body.data[0].jobId,ids.job);
  for(const id of [ids.foreign,ids.otherMechanicUser]) {assert.deepEqual((await list(id)).body.data,[]);assert.equal((await detail(id)).status,403);}
  assert.equal((await detail(ids.driver,ids.otherJob)).status,404);
  assert.equal((await request('/jobs/bad/assignment',ids.driver)).status,400);
});
test('unassigned job is not fabricated as an assignment and terminal jobs leave active recovery',async()=>{
  assert.equal((await detail(ids.driver)).status,409);assert.deepEqual((await list(ids.driver)).body.data,[]);
  seed();await accept();f.data().Job[0].status='completed';
  assert.deepEqual((await list(ids.driver)).body.data,[]);assert.equal((await detail(ids.driver)).body.data.status,'completed');
});
test('corrupt persisted bid/job relationships produce a state conflict',async()=>{
  seed();await accept(); f.data().Bid[0].jobId=ids.otherJob;
  assert.equal((await detail(ids.driver)).status,409);
});
test('multiple active assignments are returned without silently replacing a job',async()=>{
  seed();await accept();
  f.data().Job.push({...f.data().Job[0],_id:ids.otherJob,acceptedBidId:ids.otherBid});
  Object.assign(f.data().Bid[1],{jobId:ids.otherJob,mechanicId:ids.mechanic,status:'accepted'});
  for(const id of [ids.driver,ids.mechanicUser]) assert.equal((await list(id)).body.data.length,2);
});
test('only owner and winner receive private assignment hints; losers receive minimal invalidation and own decline',async()=>{
  seed(); const driver=await connect(ids.driver),winner=await connect(ids.mechanicUser),loser=await connect(ids.otherMechanicUser),foreign=await connect(ids.foreign);
  assert.equal((await accept()).status,200);
  for(const [client,id] of [[driver,ids.driver],[winner,ids.mechanicUser],[loser,ids.otherMechanicUser],[foreign,ids.foreign]]) await roundTrip(client,id);
  const hint={jobId:ids.job,acceptedBidId:ids.bid,mechanicId:ids.mechanic,status:'accepted'};
  assert.deepEqual(events(driver,'bid:accepted'),[hint]);assert.deepEqual(events(winner,'job:assigned'),[hint]);
  for(const client of [loser,foreign]){assert.deepEqual(events(client,'bid:accepted'),[]);assert.deepEqual(events(client,'job:assigned'),[]);}
  assert.deepEqual(events(loser,'job:unavailable'),[{jobId:ids.job}]);
  assert.deepEqual(events(loser,'bid:declined'),[{jobId:ids.job,bidId:ids.otherBid,status:'declined'}]);
  assert.equal(JSON.stringify(loser.events).includes('labourCost'),false);assert.equal(JSON.stringify(loser.events).includes(ids.driver),false);
});
test('duplicate acceptance returns conflict and emits no second assignment',async()=>{
  seed();const winner=await connect(ids.mechanicUser);
  assert.equal((await accept()).status,200);assert.equal((await accept()).status,409);
  await roundTrip(winner,ids.mechanicUser);assert.equal(events(winner,'job:assigned').length,1);
});
test('racing acceptance publishes exactly one committed winner and declines the competitor',async()=>{
  seed();const one=await connect(ids.mechanicUser),two=await connect(ids.otherMechanicUser);
  const result=await Promise.all([accept(),accept(ids.otherBid)]);
  assert.deepEqual(result.map(r=>r.status).sort(),[200,409]);
  await roundTrip(one,ids.mechanicUser);await roundTrip(two,ids.otherMechanicUser);
  assert.equal(events(one,'job:assigned').length+events(two,'job:assigned').length,1);
  assert.equal(f.data().Bid.filter(b=>b.status==='accepted').length,1);assert.equal(f.data().Bid.filter(b=>b.status==='declined').length,1);
});
test('transaction failure rolls back records and emits no successful assignment or invalidation',async t=>{
  seed();const winner=await connect(ids.mechanicUser);
  const original=f.models.Bid.findOneAndUpdate;
  const stub=t.mock.method(f.models.Bid,'findOneAndUpdate',()=>{throw new Error('controlled write failure');});
  try {
    assert.equal((await accept()).status,500);
    await roundTrip(winner,ids.mechanicUser);assert.deepEqual(events(winner,'job:assigned'),[]);assert.deepEqual(events(winner,'job:unavailable'),[]);
    assert.equal(f.data().Job[0].status,'bidding');assert.equal(f.data().Bid[0].status,'pending');assert.equal(f.data().Bid[1].status,'pending');
  } finally {stub.mock.restore();f.models.Bid.findOneAndUpdate=original;}
});
test('job rooms admit owner/winner/admin and reject competitors before and after assignment',async()=>{
  seed();const loser=await connect(ids.otherMechanicUser);
  assert.equal((await loser.emit('join_room',{room:`job_${ids.job}`})).status,403);
  await accept();
  for(const id of [ids.driver,ids.mechanicUser,ids.admin]) {const c=await connect(id);assert.equal((await c.emit('join_room',{room:`job_${ids.job}`})).success,true);}
  assert.equal((await loser.emit('join_room',{room:`job_${ids.job}`})).status,403);
});
test('new assignment event names cannot be forged by clients',async()=>{
  const c=await connect(ids.mechanicUser);
  for(const event of ['job:assigned','job:unavailable','bid:declined','bid:accepted','chat:new']) assert.equal((await c.emit(event,{jobId:ids.job})).status,403);
});
test('disconnected winner recovers through API on startup and authorized room join after reconnect',async()=>{
  seed();await accept();
  assert.equal((await list(ids.mechanicUser)).body.data[0].acceptedBidId,ids.bid);
  const client=await connect(ids.mechanicUser);
  assert.deepEqual(events(client,'job:assigned'),[]); // no fabricated replay
  assert.equal((await client.emit('join_room',{room:`job_${ids.job}`})).success,true);
  assert.equal((await detail(ids.mechanicUser)).body.data.jobId,ids.job);
  assert.equal((await detail(ids.driver)).body.data.jobId,ids.job);
});
test('revoked or inactive mechanic loses assignment reads and private room membership',async()=>{
  seed();await accept();const client=await connect(ids.mechanicUser);
  assert.equal((await client.emit('join_room',{room:`job_${ids.job}`})).success,true);
  f.data().Mechanic[0].isApproved=false;await sockets.revokeMechanicPresence(ids.mechanic);
  assert.equal(io.sockets.sockets.get(client.socketId).rooms.has(`job_${ids.job}`),false);
  assert.equal((await list(ids.mechanicUser)).status,403);assert.equal((await detail(ids.mechanicUser)).status,403);
  assert.equal((await client.emit('join_room',{room:`job_${ids.job}`})).status,403);
  f.data().User.find(u=>u._id===ids.mechanicUser).isActive=false;
  assert.equal((await detail(ids.mechanicUser)).status,403);
});
test('assigned job is closed to opportunity checks, request recovery and further bids',async()=>{
  seed();const loser=await connect(ids.otherMechanicUser);
  await loser.emit('mechanic:go_online',{lat:31,lng:74});
  assert.equal((await request(`/jobs/${ids.job}/opportunity`,ids.otherMechanicUser)).body.data.isOpen,true);
  await accept();
  const r=await request(`/jobs/${ids.job}/opportunity`,ids.otherMechanicUser);
  assert.deepEqual(r.body.data,{jobId:ids.job,isOpen:false});
  assert.deepEqual((await request('/mechanics/requests',ids.otherMechanicUser)).body.data,[]);
  assert.equal((await request('/bids',ids.otherMechanicUser,'POST',{jobId:ids.job,labourCost:500,partsCost:0,totalCost:500,eta:10})).status,409);
  assert.equal((await request(`/jobs/${ids.job}/opportunity`,ids.foreign)).status,403);
});
test('post-commit socket publication failure does not misreport a saved acceptance as failure',async t=>{
  seed();
  const stub=t.mock.method(f.models.Mechanic,'findById',()=>{throw new Error('controlled notification read failure');});
  try {
    const r=await accept();assert.equal(r.status,200);assert.equal(r.body.data.status,'accepted');
    assert.equal(f.data().Job[0].acceptedBidId,ids.bid);assert.equal(f.data().Bid[1].status,'declined');
  } finally {stub.mock.restore();}
  assert.equal((await detail(ids.driver)).body.data.acceptedBidId,ids.bid);
});

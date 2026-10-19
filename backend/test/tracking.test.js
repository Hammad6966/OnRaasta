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
beforeEach(() => { f.reset('unused-fixture-hash'); presence.clear(); tracking.clearCache(); apiLimiter.resetKey('127.0.0.1'); });
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
function assigned(status='accepted') {
  Object.assign(f.data().Job[0],{status,mechanicId:ids.mechanic,acceptedBidId:ids.bid,statusVersion:0});
  f.data().Bid.push({_id:ids.bid,jobId:ids.job,mechanicId:ids.mechanic,status:'accepted',labourCost:900.5,partsCost:200.25,totalCost:1100.75,eta:12});
}
const change=(status,id=ids.mechanicUser,extra={})=>request(`/jobs/${ids.job}/status`,id,'PATCH',{status,...extra});
const tracking = require('../src/services/job-tracking.service');
const statusEvents=c=>c.events.filter(e=>e[0]==='job:status_changed').map(e=>e[1]);
const flush=(c,id)=>c.emit('join_room',{room:`user_${id}`});

const input=(extra={})=>({jobId:ids.job,lat:31,lng:74,accuracy:12,observedAt:new Date().toISOString(),...extra});
const actor={id:ids.mechanicUser,role:'mechanic'};
const locations=c=>c.events.filter(e=>e[0]==='job:mechanic_location').map(e=>e[1]);
test('assigned mechanic publishes canonical observation to owner only, one delivery per socket',async()=>{
  assigned('en_route');const driver=await connect(ids.driver),mechanic=await connect(ids.mechanicUser),loser=await connect(ids.otherMechanicUser),foreign=await connect(ids.foreign);
  await driver.emit('join_room',{room:`job_${ids.job}`});const ack=await mechanic.emit('job:mechanic_location',input());
  assert.equal(ack.success,true);assert.equal(ack.data.accepted,true);assert.equal(ack.data.persisted,true);
  for(const [c,id] of [[driver,ids.driver],[mechanic,ids.mechanicUser],[loser,ids.otherMechanicUser],[foreign,ids.foreign]])await flush(c,id);
  const event=locations(driver);assert.equal(event.length,1);assert.equal(event[0].jobId,ids.job);assert.equal(event[0].mechanicId,ids.mechanic);
  assert.deepEqual(Object.keys(event[0]).sort(),['accuracy','jobId','lat','lng','mechanicId','observedAt','receivedAt']);
  assert.equal(event[0].lat,31);assert.ok(Date.parse(event[0].receivedAt));
  for(const c of [mechanic,loser,foreign])assert.deepEqual(locations(c),[]);
});
test('drivers and unassigned/unapproved mechanics cannot publish; unrelated and missing jobs are rejected',async()=>{
  assigned('en_route');for(const id of [ids.driver,ids.foreign,ids.otherMechanicUser,ids.unapprovedUser]){
    const c=await connect(id);assert.equal((await c.emit('job:mechanic_location',input())).status,403);
  }
  const c=await connect(ids.mechanicUser);assert.equal((await c.emit('job:mechanic_location',input({jobId:ids.otherJob}))).status,404);
  delete f.data().Job[0].mechanicId;assert.equal((await c.emit('job:mechanic_location',input())).status,403);
});
for(const status of ['pending','bidding','accepted','arrived','in_progress','completed','cancelled'])test(`tracking is forbidden in ${status}`,async()=>{
  assigned(status);await assert.rejects(tracking.publish(actor,input(),null),e=>e.status===409);
});
test('invalid coordinates, accuracy and timestamp fail without persistence',async()=>{
  assigned('en_route');const c=await connect(ids.mechanicUser);
  for(const extra of [{lat:91},{lng:181},{lat:'31'},{lat:0,lng:0},{accuracy:-1},{accuracy:101},{accuracy:'12'},
    {observedAt:'bad'},{observedAt:new Date(Date.now()-61000).toISOString()},{observedAt:new Date(Date.now()+11000).toISOString()},
    {observedAt:'2026-02-30T12:00:00Z'},{jobId:'bad'}])assert.equal((await c.emit('job:mechanic_location',input(extra))).status,400);
  assert.equal(f.data().Job[0].latestMechanicLocation,undefined);
});
test('publisher cannot supply identity, server timestamps or arbitrary relay fields',async()=>{
  assigned('en_route');const c=await connect(ids.mechanicUser);
  for(const extra of [{mechanicId:ids.otherMechanic},{userId:ids.foreign},{receivedAt:new Date().toISOString()},{status:'completed'},{documents:[]}])assert.equal((await c.emit('job:mechanic_location',input(extra))).status,403);
});
test('approval and account state are rechecked after handshake',async()=>{
  assigned('en_route');const c=await connect(ids.mechanicUser);f.data().Mechanic[0].isApproved=false;assert.equal((await c.emit('job:mechanic_location',input())).status,403);
  f.data().Mechanic[0].isApproved=true;f.data().User.find(u=>u._id===ids.mechanicUser).isActive=false;assert.equal((await c.emit('job:mechanic_location',input())).status,403);
});
test('duplicate observation is acknowledged without duplicate relay or write',async()=>{
  assigned('en_route');const d=await connect(ids.driver),m=await connect(ids.mechanicUser),point=input();
  await m.emit('job:mechanic_location',point);const first=f.data().Job[0].latestMechanicLocation;
  const again=await m.emit('job:mechanic_location',point);assert.equal(again.data.accepted,false);assert.equal(again.data.reason,'duplicate');await flush(d,ids.driver);
  assert.equal(locations(d).length,1);assert.deepEqual(f.data().Job[0].latestMechanicLocation,first);
});
test('rate limit, reordered observations and implausible jumps are rejected',async()=>{
  assigned('en_route');const now=Date.now();await tracking.publish(actor,input({observedAt:new Date(now).toISOString()}),null,now);
  await assert.rejects(tracking.publish(actor,input({lat:31.0001,observedAt:new Date(now+1000).toISOString()}),null,now+1000),e=>e.status===429);
  await assert.rejects(tracking.publish(actor,input({lat:31.0001,observedAt:new Date(now-1000).toISOString()}),null,now+6000),e=>e.status===409);
  await assert.rejects(tracking.publish(actor,input({lat:34,observedAt:new Date(now+6000).toISOString()}),null,now+6000),e=>e.status===400);
});
test('latest persistence is throttled to 15 seconds while intermediate real observations are recoverable in memory',async()=>{
  assigned('en_route');const now=Date.now();
  for(const [offset,lat,persisted] of [[0,31,true],[6000,31.0001,false],[16000,31.0002,true]]) {
    const result=await tracking.publish(actor,input({lat,observedAt:new Date(now+offset).toISOString()}),null,now+offset);assert.equal(result.persisted,persisted);
    assert.equal(f.data().Job[0].latestMechanicLocation.lat,persisted?lat:31);
  }
});
test('owner/assigned mechanic/admin recover latest; foreign participants cannot and empty location is honest',async()=>{
  assigned('en_route');assert.equal((await request(`/jobs/${ids.job}/location`,ids.driver)).body.data.location,null);
  await tracking.publish(actor,input(),null);tracking.clearCache(); // server restart loses only the unpersisted tail
  for(const id of [ids.driver,ids.mechanicUser,ids.admin]){const r=await request(`/jobs/${ids.job}/location`,id);assert.equal(r.status,200);assert.equal(r.body.data.location.lat,31);assert.equal(r.body.data.fresh,true);assert.ok(r.body.data.serverTime);}
  for(const id of [ids.foreign,ids.otherMechanicUser])assert.equal((await request(`/jobs/${ids.job}/location`,id)).status,403);
  assert.equal((await request(`/jobs/${ids.job}/location`,null)).status,401);
});
test('stale snapshots are explicitly stale and expired snapshots are hidden and scrubbed without deleting Jobs',async()=>{
  assigned('en_route');await tracking.publish(actor,input(),null);tracking.clearCache();
  const point=f.data().Job[0].latestMechanicLocation;point.observedAt=new Date(Date.now()-90000);point.receivedAt=new Date(Date.now()-90000);
  let r=await request(`/jobs/${ids.job}/location`,ids.driver);assert.equal(r.body.data.fresh,false);assert.ok(r.body.data.location);
  point.expiresAt=new Date(Date.now()-1000);r=await request(`/jobs/${ids.job}/location`,ids.driver);assert.equal(r.body.data.location,null);
  await tracking.sweep();assert.equal(f.data().Job.length,1);assert.equal(f.data().Job[0].latestMechanicLocation,null);
});
test('explicit arrival stops tracking, clears the persisted point and never follows GPS proximity automatically',async()=>{
  assigned('en_route');await tracking.publish(actor,input(),null);assert.equal(f.data().Job[0].status,'en_route');
  assert.equal((await change('arrived')).status,200);assert.equal(f.data().Job[0].latestMechanicLocation,null);
  const r=await request(`/jobs/${ids.job}/location`,ids.driver);assert.equal(r.body.data.trackingAllowed,false);assert.equal(r.body.data.location,null);
  await assert.rejects(tracking.publish(actor,input(),null),e=>e.status===409);
});
test('revocation or reassignment prevents disclosure of an earlier point',async()=>{
  assigned('en_route');await tracking.publish(actor,input(),null);f.data().Mechanic[0].isApproved=false;
  assert.equal((await request(`/jobs/${ids.job}/location`,ids.driver)).body.data.location,null);
  f.data().Mechanic[0].isApproved=true;f.data().Job[0].mechanicId=ids.otherMechanic;
  assert.equal((await request(`/jobs/${ids.job}/location`,ids.driver)).body.data.location,null);
});
test('tracking error does not silently remove independent mechanic availability',async()=>{
  assigned('accepted');const c=await connect(ids.mechanicUser);await c.emit('mechanic:go_online',{lat:31,lng:74});
  assert.equal((await c.emit('job:mechanic_location',input())).status,409);assert.equal(presence.isOnline(ids.mechanic),true);
});
test('tracking storage is excluded from ordinary Mongoose projections',()=>{assert.equal(f.models.Job.schema.path('latestMechanicLocation').options.select,false);});
test('invalid tracking attempts are bounded per authenticated mechanic without disrupting sockets',async()=>{
  assigned('en_route');const now=Date.now();
  for(let i=0;i<60;i++)await assert.rejects(tracking.publish(actor,input({lat:91}),null,now),e=>e.status===400);
  await assert.rejects(tracking.publish(actor,input(),null,now),e=>e.status===429);
});
test('cancellation and location publication serialize: no observation is relayed after terminal confirmation',async()=>{
  assigned('en_route');const d=await connect(ids.driver),m=await connect(ids.mechanicUser);
  const [point,cancel]=await Promise.all([m.emit('job:mechanic_location',input()),change('cancelled',ids.driver)]);
  assert.ok(point.success || point.status===409);assert.equal(cancel.status,200);await flush(d,ids.driver);
  const events=d.events.map(e=>e[0]),location=events.indexOf('job:mechanic_location'),closed=events.indexOf('job:status_changed');
  assert.ok(closed>=0);assert.ok(location<0 || location<closed);assert.equal(f.data().Job[0].latestMechanicLocation,null);
});

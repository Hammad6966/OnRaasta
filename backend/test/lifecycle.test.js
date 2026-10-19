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
function assigned(status='accepted') {
  Object.assign(f.data().Job[0],{status,mechanicId:ids.mechanic,acceptedBidId:ids.bid,statusVersion:0});
  f.data().Bid.push({_id:ids.bid,jobId:ids.job,mechanicId:ids.mechanic,status:'accepted',labourCost:900.5,partsCost:200.25,totalCost:1100.75,eta:12});
}
const change=(status,id=ids.mechanicUser,extra={})=>request(`/jobs/${ids.job}/status`,id,'PATCH',{status,...extra});
const statusEvents=c=>c.events.filter(e=>e[0]==='job:status_changed').map(e=>e[1]);
const flush=(c,id)=>c.emit('join_room',{room:`user_${id}`});

test('each required repair stage persists exactly one version and its milestone without financial mutations',async()=>{
  assigned();let version=0;
  for(const [status,key] of [['en_route','enRouteAt'],['arrived','arrivedAt'],['in_progress','startedAt'],['completed','completedAt']]){
    const r=await change(status);assert.equal(r.status,200);assert.equal(r.body.job.status,status);assert.equal(r.body.job.statusVersion,++version);
    assert.ok(Date.parse(r.body.job[key]));assert.equal(r.body.job[key],r.body.job.statusChangedAt);
    const read=await request(`/jobs/${ids.job}/assignment`,ids.driver);assert.equal(read.body.data.job.status,status);assert.equal(read.body.data.job.statusVersion,version);
    assert.equal(read.body.data.totalCost,1100.75);assert.equal(read.body.data.labourCost,900.5);assert.equal(read.body.data.partsCost,200.25);
  }
  assert.equal(f.data().Job[0].finalCost,undefined);assert.equal(f.data().Mechanic[0].earnings,undefined);assert.equal(f.data().Mechanic[0].totalJobs,undefined);
});
for(const [from,to] of [['accepted','arrived'],['accepted','in_progress'],['accepted','completed'],['en_route','in_progress'],['arrived','completed'],['arrived','en_route'],['in_progress','arrived']]) {
  test(`rejects skipped/backwards ${from} -> ${to}`,async()=>{assigned(from);assert.equal((await change(to)).status,409);assert.equal(f.data().Job[0].status,from);assert.equal(f.data().Job[0].statusVersion,0);});
}
test('invalid values and protected mutation metadata fail validation',async()=>{
  assigned();for(const value of ['finished','',null,{},7])assert.equal((await change(value)).status,400);
  for(const extra of [{mechanicId:ids.mechanic},{userId:ids.driver},{completedAt:'2026-01-01'},{finalCost:1},{expectedVersion:-1},{expectedVersion:'0'},{expectedStatus:'made_up'}])assert.equal((await change('en_route',ids.mechanicUser,extra)).status,400);
});
test('missing and foreign/authentication paths return proper errors',async()=>{
  assigned();assert.equal((await change('en_route',null)).status,401);
  assert.equal((await request(`/jobs/${ids.otherJob}/status`,ids.mechanicUser,'PATCH',{status:'en_route'})).status,404);
  for(const id of [ids.driver,ids.foreign,ids.otherMechanicUser,ids.admin])assert.equal((await change('en_route',id)).status,403);
});
test('approval and live active/verified account are required at mutation time',async()=>{
  assigned();f.data().Mechanic[0].isApproved=false;assert.equal((await change('en_route')).status,403);f.data().Mechanic[0].isApproved=true;
  const user=f.data().User.find(u=>u._id===ids.mechanicUser);user.isActive=false;assert.equal((await change('en_route')).status,403);user.isActive=true;user.isVerified=false;assert.equal((await change('en_route')).status,403);
  assert.equal(f.data().Job[0].status,'accepted');
});
test('stale expected status/version cannot advance even if target would now be legal',async()=>{
  assigned();assert.equal((await change('en_route',ids.mechanicUser,{expectedStatus:'accepted',expectedVersion:0})).status,200);
  assert.equal((await change('arrived',ids.mechanicUser,{expectedStatus:'accepted',expectedVersion:0})).status,409);
  assert.equal((await change('arrived',ids.mechanicUser,{expectedStatus:'en_route',expectedVersion:0})).status,409);
  assert.equal((await change('arrived',ids.mechanicUser,{expectedStatus:'en_route',expectedVersion:1})).status,200);
});
test('legacy Jobs without statusVersion transition safely without migration',async()=>{
  assigned();delete f.data().Job[0].statusVersion;const r=await change('en_route');assert.equal(r.status,200);assert.equal(r.body.job.statusVersion,1);
});
test('repeated completion is a deterministic conflict and never repeats side effects or event',async()=>{
  assigned('in_progress');const c=await connect(ids.mechanicUser);
  assert.equal((await change('completed')).status,200);const completedAt=f.data().Job[0].completedAt;
  assert.equal((await change('completed')).status,409);await flush(c,ids.mechanicUser);
  assert.equal(statusEvents(c).length,1);assert.deepEqual(f.data().Job[0].completedAt,completedAt);assert.equal(f.data().Job[0].statusVersion,1);
});
test('simultaneous completion requests have one persisted winner',async()=>{
  assigned('in_progress');const results=await Promise.all([change('completed'),change('completed')]);assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);assert.equal(f.data().Job[0].statusVersion,1);
});
test('competing driver cancellation/mechanic progression from one snapshot cannot overwrite each other',async()=>{
  assigned('en_route');const results=await Promise.all([change('arrived',ids.mechanicUser,{expectedStatus:'en_route',expectedVersion:0}),change('cancelled',ids.driver,{expectedStatus:'en_route',expectedVersion:0})]);
  assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);assert.equal(f.data().Job[0].statusVersion,1);
});
test('owner pre-arrival and admin nonterminal cancellation permissions are preserved',async()=>{
  assigned('en_route');assert.equal((await change('cancelled',ids.driver)).status,200);assert.ok(f.data().Job[0].cancelledAt);
  f.data().Job[0].status='arrived';assert.equal((await change('cancelled',ids.driver)).status,409);assert.equal((await change('cancelled',ids.admin)).status,200);
});
for(const state of ['completed','cancelled'])test(`terminal ${state} cannot reopen or be completed again`,async()=>{
  assigned(state);for(const target of ['en_route','arrived','in_progress','completed'])assert.equal((await change(target)).status,409);
  assert.equal((await change('cancelled',ids.admin)).status,409);
});
test('post-commit event reaches owner and winner once even with overlapping job/personal rooms; excludes competitors',async()=>{
  assigned();const driver=await connect(ids.driver),winner=await connect(ids.mechanicUser),other=await connect(ids.otherMechanicUser);
  await driver.emit('join_room',{room:`job_${ids.job}`});await winner.emit('join_room',{room:`job_${ids.job}`});
  assert.equal((await change('en_route')).status,200);
  for(const [c,id] of [[driver,ids.driver],[winner,ids.mechanicUser],[other,ids.otherMechanicUser]])await flush(c,id);
  for(const c of [driver,winner]){assert.equal(statusEvents(c).length,1);const e=statusEvents(c)[0];assert.equal(e.jobId,ids.job);assert.equal(e.status,f.data().Job[0].status);assert.equal(e.version,1);assert.equal(e.changedAt,f.data().Job[0].statusChangedAt.toISOString());assert.deepEqual(Object.keys(e).sort(),['changedAt','jobId','status','version']);}
  assert.deepEqual(statusEvents(other),[]);
});
test('failed persistence rolls back timestamp/version and publishes nothing',async t=>{
  assigned();const c=await connect(ids.driver);const stub=t.mock.method(f.models.Job,'findOneAndUpdate',()=>{throw new Error('controlled persistence failure');});
  try {assert.equal((await change('en_route')).status,500);await flush(c,ids.driver);assert.deepEqual(statusEvents(c),[]);assert.equal(f.data().Job[0].statusVersion,0);assert.equal(f.data().Job[0].enRouteAt,undefined);}finally{stub.mock.restore();}
});
test('missed status notification is recovered by persisted assignment after reconnect',async()=>{
  assigned('arrived');assert.equal((await change('in_progress')).status,200);const c=await connect(ids.driver);
  assert.deepEqual(statusEvents(c),[]);const saved=await request(`/jobs/${ids.job}/assignment`,ids.driver);assert.equal(saved.body.data.status,'in_progress');assert.equal(saved.body.data.job.statusVersion,1);
});
test('clients cannot forge lifecycle events',async()=>{assigned();const c=await connect(ids.mechanicUser);assert.equal((await c.emit('job:status_changed',{jobId:ids.job,status:'completed'})).status,403);assert.equal(f.data().Job[0].status,'accepted');});
test('offline completion recovery includes recent closed jobs only by explicit authorized request',async()=>{
  assigned('in_progress');await change('completed');
  assert.deepEqual((await request('/jobs/assignments',ids.driver)).body.data,[]);
  for(const id of [ids.driver,ids.mechanicUser]) {
    const r=await request('/jobs/assignments?includeClosed=true',id);
    assert.equal(r.body.data[0].status,'completed');assert.equal(r.body.data[0].job.statusVersion,1);
  }
  assert.deepEqual((await request('/jobs/assignments?includeClosed=true',ids.foreign)).body.data,[]);
  assert.equal((await request('/jobs/assignments?includeClosed=invalid',ids.driver)).status,400);
});
test('closed assignment recovery is bounded to ten while preserving all active assignments',async()=>{
  assigned();
  for(let i=100;i<112;i++) {
    const id=i.toString(16).padStart(24,'0'),bid=(i+100).toString(16).padStart(24,'0');
    f.data().Job.push({...f.data().Job[0],_id:id,acceptedBidId:bid,status:'completed'});
    f.data().Bid.push({...f.data().Bid[0],_id:bid,jobId:id});
  }
  const r=await request('/jobs/assignments?includeClosed=true',ids.driver);
  assert.equal(r.body.data.filter(a=>a.status==='completed').length,10);assert.equal(r.body.data.filter(a=>a.status==='accepted').length,1);
});
test('publication failure after a committed status update cannot turn persistence into apparent HTTP failure',async t=>{
  assigned();const stub=t.mock.method(f.models.Mechanic,'findById',()=>{throw new Error('controlled transport read failure');});
  try {const r=await change('en_route');assert.equal(r.status,200);assert.equal(r.body.job.statusVersion,1);assert.equal(f.data().Job[0].status,'en_route');}
  finally {stub.mock.restore();}
  assert.equal((await request(`/jobs/${ids.job}/assignment`,ids.driver)).body.data.status,'en_route');
});

const { test, before, after, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = crypto.randomBytes(32).toString('hex');
process.env.JWT_REFRESH_SECRET = crypto.randomBytes(32).toString('hex');
const f = require('./fixtures'); f.install(mock);
const { ids } = f;
const { signAccessToken } = require('../src/services/access.service');
const { apiLimiter } = require('../src/middleware/rate-limit.middleware');
const app = require('../src/app');
const server = http.createServer(app); let base;
before(async () => { await new Promise(r => server.listen(0, '127.0.0.1', r)); base = `http://127.0.0.1:${server.address().port}/api`; });
after(async () => { await new Promise(r => server.close(r)); mock.restoreAll(); });
beforeEach(() => { f.reset('PRIVATE'); apiLimiter.resetKey('127.0.0.1'); });
function seed(jobId = ids.job, bidId = ids.bid, userId = ids.driver) {
  let job = f.data().Job.find(j => j._id === jobId);
  if (!job) { job = { _id: jobId, userId }; f.data().Job.push(job); }
  Object.assign(job, { status: 'completed', mechanicId: ids.mechanic, acceptedBidId: bidId });
  f.data().Bid.push({ _id: bidId, jobId, mechanicId: ids.mechanic, status: 'accepted' });
  return job;
}
async function request(path, {id = ids.driver, method = 'GET', body, rawToken} = {}) {
  const user = f.data().User.find(u => u._id === id);
  const token = rawToken ?? (user ? signAccessToken(user) : null);
  const r = await fetch(base + path, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: r.status, body: await r.json() };
}
const submit = (body = {stars: 5}, opts = {}) => request(`/jobs/${opts.jobId ?? ids.job}/review`, { method: 'POST', body, ...opts });
const list = (query='',id=ids.driver) => request(`/mechanics/${ids.mechanic}/reviews${query}`, {id});
test('completed review persists exact Job/Mechanic IDs and safe reputation response',async()=>{
  seed(); const r = await submit({stars:5,tags:['Professional'],comment:' <b>Great</b>\u0000 work '});
  assert.equal(r.status,200); assert.equal(r.body.data.jobId,ids.job); assert.equal(r.body.data.mechanicId,ids.mechanic);
  assert.equal(r.body.data.review.comment,'Great work'); assert.equal(f.data().Job[0].review.stars,5);
  assert.deepEqual(r.body.data.reputation,{rating:5,reviewCount:1,distribution:{1:0,2:0,3:0,4:0,5:1}});
  assert.equal(f.data().Mechanic[0].reviewCount,1); assert.equal(f.data().Mechanic[1].rating,3);
});
test('all unfinished and cancelled states reject review',async()=>{
  const job=seed(); for(const status of ['pending','bidding','accepted','en_route','arrived','in_progress','cancelled']) {
    job.status=status; assert.equal((await submit()).status,409);
  }
});
test('foreign driver and mechanic cannot submit',async()=>{
  seed(); assert.equal((await submit({stars:5},{id:ids.foreign})).status,403);
  assert.equal((await submit({stars:5},{id:ids.mechanicUser})).status,403);
});
test('missing, invalid, expired and refresh JWT are rejected',async()=>{
  seed(); const jwt=require('jsonwebtoken');
  for(const rawToken of ['bad', jwt.sign({id:ids.driver,tokenUse:'access'},process.env.JWT_SECRET,{expiresIn:-1}),
    jwt.sign({id:ids.driver,tokenUse:'refresh'},process.env.JWT_SECRET,{expiresIn:100})]) assert.equal((await submit({stars:5},{rawToken})).status,401);
  assert.equal((await submit({stars:5},{id:null})).status,401);
});
test('inactive account cannot review',async()=>{
  seed(); f.data().User[0].isActive=false; assert.equal((await submit()).status,403);
});
test('missing assignment, wrong accepted bid, wrong profile and absent mechanic rejected',async()=>{
  const job=seed(); delete job.acceptedBidId; assert.equal((await submit()).status,409);
  job.acceptedBidId=ids.bid; f.data().Bid[0].mechanicId=ids.otherMechanic; assert.equal((await submit()).status,409);
  f.data().Bid[0].mechanicId=ids.mechanic; f.data().Bid[0].status='declined'; assert.equal((await submit()).status,409);
  f.data().Bid[0].status='accepted'; f.data().Mechanic.shift(); assert.equal((await submit()).status,409);
});
test('missing job returns 404, malformed ID returns 400',async()=>{
  assert.equal((await submit({stars:5},{jobId:ids.otherJob})).status,404);
  assert.equal((await submit({stars:5},{jobId:'broken'})).status,400);
});
test('stars must be integer 1 through 5, tags vocabulary/duplicates/bounds and comment validated',async()=>{
  seed(); for(const body of [{stars:0},{stars:6},{stars:2.5},{stars:'5'},{stars:null},{stars:5,tags:['Invented']},
    {stars:5,tags:['Friendly','Friendly']},{stars:5,tags:['Friendly','Skilled','On Time','Professional']},
    {stars:5,comment:'x'.repeat(301)},{stars:5,comment:{}},{stars:5,mechanicId:ids.otherMechanic}]) assert.equal((await submit(body)).status,400);
  assert.equal((await submit({stars:1,comment:'x'.repeat(300)})).status,200);
});
test('duplicate sequential and concurrent submissions count exactly once',async()=>{
  seed(); const results=await Promise.all([submit({stars:4}),submit({stars:4})]);
  assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);
  assert.equal((await submit()).status,409); assert.equal(f.data().Mechanic[0].reviewCount,1); assert.equal(f.data().Mechanic[0].rating,4);
});
test('different drivers concurrently review one profile without lost aggregate updates',async()=>{
  seed(); seed(ids.otherJob,ids.otherBid,ids.foreign);
  const r=await Promise.all([submit({stars:5}),submit({stars:2},{jobId:ids.otherJob,id:ids.foreign})]);
  assert.deepEqual(r.map(v=>v.status),[200,200]); assert.equal(f.data().Mechanic[0].rating,3.5); assert.equal(f.data().Mechanic[0].reviewCount,2);
});
test('aggregate excludes unassigned, incomplete, foreign and malformed historical reviews',async()=>{
  seed(); seed(ids.otherJob,ids.otherBid,ids.foreign).review={stars:3,createdAt:new Date()};
  f.data().Job.push(...[
    {status:'completed',review:{stars:5,createdAt:new Date()}},
    {status:'cancelled',acceptedBidId:ids.otherBid,review:{stars:1,createdAt:new Date()}},
    {status:'completed',acceptedBidId:ids.otherBid,review:{stars:2.5,createdAt:new Date()}},
  ].map((j,i)=>({_id:(200+i).toString(16).padStart(24,'0'),mechanicId:ids.mechanic,...j})));
  await submit({stars:4}); assert.equal(f.data().Mechanic[0].rating,3.5); assert.equal(f.data().Mechanic[0].reviewCount,2);
});
test('transaction failure rolls back review and reputation together',async()=>{
  seed(); const original=f.models.Mechanic.findOneAndUpdate;
  const stub=mock.method(f.models.Mechanic,'findOneAndUpdate',(filter,change,options)=>{
    if(change.$set?.reviewCount) throw new Error('PRIVATE database error'); return original(filter,change,options);
  });
  try { const r=await submit(); assert.equal(r.status,500); assert.equal(JSON.stringify(r.body).includes('PRIVATE'),false);
    assert.equal(f.data().Job[0].review,undefined); assert.equal(f.data().Mechanic[0].reviewCount,undefined);
  } finally {stub.mock.restore();}
});
test('zero reviews has honest zero average and distribution',async()=>{
  const r=await list(); assert.equal(r.status,200); assert.equal(r.body.data.rating,0); assert.equal(r.body.data.reviewCount,0);
  assert.deepEqual(r.body.data.reviews,[]); assert.deepEqual(r.body.data.distribution,{1:0,2:0,3:0,4:0,5:0});
});
test('review pages are bounded, newest first, anonymous and safe',async()=>{
  for(let i=0;i<12;i++) {
    const jobId=(300+i).toString(16).padStart(24,'0'),bidId=(400+i).toString(16).padStart(24,'0');
    const j=seed(jobId,bidId); j.review={stars:5,tags:['Friendly','PRIVATE'],comment:'<i>Review '+i+'</i>',createdAt:new Date(2026,0,i+1)};
  }
  const r=await list('?page=1&limit=10'); assert.equal(r.body.data.reviews.length,10); assert.equal(r.body.data.hasMore,true);
  assert.equal(r.body.data.reviews[0].comment,'Review 11');
  assert.deepEqual(Object.keys(r.body.data.reviews[0]).sort(),['comment','createdAt','stars','tags']);
  for(const word of ['PRIVATE','password','email','phone','userId','jobId','documents']) assert.equal(JSON.stringify(r.body).includes(word),false);
  const second=await list('?page=2&limit=10'); assert.equal(second.body.data.reviews.length,2); assert.equal(second.body.data.hasMore,false);
  const stats=r.body.data; assert.equal(stats.reviewCount,12); assert.equal(stats.distribution[5],12);
});
test('read authentication, approval and pagination restrictions',async()=>{
  assert.equal((await list('',null)).status,401);
  f.data().Mechanic[0].isApproved=false;
  assert.equal((await list()).status,403); assert.equal((await list('',ids.mechanicUser)).status,200); assert.equal((await list('',ids.admin)).status,200);
  f.data().Mechanic[0].isApproved=true;
  for(const q of ['?page=0','?limit=51','?page=x','?limit=0','?page=1&page=2','?unknown=1']) assert.equal((await list(q)).status,400);
});

test('published summary matches stored reputation and leaves assignment/financial data intact',async()=>{
  const job=seed(); job.finalCost=1100.75; f.data().Mechanic[0].earnings=1234;
  await submit({stars:4});
  const publicRead=await list();
  assert.equal(publicRead.body.data.reviewCount,f.data().Mechanic[0].reviewCount);
  assert.equal(publicRead.body.data.rating,f.data().Mechanic[0].rating);
  const profile=await request('/mechanics/profile',{id:ids.mechanicUser});
  assert.equal(profile.body.data.reviewCount,1); assert.equal(profile.body.data.rating,4);
  assert.equal(f.data().Job[0].status,'completed'); assert.equal(f.data().Job[0].acceptedBidId,ids.bid);
  assert.equal(f.data().Job[0].finalCost,1100.75); assert.equal(f.data().Mechanic[0].earnings,1234);
});

test('reading legacy reputation repairs cached average/count from valid evidence without touching jobs',async()=>{
  const job=seed(); job.review={stars:3,tags:[],comment:'Historical persisted review',createdAt:new Date()};
  const before=structuredClone(f.data().Job); f.data().Mechanic[0].rating=4.9; f.data().Mechanic[0].reviewCount=500;
  const r=await list(); assert.equal(r.status,200); assert.equal(r.body.data.rating,3); assert.equal(r.body.data.reviewCount,1);
  assert.equal(f.data().Mechanic[0].rating,3); assert.equal(f.data().Mechanic[0].reviewCount,1);
  assert.deepEqual(f.data().Job,before);
});

test('legacy read reconciliation cannot overwrite a concurrent newly submitted review',async()=>{
  seed(); f.data().Mechanic[0].rating=4.9; f.data().Mechanic[0].reviewCount=500;
  const results=await Promise.all([list(),submit({stars:5})]);
  assert.deepEqual(results.map(r=>r.status),[200,200]);
  assert.equal(f.data().Mechanic[0].rating,5); assert.equal(f.data().Mechanic[0].reviewCount,1);
});

const { test, before, after, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const crypto = require('node:crypto');
const jwt = require('jsonwebtoken');
process.env.NODE_ENV='test';
process.env.JWT_SECRET=crypto.randomBytes(32).toString('hex');
process.env.JWT_REFRESH_SECRET=crypto.randomBytes(32).toString('hex');
const f=require('./fixtures');f.install(mock);
const { ids }=f;
const session=require('../src/services/refresh-session.service');
const { authenticateAccessToken }=require('../src/services/access.service');
const { apiLimiter,authLimiter }=require('../src/middleware/rate-limit.middleware');
const sockets=require('../src/socket/socket');
const server=http.createServer(require('../src/app'));const io=sockets.initSocket(server);let base;
before(async()=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));base=`http://127.0.0.1:${server.address().port}/api`;});
after(async()=>{await new Promise(r=>io.close(r));mock.restoreAll();});
beforeEach(()=>{f.reset('fixture');apiLimiter.resetKey('127.0.0.1');authLimiter.resetKey('127.0.0.1');});
const issue=(id=ids.driver)=>session.issue(f.data().User.find(u=>u._id===id));
async function request(path,body,token) {
  const r=await fetch(base+path,{method:body===undefined?'GET':'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:body===undefined?undefined:JSON.stringify(body)});
  return {status:r.status,body:await r.json(),cache:r.headers.get('cache-control')};
}
const refresh=t=>request('/auth/refresh',{refreshToken:t});
test('session issuance preserves 15 minute access and 7 day refresh, hashed storage and safe user',async()=>{
  const t=await issue(),a=jwt.decode(t.accessToken),r=jwt.decode(t.refreshToken);
  assert.equal(a.exp-a.iat,900);assert.equal(r.exp-r.iat,604800);assert.equal(a.sid,r.sid);assert.equal(r.tokenUse,'refresh');
  const doc=f.data().RefreshSession[0];assert.equal(doc.tokenHash,session.hash(t.refreshToken));assert.equal(JSON.stringify(doc).includes(t.refreshToken),false);
  assert.equal('passwordHash' in t.user,false);assert.equal(f.models.RefreshSession.schema.path('tokenHash').options.select,false);
  assert.ok(f.models.RefreshSession.schema.indexes().some(([fields,opts])=>fields.expiresAt===1&&opts.expireAfterSeconds===0));
});
test('valid refresh rotates both tokens with same session and authoritative identity',async()=>{
  const t=await issue();const r=await refresh(t.refreshToken);assert.equal(r.status,200);assert.notEqual(r.body.refreshToken,t.refreshToken);
  assert.equal(r.body.user.id,ids.driver);assert.equal(jwt.decode(r.body.accessToken).sid,jwt.decode(t.accessToken).sid);
  assert.equal(f.data().RefreshSession[0].tokenHash,session.hash(r.body.refreshToken));assert.equal(r.cache,'no-store');
});
test('immediate concurrent legitimate refresh gets one winner and a non-revoking conflict',async()=>{
  const t=await issue();const results=await Promise.all([refresh(t.refreshToken),refresh(t.refreshToken)]);
  assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);assert.equal(f.data().RefreshSession[0].revokedAt,null);
  const winner=results.find(r=>r.status===200);assert.equal((await refresh(winner.body.refreshToken)).status,200);
});
test('old refresh replay after overlap revokes affected family and access',async()=>{
  const t=await issue();const rotated=await refresh(t.refreshToken);
  f.data().RefreshSession[0].rotatedAt=new Date(Date.now()-session.OVERLAP_MS-10);
  assert.equal((await refresh(t.refreshToken)).status,401);assert.ok(f.data().RefreshSession[0].revokedAt);
  await assert.rejects(authenticateAccessToken(rotated.body.accessToken),e=>e.status===401);
  assert.equal((await refresh(rotated.body.refreshToken)).status,401);
});
test('replaying an older generation revokes immediately even within overlap',async()=>{
  const t=await issue(),r1=await session.rotate(t.refreshToken);await session.rotate(r1.refreshToken);
  await assert.rejects(session.rotate(t.refreshToken),e=>e.status===401);assert.ok(f.data().RefreshSession[0].revokedAt);
});
test('invalid, access-purpose, expired and legacy refresh tokens are rejected',async()=>{
  const t=await issue(),decoded=jwt.decode(t.refreshToken);delete decoded.iat;delete decoded.exp;
  for(const token of ['invalid',t.accessToken,jwt.sign(decoded,process.env.JWT_REFRESH_SECRET,{expiresIn:-1}),
    jwt.sign({id:ids.driver,role:'user',tokenUse:'refresh'},process.env.JWT_REFRESH_SECRET,{expiresIn:'7d'})]) {
    assert.equal((await refresh(token)).status,401);
  }
});
test('logout revokes only its session; repeated logout is idempotent',async()=>{
  const one=await issue(),two=await issue();assert.notEqual(one.refreshToken,two.refreshToken);
  assert.equal((await request('/auth/logout',{refreshToken:one.refreshToken})).status,200);
  assert.equal((await request('/auth/logout',{refreshToken:one.refreshToken})).status,200);
  assert.equal((await refresh(one.refreshToken)).status,401);
  assert.equal((await refresh(two.refreshToken)).status,200);
  await assert.rejects(authenticateAccessToken(one.accessToken),e=>e.status===401);
  assert.equal((await authenticateAccessToken(two.accessToken)).id,ids.driver);
});
test('active and verified account state remains authoritative',async()=>{
  for(const field of ['isActive','isVerified']) {
    f.reset('fixture');const t=await issue();f.data().User[0][field]=false;
    assert.equal((await refresh(t.refreshToken)).status,403);
    await assert.rejects(authenticateAccessToken(t.accessToken),e=>e.status===403);
    assert.ok(f.data().RefreshSession[0].revokedAt);
  }
});
test('role changes cannot reuse old session to change app identity',async()=>{
  const t=await issue();f.data().User[0].role='mechanic';
  await assert.rejects(authenticateAccessToken(t.accessToken),e=>e.status===403);
  assert.equal((await refresh(t.refreshToken)).status,403);assert.ok(f.data().RefreshSession[0].revokedAt);
});
test('expired access has explicit pre-handler rejection code; refresh cannot authorize APIs',async()=>{
  const t=await issue();const claims=jwt.decode(t.accessToken);delete claims.iat;delete claims.exp;
  const expired=jwt.sign(claims,process.env.JWT_SECRET,{expiresIn:-1});
  const r=await request('/auth/session',undefined,expired);assert.equal(r.status,401);assert.equal(r.body.code,'ACCESS_TOKEN_EXPIRED');
  assert.equal((await request('/auth/session',undefined,t.refreshToken)).status,401);
});
test('startup session endpoint validates identity and never exposes private fields',async()=>{
  const t=await issue(ids.mechanicUser);const r=await request('/auth/session',undefined,t.accessToken);
  assert.equal(r.status,200);assert.equal(r.body.user.role,'mechanic');assert.equal(r.body.user.id,ids.mechanicUser);
  for(const secret of ['passwordHash','tokenHash','refreshToken','documents','lockoutUntil']) assert.equal(JSON.stringify(r.body).includes(secret),false);
  assert.equal((await request('/auth/session')).status,401);
});
test('refresh database failure never returns credentials or silently creates replacement sessions',async()=>{
  const t=await issue();const original=f.models.RefreshSession.findOneAndUpdate;
  const stub=mock.method(f.models.RefreshSession,'findOneAndUpdate',()=>{throw new Error('private fixture database fault');});
  try {const r=await refresh(t.refreshToken);assert.equal(r.status,500);assert.equal(r.body.accessToken,undefined);assert.equal(JSON.stringify(r.body).includes('private'),false);}
  finally{stub.mock.restore();}
  assert.equal((await session.rotate(t.refreshToken)).user.id,ids.driver);assert.equal(f.data().RefreshSession.length,1);
});
test('logout disconnects the revoked session socket without touching another device',async()=>{
  const t=await issue(),other=await issue();
  const disconnected=[];
  // Isolate revocation delivery from transport timing; real namespace auth is
  // covered by R02/R04/R07 websocket tests and uses the same session verifier.
  const namespace=io.of('/fixture-session');
  namespace.sockets.set('one',{data:{user:{sid:jwt.decode(t.accessToken).sid}},disconnect:()=>disconnected.push('one')});
  namespace.sockets.set('two',{data:{user:{sid:jwt.decode(other.accessToken).sid}},disconnect:()=>disconnected.push('two')});
  try {await session.revoke(t.refreshToken);assert.deepEqual(disconnected,['one']);}
  finally {namespace.sockets.clear();}
});

test('expired database session cannot refresh or authorize despite a valid JWT',async()=>{
  const t=await issue();f.data().RefreshSession[0].expiresAt=new Date(Date.now()-1);
  assert.equal((await refresh(t.refreshToken)).status,401);
  await assert.rejects(authenticateAccessToken(t.accessToken),e=>e.status===401);
});
test('legacy untracked mobile access must reauthenticate at startup',async()=>{
  const {signAccessToken}=require('../src/services/access.service');
  const r=await request('/auth/session',undefined,signAccessToken(f.data().User[0]));
  assert.equal(r.status,401);assert.equal(f.data().RefreshSession.length,0);
});

test('signed malformed claim types are rejected before database lookup',async()=>{
  const t=await issue();const claims=jwt.decode(t.refreshToken);delete claims.iat;delete claims.exp;
  for(const patch of [{id:[ids.driver]},{sid:[claims.sid]},{jti:[claims.jti]},{tokenUse:'access'}]) {
    const malformed=jwt.sign({...claims,...patch},process.env.JWT_REFRESH_SECRET,{expiresIn:'7d'});
    assert.equal((await refresh(malformed)).status,401);
  }
  assert.equal(f.data().RefreshSession[0].revokedAt,null);
});

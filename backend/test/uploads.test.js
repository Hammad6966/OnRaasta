const { test, before, after, beforeEach, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const sharp = require('sharp');
process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = require('node:crypto').randomBytes(32).toString('hex');
const f = require('./fixtures'); f.install(mock); const { ids } = f;
const media = require('../src/services/media.service');
const { signAccessToken } = require('../src/services/access.service');
const { apiLimiter } = require('../src/middleware/rate-limit.middleware');
const server = http.createServer(require('../src/app'));
let base, png, saved, counter;
mock.method(media, 'store', async (buffer, metadata) => {
  const id = (++counter).toString(16).padStart(24, '0');
  saved.set(id, { _id: id, length: buffer.length, buffer, metadata }); return id;
});
mock.method(media, 'find', async id => saved.get(String(id)));
mock.method(media, 'stream', async (file, res) => { res.set('Content-Type', file.metadata.mime).send(file.buffer); });
before(async () => {
  png = await sharp({ create: { width: 10, height: 10, channels: 3, background: 'blue' } }).png().toBuffer();
  await new Promise(r => server.listen(0, '127.0.0.1', r)); base = `http://127.0.0.1:${server.address().port}/api`;
});
after(async () => { await new Promise(r => server.close(r)); mock.restoreAll(); });
beforeEach(() => { f.reset('fixture'); saved = new Map(); counter = 1000; apiLimiter.resetKey('127.0.0.1'); });
async function req(path, id = ids.unapprovedUser, body, method = 'GET') {
  const token = id ? signAccessToken(f.data().User.find(u => u._id === id)) : null;
  const r = await fetch(base + path, { method, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body instanceof FormData ? {} : { 'Content-Type': 'application/json' }) }, body: body === undefined ? undefined : body instanceof FormData ? body : JSON.stringify(body) });
  return { status: r.status, body: r.headers.get('content-type')?.includes('json') ? await r.json() : await r.arrayBuffer() };
}
async function upload(kind, expectedVersion = 0, id = ids.unapprovedUser, bytes = png, mime = 'image/png') {
  const form = new FormData(); form.set('expectedVersion', String(expectedVersion)); form.set('file', new Blob([bytes], { type: mime }), 'evidence.png');
  return req(`/mechanics/documents/${kind}`, id, form, 'POST');
}
async function submission() {
  for (const [i, kind] of ['cnic_front', 'cnic_back', 'certificate'].entries()) assert.equal((await upload(kind, i)).status, 201);
  return req('/mechanics/documents/submit', ids.unapprovedUser, { expectedVersion: 3, licenseApplicable: false, workshopApplicable: false, permitNumber: '' }, 'POST');
}
const review = (action, expectedVersion = 4, reason = 'Identity and qualification checked') => req(`/admin/verification/${ids.unapproved}/documents/review`, ids.admin, { action, expectedVersion, reason }, 'POST');

test('document uploads require a verified mechanic session and valid image bytes', async () => {
  assert.equal((await upload('cnic_front', 0, null)).status, 401);
  assert.equal((await upload('cnic_front', 0, ids.driver)).status, 403);
  assert.equal((await upload('unknown')).status, 400);
  assert.equal((await upload('cnic_front', 0, ids.unapprovedUser, Buffer.from('<html>fake</html>'))).status, 400);
  assert.equal((await upload('cnic_front', 0, ids.unapprovedUser, Buffer.from([255,216,255,0,0,0]), 'image/jpeg')).status, 400);
  assert.equal(saved.size, 0);
});
test('private evidence is retrievable only by its owner or administrator', async () => {
  const result = await upload('cnic_front'); assert.equal(result.status, 201);
  const file = result.body.data.files[0]; assert.equal(file.mime, 'image/jpeg');
  const path = `/mechanics/documents/files/${file.fileId}`;
  assert.equal((await req(path)).status, 200);
  assert.equal((await req(path, ids.mechanicUser)).status, 404);
  assert.equal((await req(path, ids.driver)).status, 403);
  assert.equal((await req(`/admin/documents/${file.fileId}`, ids.admin)).status, 200);
  assert.equal((await req(path, null)).status, 401);
});
test('required evidence and applicable permit details are enforced', async () => {
  const body = { expectedVersion: 0, licenseApplicable: false, workshopApplicable: false, permitNumber: '' };
  assert.equal((await req('/mechanics/documents/submit', ids.unapprovedUser, body, 'POST')).status, 400);
  assert.equal((await submission()).status, 200);
  assert.equal(f.data().DocumentReview.length, 1);
  assert.equal(f.data().Mechanic[2].isApproved, false);
  assert.equal((await req('/mechanics/documents/submit', ids.unapprovedUser, { ...body, expectedVersion: 4 }, 'POST')).status, 409);
});
test('review requires an administrator, a reason and the exact submitted version', async () => {
  await submission();
  assert.equal((await req(`/admin/verification/${ids.unapproved}/documents/review`, ids.driver, { action: 'verified', expectedVersion: 4, reason: 'Checked' }, 'POST')).status, 403);
  assert.equal((await review('verified', 4, '')).status, 400);
  assert.equal((await review('verified', 3)).status, 409);
  assert.equal((await review('verified')).status, 200);
  assert.equal(f.data().Mechanic[2].isApproved, false);
  assert.equal(f.data().Mechanic[2].documents.status, 'verified');
  assert.equal(f.data().DocumentReview[1].action, 'verified');
  assert.equal((await review('rejected')).status, 409);
});
test('rejected evidence can be replaced and resubmitted without fabricated verification', async () => {
  await submission(); await review('rejected', 4, 'CNIC is unreadable');
  const replacement = await upload('cnic_front', 5); assert.equal(replacement.status, 201);
  assert.equal(replacement.body.data.status, 'draft'); assert.equal(replacement.body.data.files.length, 3);
  assert.equal(f.data().Mechanic[2].documents.status, 'pending');
  assert.equal((await req('/mechanics/documents/submit', ids.unapprovedUser, { expectedVersion: 6, licenseApplicable: false, workshopApplicable: false, permitNumber: '' }, 'POST')).status, 200);
  assert.equal((await review('verified', 7)).status, 200);
  assert.equal(f.data().DocumentReview.length, 4);
});
test('account approval is blocked until uploaded evidence is explicitly reviewed', async () => {
  await submission();
  const path = `/admin/verification/${ids.unapproved}`;
  assert.equal((await req(path, ids.admin, { action: 'approve', expectedVersion: 4, reason: 'Approve account' }, 'PATCH')).status, 409);
  await review('verified');
  assert.equal((await req(path, ids.admin, { action: 'approve', expectedVersion: 5, reason: 'Approve account' }, 'PATCH')).status, 200);
});
test('avatar upload persists on the authenticated account and never accepts PDFs', async () => {
  const form = new FormData(); form.set('file', new Blob([png], { type: 'image/png' }), 'photo.png');
  const r = await req('/users/photo', ids.driver, form, 'POST'); assert.equal(r.status, 200);
  assert.ok(f.data().User[0].photo.fileId); assert.equal(f.data().User[1].photo, undefined);
  assert.equal((await req(`/users/${ids.driver}/photo`, ids.mechanicUser)).status, 200);
  assert.equal((await req(`/users/${ids.driver}/photo`, null)).status, 401);
  assert.equal((await req(`/users/${ids.foreign}/photo`)).status, 404);
  const pdf = new FormData(); pdf.set('file', new Blob(['%PDF-1.7\n%%EOF'], { type: 'application/pdf' }), 'bad.pdf');
  assert.equal((await req('/users/photo', ids.driver, pdf, 'POST')).status, 400);
});
test('oversized multipart files are rejected before persistence', async () => {
  assert.equal((await upload('cnic_front', 0, ids.unapprovedUser, Buffer.alloc(8 * 1024 * 1024 + 1))).status, 413);
  assert.equal(saved.size, 0);
});
test('concurrent document reviewers produce one persisted decision', async () => {
  await submission();
  const results = await Promise.all([review('verified'), review('rejected')]);
  assert.deepEqual(results.map(r => r.status).sort(), [200, 409]);
  assert.equal(f.data().DocumentReview.length, 2);
});
test('failed review audit rolls back evidence verification', async () => {
  await submission();
  const stub = mock.method(f.models.DocumentReview, 'create', async () => { throw Error('write failed'); });
  assert.equal((await review('verified')).status, 500);
  assert.equal(f.data().Mechanic[2].verification.status, 'submitted');
  assert.equal(f.data().DocumentReview.length, 1);
  stub.mock.restore();
});

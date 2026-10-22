import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createAdminClient, expiresAt, AdminApiError } from '../lib/admin-api';
function jwt(role = 'admin', exp = 2000000000) { return 'header.' + btoa(JSON.stringify({ role, exp, tokenUse: 'access' })) + '.signature'; }
function fixture(send: typeof fetch) {
  const values = new Map<string, string>([['admin_token', jwt()]]);
  const store = { getItem: (k: string) => values.get(k) || null, setItem: (k: string, v: string) => { values.set(k, v); }, removeItem: (k: string) => { values.delete(k); } };
  let redirects = 0;
  const client = createAdminClient(store, send, () => redirects++, () => 1900000000000);
  return { client, values, redirects: () => redirects };
}
test('valid admin access token expiry is interpreted without changing server verification', () => {
  assert.equal(expiresAt(jwt()), 2000000000000);
  for (const invalid of ['malformed', jwt('user'), 'header.' + btoa(JSON.stringify({ role: 'admin', tokenUse: 'refresh', exp: 2000000000 })) + '.signature']) assert.equal(expiresAt(invalid), 0);
});
test('protected requests send the current tab token and disable caching', async () => {
  let options: RequestInit | undefined;
  const f = fixture(async (_url, init) => { options = init; return Response.json({ success: true, data: [] }); });
  await f.client.request('/users'); assert.equal((options?.headers as Record<string, string>).Authorization, `Bearer ${jwt()}`); assert.equal(options?.cache, 'no-store');
});
test('private previews use authorization and return binary blobs without public URLs', async () => {
  let options: RequestInit | undefined;
  const f = fixture(async (_url, init) => { options = init; return new Response(new Blob(['%PDF-1.7'], { type: 'application/pdf' })); });
  const blob = await f.client.request<Blob>('/documents/example', {}, true);
  assert.equal(await blob.text(), '%PDF-1.7');
  assert.equal((options?.headers as Record<string, string>).Authorization, `Bearer ${jwt()}`);
  assert.equal(options?.cache, 'no-store');
});
test('expired session clears tab credentials and requires login without making a request', async () => {
  let called = 0; const f = fixture(async () => { called++; return Response.json({}); });
  f.values.set('admin_token', jwt('admin', 1800000000));
  await assert.rejects(f.client.request('/users'), (e: AdminApiError) => e.status === 401);
  assert.equal(called, 0); assert.equal(f.redirects(), 1); assert.equal(f.values.has('admin_token'), false);
});
for (const status of [401, 403]) test(`HTTP ${status} clears admin session and requires reauthentication`, async () => {
  const f = fixture(async () => Response.json({ success: false }, { status }));
  await assert.rejects(f.client.request('/users')); assert.equal(f.values.has('admin_token'), false); assert.equal(f.redirects(), 1);
});
for (const status of [400, 404, 409, 503]) test(`HTTP ${status} remains a recoverable error without false success or logout`, async () => {
  const f = fixture(async () => Response.json({ success: false, message: 'Refresh before retrying' }, { status }));
  await assert.rejects(f.client.request('/verification/id', { method: 'PATCH', body: '{}' }), (e: AdminApiError) => e.status === status && e.message === 'Refresh before retrying');
  assert.equal(f.redirects(), 0); assert.equal(f.values.has('admin_token'), true);
});
test('network failure preserves session and does not automatically repeat mutations', async () => {
  let called = 0; const f = fixture(async () => { called++; throw new Error('Network unavailable'); });
  await assert.rejects(f.client.request('/users/id/status', { method: 'PATCH' })); assert.equal(called, 1); assert.equal(f.values.has('admin_token'), true);
});
test('late response from an old login cannot clear or populate a new session', async () => {
  let resolve!: (value: Response) => void;
  const f = fixture(() => new Promise<Response>(r => { resolve = r; }));
  const pending = f.client.request('/users'); const next = jwt('admin', 2100000000); f.values.set('admin_token', next);
  resolve(Response.json({ success: false }, { status: 401 }));
  await assert.rejects(pending); assert.equal(f.values.get('admin_token'), next); assert.equal(f.redirects(), 0);
});
test('late JSON parsing also rechecks the current tab identity', async () => {
  let parse!: (value: object) => void;
  const f = fixture(async () => ({ ok: true, status: 200, json: () => new Promise<object>(r => { parse = r; }) }) as Response);
  const pending = f.client.request('/users'); await new Promise(r => setTimeout(r, 0));
  f.values.delete('admin_token'); parse({ success: true, data: ['old account'] }); await assert.rejects(pending);
});

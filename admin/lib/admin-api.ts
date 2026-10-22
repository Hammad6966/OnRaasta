export class AdminApiError extends Error {
  constructor(message: string, public status: number) { super(message); }
}
export const ADMIN_API = process.env.NEXT_PUBLIC_ADMIN_API_URL || 'http://localhost:5000/api/admin';
type Store = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;
export function expiresAt(token: string): number {
  try {
    const part = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const value = JSON.parse(atob(part));
    return value.role === 'admin' && value.tokenUse === 'access' && Number.isFinite(value.exp) ? value.exp * 1000 : 0;
  } catch { return 0; }
}
export function createAdminClient(storage: Store, send: typeof fetch, unauthorized: () => void, now = Date.now) {
  const clear = () => storage.removeItem('admin_token');
  const token = () => {
    const value = storage.getItem('admin_token');
    if (!value || expiresAt(value) <= now()) { clear(); return null; }
    return value;
  };
  async function request<T>(path: string, options: RequestInit = {}, binary = false): Promise<T> {
    const expected = token();
    if (!expected) { unauthorized(); throw new AdminApiError('Session expired. Sign in again.', 401); }
    const result = await send(ADMIN_API + path, { ...options, cache: 'no-store', headers: { 'Content-Type': 'application/json', ...options.headers, Authorization: `Bearer ${expected}` } });
    if (storage.getItem('admin_token') !== expected) throw new AdminApiError('Session changed. Reload this page.', 401);
    if (result.status === 401 || result.status === 403) {
      clear(); unauthorized(); throw new AdminApiError('Administrative access expired or unavailable. Sign in again.', result.status);
    }
    const body = binary && result.ok ? await result.blob() : await result.json();
    if (storage.getItem('admin_token') !== expected) throw new AdminApiError('Session changed. Reload this page.', 401);
    if (!result.ok || !binary && !body.success) throw new AdminApiError(body.message || 'Request failed. Please retry.', result.status);
    return body as T;
  }
  return { request, token, clear };
}
export function clearAdminSession() {
  sessionStorage.removeItem('admin_token');
  localStorage.removeItem('admin_token');
}
export function saveAdminSession(token: string) {
  if (expiresAt(token) <= Date.now()) throw new Error('Invalid administrative session');
  clearAdminSession(); sessionStorage.setItem('admin_token', token);
}
export function browserClient() {
  return createAdminClient(sessionStorage, fetch, () => { clearAdminSession(); window.location.replace('/login'); });
}
export function adminRequest<T>(path: string, options?: RequestInit) { return browserClient().request<T>(path, options); }
export function adminBlob(path: string) { return browserClient().request<Blob>(path, {}, true); }

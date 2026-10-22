'use client';
import DocumentReview from './document-review';
import { FormEvent, useCallback, useEffect, useRef, useState } from 'react';
import { adminRequest, AdminApiError } from '../../lib/admin-api';
import type { Account, Mechanic, Listing, AuditLog } from '../../lib/types';
const input = 'bg-[#0D1B2E] border border-[#1E3A5F] rounded-xl px-3 py-2 text-white';
const button = 'rounded-2xl bg-[#2563EB] px-4 py-2 text-white disabled:opacity-50';
const date = (value?: string) => value ? new Date(value).toLocaleString('en-PK') : 'Unavailable';
export default function AccountManagement({ verification = false }: { verification?: boolean }) {
  const [rows, setRows] = useState<(Account | Mechanic)[]>([]);
  const [page, setPage] = useState(1), [total, setTotal] = useState(0);
  const [search, setSearch] = useState(''), [query, setQuery] = useState('');
  const [role, setRole] = useState(''), [active, setActive] = useState(''), [approval, setApproval] = useState('');
  const [counts, setCounts] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true), [error, setError] = useState(''), [notice, setNotice] = useState('');
  const [selected, setSelected] = useState<Account | Mechanic | null>(null);
  const [history, setHistory] = useState<AuditLog[]>([]);
  const [action, setAction] = useState(''), [reason, setReason] = useState(''), [saving, setSaving] = useState(false);
  const mounted = useRef(false);
  const sequence = useRef(0), detailSequence = useRef(0), pending = useRef(false);
  const load = useCallback(async () => {
    const generation = ++sequence.current; setLoading(true); setError('');
    const params = new URLSearchParams({ page: String(page), limit: '20' });
    if (query) params.set('search', query);
    if (role && !verification) params.set('role', role);
    if (active) params.set('active', active);
    if (approval) params.set('approval', approval);
    try {
      const result = await adminRequest<Listing<Account | Mechanic>>(`/${verification ? 'verification' : 'users'}?${params}`);
      if (generation !== sequence.current) return;
      setRows(result.data); setTotal(result.pagination.total); setCounts(result.counts || {});
    } catch (e) { if (generation === sequence.current) { setRows([]); setError(e instanceof Error ? e.message : 'Unable to load accounts'); } }
    finally { if (generation === sequence.current) setLoading(false); }
  }, [page, query, role, active, approval, verification]);
  useEffect(() => { load(); return () => { sequence.current++; }; }, [load]);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; detailSequence.current++; }; }, []);
  async function open(row: Account | Mechanic) {
    const generation = ++detailSequence.current; setError(''); setSelected(null); setAction(''); setReason(''); setHistory([]);
    try {
      const id = verification ? (row as Mechanic).userId : row._id;
      const result = await adminRequest<{ data: Account }>(`/users/${id}`);
      const current = verification ? { ...result.data.mechanic!, user: result.data } : result.data;
      const logs = await adminRequest<Listing<AuditLog>>(`/audit-logs?targetId=${current._id}&limit=10`);
      if (generation !== detailSequence.current) return;
      setSelected(current); setHistory(logs.data);
    } catch (e) { if (generation === detailSequence.current) setError(e instanceof Error ? e.message : 'Unable to load details'); }
  }
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!selected || pending.current || !action || reason.trim().length < 3 || reason.length > 500 || /[<>\x00-\x1f]/.test(reason)) return;
    pending.current = true; setSaving(true); setError(''); setNotice('');
    try {
      await adminRequest(verification ? `/verification/${selected._id}` : `/users/${selected._id}/status`, {
        method: 'PATCH', body: JSON.stringify({ expectedVersion: selected.revision, reason: reason.trim(),
          ...(verification ? { action } : { isActive: action === 'reactivate' }) }),
      });
      if (!mounted.current) return;
      detailSequence.current++; setNotice('Change saved and audit record recorded.'); setSelected(null); setAction(''); setReason(''); await load();
    } catch (e) {
      if (!mounted.current) return;
      setError(e instanceof Error ? e.message : 'Unable to save. Retry.');
      if (e instanceof AdminApiError && [404, 409].includes(e.status)) { setSelected(null); setAction(''); await load(); setError(e.message); }
    } finally { pending.current = false; if (mounted.current) setSaving(false); }
  }
  const mechanic = selected && verification ? selected as Mechanic : selected ? (selected as Account).mechanic : null;
  const account = selected && verification ? (selected as Mechanic).user : selected as Account | null;
  return <div>
    <h1 className="text-2xl font-bold text-white" style={{ fontFamily: 'Syne, sans-serif' }}>{verification ? 'Document Verification & Approval' : 'Users & Mechanics'}</h1>
    {verification && <p className="my-3 text-[#94A3B8]">Review identity and qualification documents, then decide account approval. Each action is recorded separately.</p>}
    {verification && <div className="flex gap-4 my-4 text-[#94A3B8]">{['pending', 'approved', 'rejected', 'revoked'].map(s => <span key={s}>{s}: {counts[s] ?? 'Unavailable'}</span>)}</div>}
    <form className="flex flex-wrap gap-3 my-6" onSubmit={e => { e.preventDefault(); setPage(1); setQuery(search.trim()); }}>
      <input aria-label="Search accounts" className={input} placeholder="Name, email or phone prefix" maxLength={80} value={search} onChange={e => setSearch(e.target.value)} />
      {!verification && <select aria-label="Role" className={input} value={role} onChange={e => { setRole(e.target.value); setPage(1); }}><option value="">All roles</option><option value="user">Drivers</option><option value="mechanic">Mechanics</option></select>}
      <select aria-label="Account status" className={input} value={active} onChange={e => { setActive(e.target.value); setPage(1); }}><option value="">All accounts</option><option value="true">Active</option><option value="false">Suspended</option></select>
      <select aria-label="Approval status" className={input} value={approval} onChange={e => { setApproval(e.target.value); setPage(1); }}><option value="">All approval states</option>{['pending', 'approved', 'rejected', 'revoked'].map(s => <option key={s}>{s}</option>)}</select>
      <button className={button}>Search</button><button type="button" className={button} onClick={load} disabled={loading}>Refresh</button>
    </form>
    {error && <div role="alert" className="my-4 text-red-400">{error}<button className="ml-3 underline" onClick={load}>Retry</button></div>}
    {notice && <p role="status" className="my-4 text-green-400">{notice}</p>}
    <div className="bg-[#0F2040] border border-[#1E3A5F] rounded-2xl p-5 overflow-x-auto">
      {loading ? <p>Loading...</p> : rows.length === 0 ? <p className="text-[#94A3B8]">No matching accounts.</p> : <table className="w-full text-sm text-left"><thead className="text-[#94A3B8]"><tr><th>Name</th><th>Role</th><th>Account</th><th>Approval</th>{verification && <th>Documents</th>}<th>Actions</th></tr></thead><tbody>{rows.map(row => {
        const a = verification ? (row as Mechanic).user! : row as Account;
        const m = verification ? row as Mechanic : a.mechanic;
        return <tr key={row._id} className="border-t border-[#1E3A5F]"><td className="py-4">{a.name}<div className="text-[#94A3B8]">{a.phone}</div></td><td>{a.role === 'user' ? 'Driver' : 'Mechanic'}</td><td>{a.isActive ? 'Active' : 'Suspended'}</td><td>{m?.accountApprovalStatus || 'Not applicable'}</td>{verification && <td><div>{m?.documents.status}</div><div className="text-xs text-[#94A3B8]">{m?.documents.submittedKinds?.length || 0} / 5 sections uploaded</div></td>}<td><button className={button} disabled={saving} onClick={() => open(row)}>View details</button></td></tr>;
      })}</tbody></table>}
    </div>
    <div className="flex items-center gap-4 my-4"><button className={button} disabled={page === 1 || loading} onClick={() => setPage(p => p - 1)}>Previous</button><span>Page {page} | {total} records</span><button className={button} disabled={page * 20 >= total || loading} onClick={() => setPage(p => p + 1)}>Next</button></div>
    {selected && <section className="my-6 bg-[#0F2040] border border-[#1E3A5F] rounded-2xl p-6">
      <button className="float-right underline" disabled={saving} onClick={() => { detailSequence.current++; setSelected(null); }}>Close</button>
      <h2 className="text-xl font-bold mb-4">{account?.name}</h2>
      <p>{account?.phone} | {account?.email || 'No email'}</p><p className="text-[#94A3B8]">Phone verified: {account?.isVerified ? 'Yes' : 'No'} | Created: {date(account?.createdAt)}</p>
      {mechanic && <div className="my-4 space-y-2"><p>Skills: {mechanic.skills.join(', ') || 'None recorded'}</p><p>Radius: {mechanic.serviceRadius} km | Address: {mechanic.shopAddress || 'Unavailable'}</p><p>Application created: {date(mechanic.createdAt)} | Updated: {date(mechanic.updatedAt)}</p><p>Account approval: {mechanic.accountApprovalStatus}</p><p>Document record: {mechanic.documents.status}; {mechanic.documents.evidenceAvailable ? 'existing evidence references recorded' : 'no complete CNIC evidence recorded'}. Document review and account approval are separate decisions.</p>{mechanic.approval?.method && <p>Manual profile decision: {date(mechanic.approval.decidedAt)} | {mechanic.approval.reason}</p>}</div>}
      {mechanic && <DocumentReview mechanicId={mechanic._id} onReviewed={() => { if (selected) open(selected); load(); }} />}
      <form onSubmit={submit} className="my-5 space-y-3">
        <label className="block">Action <select required className={input} value={action} disabled={saving} onChange={e => setAction(e.target.value)}><option value="">Choose action</option>{verification ? mechanic?.isApproved ? <option value="revoke">Revoke manual approval</option> : <><option value="approve" disabled={!account?.isActive || !account.isVerified || !!mechanic?.documents.revision && mechanic.documents.status !== 'verified'}>Approve by manual profile review</option>{mechanic?.accountApprovalStatus === 'pending' && <option value="reject">Reject application</option>}</> : <option value={account?.isActive ? 'suspend' : 'reactivate'}>{account?.isActive ? 'Suspend account' : 'Reactivate account'}</option>}</select></label>
        <textarea aria-label="Audit reason" className={`${input} block w-full`} required minLength={3} maxLength={500} placeholder="Reason for this administrative decision" value={reason} disabled={saving} onChange={e => setReason(e.target.value)} />
        <p className="text-[#94A3B8] text-sm">Confirming applies the selected action to this account and creates a permanent audit record. Historical jobs and reviews remain.</p>
        <button className={button} disabled={saving || !action || reason.trim().length < 3}>{saving ? 'Saving...' : 'Confirm change'}</button>
      </form>
      <h3 className="font-bold">Recent administrative actions</h3>{history.length === 0 ? <p className="text-[#94A3B8]">No recorded actions.</p> : history.map(log => <div key={log._id} className="border-t border-[#1E3A5F] py-3 text-sm"><p>{log.action} | {date(log.createdAt)}</p><p>{log.reason}</p><p className="text-[#94A3B8]">Admin: {log.adminId}</p></div>)}
    </section>}
  </div>;
}

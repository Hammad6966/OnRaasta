'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import { FileText, BadgeCheck, ShieldCheck } from 'lucide-react';
import { adminRequest, adminBlob } from '../../lib/admin-api';

type Evidence = { kind: string; fileId: string; name: string; mime: string; size: number };
type Submission = { status: string; expectedVersion: number; revision: number; permitNumber?: string;
  submittedAt?: string; reason?: string; files: Evidence[]; licenseApplicable?: boolean; workshopApplicable?: boolean;
  history: { _id: string; action: string; actorId: string; revision: number; createdAt: string; reason?: string }[] };
const labels: Record<string, string> = { cnic_front: 'CNIC Front', cnic_back: 'CNIC Back', license: 'Driving License', certificate: 'Mechanic Certificate', workshop: 'Workshop Permit' };

export default function DocumentReview({ mechanicId, onReviewed }: { mechanicId: string; onReviewed: () => void }) {
  const [data, setData] = useState<Submission | null>(null);
  const [error, setError] = useState(''), [loading, setLoading] = useState(true), [saving, setSaving] = useState(false);
  const [reason, setReason] = useState(''), [preview, setPreview] = useState<{ url: string; file: Evidence } | null>(null);
  const generation = useRef(0), previewGeneration = useRef(0), busy = useRef(false);
  const load = useCallback(async () => {
    const seq = ++generation.current; setLoading(true); setError('');
    try {
      const result = await adminRequest<{ data: Submission }>(`/verification/${mechanicId}/documents`);
      if (seq === generation.current) setData(result.data);
    } catch (e) { if (seq === generation.current) setError(e instanceof Error ? e.message : 'Unable to load documents'); }
    finally { if (seq === generation.current) setLoading(false); }
  }, [mechanicId]);
  useEffect(() => { load(); return () => { generation.current++; previewGeneration.current++; }; }, [load]);
  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview.url); }, [preview]);
  async function view(file: Evidence) {
    const seq = ++previewGeneration.current; setError('');
    try {
      const blob = await adminBlob(`/documents/${file.fileId}`);
      if (seq === previewGeneration.current) setPreview({ url: URL.createObjectURL(blob), file });
    } catch (e) { if (seq === previewGeneration.current) setError(e instanceof Error ? e.message : 'Unable to preview document'); }
  }
  async function decide(action: string) {
    if (!data || busy.current || reason.trim().length < 3) return;
    busy.current = true; setSaving(true); setError('');
    const seq = generation.current;
    try {
      await adminRequest(`/verification/${mechanicId}/documents/review`, { method: 'POST',
        body: JSON.stringify({ action, expectedVersion: data.expectedVersion, reason: reason.trim() }) });
      if (seq === generation.current) { setReason(''); await load(); onReviewed(); }
    } catch (e) { if (seq === generation.current) setError(e instanceof Error ? e.message : 'Review could not be saved. Reload before retrying.'); }
    finally { busy.current = false; if (seq <= generation.current) setSaving(false); }
  }
  return <section className="my-6 rounded-2xl border border-[#0F2642] bg-[#0B1929] p-5">
    <h3 className="flex gap-2 items-center font-bold text-lg"><ShieldCheck size={22} />Document Review</h3>
    {loading && <p role="status" className="py-4">Loading evidence…</p>}
    {error && <p role="alert" className="text-red-400 my-3">{error} <button className="underline" onClick={load}>Reload</button></p>}
    {data && <>
      <p className="my-3 text-[#94A3B8]">Documents: <strong className="text-white">{data.status}</strong> · Revision {data.revision} · {data.submittedAt ? new Date(data.submittedAt).toLocaleString() : 'Not submitted'}</p>
      {data.reason && <p className="my-3 text-amber-300">Last review: {data.reason}</p>}
      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-3">{Object.entries(labels).map(([kind, label]) => {
        const file = data.files.find(f => f.kind === kind);
        const required = kind.startsWith('cnic') || kind === 'certificate' || kind === 'license' && data.licenseApplicable || kind === 'workshop' && data.workshopApplicable;
        return <div key={kind} className="rounded-xl border border-[#0F2642] bg-[#080F1E] p-4">
          <FileText className="text-blue-400 mb-3" size={24}/><h4 className="font-semibold">{label}</h4>
          <p className={`text-xs my-2 ${file ? 'text-green-400' : required ? 'text-amber-400' : 'text-slate-400'}`}>{file ? 'Submitted' : required ? 'Missing · Required' : 'Not applicable'}</p>
          {file && <button className="text-blue-400 text-sm underline" onClick={() => view(file)}>Preview document</button>}
        </div>;
      })}</div>
      {data.workshopApplicable && <p className="my-3">Workshop permit: {data.permitNumber || 'Missing'}</p>}
      {preview && <div className="my-5 border border-[#0F2642] rounded-xl p-3">
        <div className="flex justify-between gap-4 mb-3"><h4>{labels[preview.file.kind]} · {preview.file.name}</h4><button className="underline" onClick={() => { previewGeneration.current++; setPreview(null); }}>Close preview</button></div>
        {preview.file.mime === 'application/pdf' ? <iframe title="Private document preview" sandbox="" src={preview.url} className="w-full h-[480px] bg-white" />
          // eslint-disable-next-line @next/next/no-img-element
          : <img alt={labels[preview.file.kind]} src={preview.url} className="max-h-[480px] object-contain mx-auto" />}
      </div>}
      {data.status === 'submitted' && <div className="mt-5 space-y-3">
        <label className="block text-sm">Review reason (required for either decision)<textarea className="block w-full mt-2 rounded-xl border border-[#0F2642] bg-[#080F1E] p-3" value={reason} onChange={e => setReason(e.target.value)} minLength={3} maxLength={500} disabled={saving}/></label>
        <div className="flex flex-wrap gap-3"><button disabled={saving || reason.trim().length < 3} onClick={() => decide('verified')} className="flex gap-2 items-center rounded-xl bg-green-700 px-4 py-3 disabled:opacity-50"><BadgeCheck size={18}/>Verify Documents</button><button disabled={saving || reason.trim().length < 3} onClick={() => decide('rejected')} className="rounded-xl border border-red-500 text-red-400 px-4 py-3 disabled:opacity-50">Reject Documents</button></div>
        <p className="text-xs text-[#94A3B8]">Verifying evidence records this review. Use the separate account approval action below to authorize work.</p>
      </div>}
      <h4 className="mt-6 mb-2 font-semibold">Submission & Review History</h4>
      {data.history.length ? data.history.map(h => <div key={h._id} className="border-t border-[#0F2642] py-3 text-sm"><p>{h.action} · Revision {h.revision} · {new Date(h.createdAt).toLocaleString()}</p><p className="text-[#94A3B8]">{h.reason || 'Submitted for review'} · Actor {h.actorId}</p></div>) : <p className="text-[#94A3B8]">No submission recorded.</p>}
    </>}
  </section>;
}

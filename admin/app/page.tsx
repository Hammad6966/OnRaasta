'use client';

import { useEffect, useState, useCallback } from 'react';
import {
  Users,
  Wrench,
  Car,
  Shield,
  TrendingUp,
  Clock,
} from 'lucide-react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  Legend,
} from 'recharts';

const API = 'http://localhost:5000/api/admin';

function getToken() {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem('admin_token');
}

function authHeaders(): HeadersInit {
  return { Authorization: `Bearer ${getToken()}` };
}

// ── Types ─────────────────────────────────────────────────────────────────────

interface Stats {
  totalUsers: number;
  totalMechanics: number;
  activeJobs: number;
  pendingVerifications: number;
  totalRevenue: number;
  newUsersToday: number;
}

interface ChartPoint { day: string; jobs: number }
interface FaultPoint  { name: string; value: number }

interface RecentJob {
  jobId: string;
  user: string;
  status: string;
  fault: string;
  amount: number | null;
  createdAt: string;
}

// ── KPI Card ──────────────────────────────────────────────────────────────────

function KpiCard({
  label, value, trend, icon, iconColor,
}: {
  label: string;
  value: string | number;
  trend?: string;
  icon: React.ReactNode;
  iconColor: string;
}) {
  return (
    <div className="bg-[#0F2040] rounded-2xl p-6 border border-[#1E3A5F] relative overflow-hidden">
      <div
        className="absolute top-4 right-4 p-2 rounded-xl"
        style={{ backgroundColor: `${iconColor}20` }}
      >
        <span style={{ color: iconColor }}>{icon}</span>
      </div>
      <p className="text-[#94A3B8] text-sm mb-2">{label}</p>
      <p className="text-3xl font-bold text-white" style={{ fontFamily: 'Syne, sans-serif' }}>
        {value}
      </p>
      {trend && (
        <p className="text-[#22C55E] text-xs mt-2 flex items-center gap-1">
          <TrendingUp size={12} /> {trend}
        </p>
      )}
    </div>
  );
}

// ── Status badge ──────────────────────────────────────────────────────────────

const STATUS_STYLES: Record<string, string> = {
  pending:     'bg-yellow-500/10 text-yellow-400 border-yellow-500/30',
  bidding:     'bg-blue-500/10   text-blue-400   border-blue-500/30',
  accepted:    'bg-green-500/10  text-green-400  border-green-500/30',
  en_route:    'bg-blue-500/10   text-blue-400   border-blue-500/30',
  arrived:     'bg-orange-500/10 text-orange-400 border-orange-500/30',
  in_progress: 'bg-orange-500/10 text-orange-400 border-orange-500/30',
  completed:   'bg-green-500/10  text-green-400  border-green-500/30',
  cancelled:   'bg-red-500/10    text-red-400    border-red-500/30',
};

function StatusBadge({ status }: { status: string }) {
  const cls = STATUS_STYLES[status] ?? 'bg-gray-500/10 text-gray-400 border-gray-500/30';
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium border capitalize ${cls}`}>
      {status.replace(/_/g, ' ')}
    </span>
  );
}

// ── Donut colours ─────────────────────────────────────────────────────────────

const FAULT_COLORS = ['#2563EB', '#F97316', '#22C55E', '#EF4444', '#F59E0B', '#94A3B8'];

// ── Main ──────────────────────────────────────────────────────────────────────

export default function DashboardPage() {
  const [stats,      setStats]      = useState<Stats | null>(null);
  const [jobsChart,  setJobsChart]  = useState<ChartPoint[]>([]);
  const [faults,     setFaults]     = useState<FaultPoint[]>([]);
  const [recentJobs, setRecentJobs] = useState<RecentJob[]>([]);
  const [loading,    setLoading]    = useState(true);

  const fetchAll = useCallback(async () => {
    try {
      const headers = authHeaders();
      const [sRes, jRes, fRes, rRes] = await Promise.all([
        fetch(`${API}/stats`,        { headers }),
        fetch(`${API}/jobs-chart`,   { headers }),
        fetch(`${API}/faults-chart`, { headers }),
        fetch(`${API}/recent-jobs`,  { headers }),
      ]);
      const [s, j, f, r] = await Promise.all([
        sRes.json(), jRes.json(), fRes.json(), rRes.json(),
      ]);
      if (s.success) setStats(s.data);
      if (j.success) setJobsChart(j.data);
      if (f.success) setFaults(f.data);
      if (r.success) setRecentJobs(r.data);
    } catch (err) {
      console.error('Dashboard fetch:', err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchAll();
    const id = setInterval(fetchAll, 60_000);
    return () => clearInterval(id);
  }, [fetchAll]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="w-8 h-8 border-2 border-[#2563EB] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div>
      {/* Header */}
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-white" style={{ fontFamily: 'Syne, sans-serif' }}>
          Dashboard
        </h1>
        <p className="text-[#94A3B8] text-sm mt-1">
          Real-time overview · auto-refreshes every 60s
        </p>
      </div>

      {/* KPI grid */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <KpiCard
          label="Total Users"
          value={stats?.totalUsers ?? '—'}
          trend={stats ? `+${stats.newUsersToday} today` : undefined}
          icon={<Users size={24} />}
          iconColor="#2563EB"
        />
        <KpiCard
          label="Active Mechanics"
          value={stats?.totalMechanics ?? '—'}
          icon={<Wrench size={24} />}
          iconColor="#F97316"
        />
        <KpiCard
          label="Active Jobs"
          value={stats?.activeJobs ?? '—'}
          icon={<Car size={24} />}
          iconColor="#22C55E"
        />
        <KpiCard
          label="Pending Verifications"
          value={stats?.pendingVerifications ?? '—'}
          icon={<Shield size={24} />}
          iconColor="#F59E0B"
        />
      </div>

      {/* Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
        {/* Line chart */}
        <div className="bg-[#0F2040] rounded-2xl p-6 border border-[#1E3A5F]">
          <h2
            className="text-white font-semibold mb-6"
            style={{ fontFamily: 'Syne, sans-serif' }}
          >
            Jobs This Week
          </h2>
          {jobsChart.length > 0 ? (
            <ResponsiveContainer width="100%" height={220}>
              <LineChart data={jobsChart}>
                <XAxis
                  dataKey="day"
                  stroke="#94A3B8"
                  tick={{ fill: '#94A3B8', fontSize: 12 }}
                  axisLine={false}
                  tickLine={false}
                />
                <YAxis
                  stroke="#94A3B8"
                  tick={{ fill: '#94A3B8', fontSize: 12 }}
                  axisLine={false}
                  tickLine={false}
                  allowDecimals={false}
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: '#0D1B2E',
                    border: '1px solid #1E3A5F',
                    borderRadius: 8,
                    color: '#fff',
                    fontSize: 13,
                  }}
                  cursor={{ stroke: '#1E3A5F' }}
                />
                <Line
                  type="monotone"
                  dataKey="jobs"
                  stroke="#2563EB"
                  strokeWidth={2}
                  dot={{ fill: '#2563EB', r: 4 }}
                  activeDot={{ r: 6, fill: '#2563EB' }}
                />
              </LineChart>
            </ResponsiveContainer>
          ) : (
            <div className="flex items-center justify-center h-[220px] text-[#94A3B8] text-sm">
              No data yet
            </div>
          )}
        </div>

        {/* Donut chart */}
        <div className="bg-[#0F2040] rounded-2xl p-6 border border-[#1E3A5F]">
          <h2
            className="text-white font-semibold mb-4"
            style={{ fontFamily: 'Syne, sans-serif' }}
          >
            Common Faults
          </h2>
          {faults.length > 0 ? (
            <ResponsiveContainer width="100%" height={240}>
              <PieChart>
                <Pie
                  data={faults}
                  cx="50%"
                  cy="45%"
                  innerRadius={60}
                  outerRadius={100}
                  paddingAngle={3}
                  dataKey="value"
                >
                  {faults.map((_, i) => (
                    <Cell key={i} fill={FAULT_COLORS[i % FAULT_COLORS.length]} />
                  ))}
                </Pie>
                <Legend
                  iconType="circle"
                  iconSize={8}
                  formatter={(v) => (
                    <span style={{ color: '#94A3B8', fontSize: 12 }} className="capitalize">
                      {v}
                    </span>
                  )}
                />
                <Tooltip
                  contentStyle={{
                    backgroundColor: '#0D1B2E',
                    border: '1px solid #1E3A5F',
                    borderRadius: 8,
                    color: '#fff',
                    fontSize: 13,
                  }}
                />
              </PieChart>
            </ResponsiveContainer>
          ) : (
            <div className="flex items-center justify-center h-[240px] text-[#94A3B8] text-sm">
              No fault data yet
            </div>
          )}
        </div>
      </div>

      {/* Recent jobs table */}
      <div className="bg-[#0F2040] rounded-2xl p-6 border border-[#1E3A5F]">
        <h2
          className="text-white font-semibold mb-5"
          style={{ fontFamily: 'Syne, sans-serif' }}
        >
          Recent Jobs
        </h2>

        {recentJobs.length === 0 ? (
          <p className="text-[#94A3B8] text-sm text-center py-8">No jobs yet</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr>
                  {['Job ID', 'User', 'Status', 'Fault', 'Amount', 'Time'].map((h) => (
                    <th
                      key={h}
                      className="text-left text-xs text-[#94A3B8] uppercase tracking-wider pb-3 pr-6 font-medium whitespace-nowrap"
                    >
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {recentJobs.map((job, i) => (
                  <tr
                    key={i}
                    className="border-t border-[#1E3A5F] hover:bg-[#0D1B2E] transition-colors"
                  >
                    <td className="py-3 pr-6 text-[#94A3B8] font-mono text-xs">
                      #{job.jobId}
                    </td>
                    <td className="py-3 pr-6 text-white">{job.user}</td>
                    <td className="py-3 pr-6">
                      <StatusBadge status={job.status} />
                    </td>
                    <td className="py-3 pr-6 text-[#94A3B8] capitalize">{job.fault}</td>
                    <td className="py-3 pr-6 text-white">
                      {job.amount != null ? `PKR ${job.amount.toLocaleString()}` : '—'}
                    </td>
                    <td className="py-3 text-[#94A3B8] whitespace-nowrap flex items-center gap-1 pt-4">
                      <Clock size={12} />
                      {new Date(job.createdAt).toLocaleDateString('en-PK', {
                        month: 'short',
                        day: 'numeric',
                        hour: '2-digit',
                        minute: '2-digit',
                      })}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}

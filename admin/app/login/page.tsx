'use client';

import { useState, FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { Eye, EyeOff, Loader2 } from 'lucide-react';

const API = 'http://localhost:5000/api/admin';

export default function LoginPage() {
  const router = useRouter();

  const [email,    setEmail]    = useState('');
  const [password, setPassword] = useState('');
  const [showPw,   setShowPw]   = useState(false);
  const [loading,  setLoading]  = useState(false);
  const [error,    setError]    = useState('');

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const res  = await fetch(`${API}/login`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ email, password }),
      });
      const data = await res.json();

      if (!res.ok || !data.success) {
        setError(data.message || 'Invalid credentials');
        return;
      }

      localStorage.setItem('admin_token', data.token);
      router.push('/');
    } catch {
      setError('Server unreachable. Check that the backend is running.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen bg-[#050A14] flex items-center justify-center p-4">
      <div className="w-full max-w-md bg-[#0F2040] rounded-2xl p-8 border border-[#1E3A5F]">
        {/* Logo */}
        <div className="text-center mb-8">
          <h1 className="text-3xl font-bold" style={{ fontFamily: 'Syne, sans-serif' }}>
            <span className="text-white">On</span>
            <span className="text-[#F97316]">Raasta</span>
          </h1>
          <p className="text-[#94A3B8] text-sm mt-2">Admin Portal</p>
        </div>

        {/* Error */}
        {error && (
          <div className="mb-5 px-4 py-3 rounded-xl bg-red-500/10 border border-red-500/30 text-red-400 text-sm">
            {error}
          </div>
        )}

        {/* Form */}
        <form onSubmit={handleSubmit} className="space-y-5">
          {/* Email */}
          <div>
            <label className="block text-xs text-[#94A3B8] uppercase tracking-wider mb-2 font-medium">
              Email
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="admin@onraasta.com"
              required
              autoComplete="email"
              className="w-full bg-[#0D1B2E] border border-[#1E3A5F] rounded-xl p-3 text-white placeholder-[#94A3B8] text-sm outline-none focus:border-[#2563EB] transition-colors"
            />
          </div>

          {/* Password */}
          <div>
            <label className="block text-xs text-[#94A3B8] uppercase tracking-wider mb-2 font-medium">
              Password
            </label>
            <div className="relative">
              <input
                type={showPw ? 'text' : 'password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="••••••••"
                required
                autoComplete="current-password"
                className="w-full bg-[#0D1B2E] border border-[#1E3A5F] rounded-xl p-3 pr-11 text-white placeholder-[#94A3B8] text-sm outline-none focus:border-[#2563EB] transition-colors"
              />
              <button
                type="button"
                onClick={() => setShowPw((v) => !v)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-[#94A3B8] hover:text-white transition-colors"
                tabIndex={-1}
              >
                {showPw ? <EyeOff size={16} /> : <Eye size={16} />}
              </button>
            </div>
          </div>

          {/* Submit */}
          <button
            type="submit"
            disabled={loading}
            className="w-full bg-[#2563EB] hover:bg-[#1D4ED8] disabled:opacity-60 text-white rounded-2xl py-3 font-medium text-sm transition-colors flex items-center justify-center gap-2 mt-2"
          >
            {loading ? (
              <>
                <Loader2 size={16} className="animate-spin" />
                Signing in…
              </>
            ) : (
              'Sign In'
            )}
          </button>
        </form>

        <p className="text-[#94A3B8] text-xs text-center mt-6">
          Default: admin@onraasta.com / admin123
        </p>
      </div>
    </div>
  );
}

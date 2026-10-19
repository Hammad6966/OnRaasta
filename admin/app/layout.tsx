'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { browserClient, clearAdminSession } from '../lib/admin-api';
import { usePathname } from 'next/navigation';
import {
  LayoutDashboard,
  Users,
  Shield,
  BarChart2,
  AlertCircle,
} from 'lucide-react';
import './globals.css';

const NAV = [
  { label: 'Dashboard',    href: '/',            icon: LayoutDashboard },
  { label: 'Users',        href: '/users',       icon: Users           },
  { label: 'Verification', href: '/verification',icon: Shield          },
  { label: 'Analytics',    href: '/analytics',   icon: BarChart2       },
  { label: 'Disputes',     href: '/disputes',    icon: AlertCircle     },
];

const NO_SIDEBAR = ['/login'];

function Sidebar() {
  const pathname = usePathname();

  return (
    <aside
      style={{ width: 240 }}
      className="fixed top-0 left-0 h-screen flex flex-col bg-[#0F2040] border-r border-[#1E3A5F] z-50"
    >
      {/* Logo */}
      <div className="px-6 py-6 border-b border-[#1E3A5F]">
        <span className="text-2xl font-bold" style={{ fontFamily: 'Syne, sans-serif' }}>
          <span className="text-white">On</span>
          <span className="text-[#F97316]">Raasta</span>
        </span>
        <p className="text-[#94A3B8] text-xs mt-1">Admin Dashboard</p>
      </div>

      {/* Nav */}
      <nav className="flex-1 px-4 py-6 space-y-1 overflow-y-auto">
        {NAV.map(({ label, href, icon: Icon }) => {
          const active =
            href === '/' ? pathname === '/' : pathname.startsWith(href);
          return (
            <Link
              key={href}
              href={href}
              className={`flex items-center gap-3 px-4 py-3 rounded-lg text-sm font-medium transition-colors ${
                active
                  ? 'bg-[#2563EB] text-white'
                  : 'text-[#94A3B8] hover:text-white hover:bg-[#0D1B2E]'
              }`}
            >
              <Icon size={18} />
              {label}
            </Link>
          );
        })}
      </nav>

      {/* Footer */}
      <div className="px-6 py-4 border-t border-[#1E3A5F]">
        <button className="text-sm mb-3" onClick={() => { clearAdminSession(); window.location.replace('/login'); }}>Sign out</button>
        <p className="text-[#94A3B8] text-xs">© 2025 OnRaasta</p>
      </div>
    </aside>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const hideSidebar = NO_SIDEBAR.includes(pathname);
  const [ready, setReady] = useState(false);
  useEffect(() => {
    if (hideSidebar) { setReady(false); return; }
    const client = browserClient();
    let timer: ReturnType<typeof setTimeout>;
    const check = () => {
      clearTimeout(timer);
      const token = client.token();
      if (!token) { clearAdminSession(); window.location.replace('/login'); return; }
      setReady(true);
      const expiry = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).exp * 1000;
      timer = setTimeout(check, Math.max(1, expiry - Date.now()));
    };
    check(); window.addEventListener('focus', check);
    return () => { clearTimeout(timer); window.removeEventListener('focus', check); };
  }, [pathname, hideSidebar]);

  if (hideSidebar) {
    return <>{children}</>;
  }

  if (!ready) return <p className="p-8">Checking administrative session...</p>;
  return (
    <>
      <Sidebar />
      <main style={{ marginLeft: 240 }} className="min-h-screen bg-[#050A14] p-8">
        {children}
      </main>
    </>
  );
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Shell>{children}</Shell>
      </body>
    </html>
  );
}

'use client';

import Link from 'next/link';
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
        <p className="text-[#94A3B8] text-xs">© 2025 OnRaasta</p>
      </div>
    </aside>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const hideSidebar = NO_SIDEBAR.includes(pathname);

  if (hideSidebar) {
    return <>{children}</>;
  }

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

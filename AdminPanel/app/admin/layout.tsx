import Link from "next/link";
import { prisma } from "@/lib/db";
import { requireAdminOrRedirect } from "@/lib/session";
import LogoutButton from "./logout-button";

const activeNav = [
  { href: "/admin", label: "Dashboard" },
  { href: "/admin/products", label: "Mağaza" },
];

const passiveNav = ["Skinler", "Temalar", "Seviyeler", "Telemetri"];

export default async function AdminLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  await requireAdminOrRedirect();

  const state = await prisma.catalogState.findUnique({ where: { id: 1 } });
  const version = state?.version ?? 0;

  return (
    <div className="flex min-h-screen bg-zinc-950 text-zinc-100">
      <aside className="flex w-56 shrink-0 flex-col border-r border-zinc-800 bg-zinc-900">
        <div className="border-b border-zinc-800 px-5 py-4">
          <span className="text-lg font-bold tracking-wide text-amber-500">
            Komuta Paneli
          </span>
        </div>
        <nav className="flex-1 space-y-1 px-3 py-4">
          {activeNav.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className="block rounded-md px-3 py-2 text-sm font-medium text-zinc-300 transition hover:bg-zinc-800 hover:text-amber-500"
            >
              {item.label}
            </Link>
          ))}
          <div className="pt-4">
            <p className="px-3 pb-1 text-xs font-semibold uppercase tracking-wider text-zinc-600">
              Yakında
            </p>
            {passiveNav.map((label) => (
              <span
                key={label}
                className="flex items-center justify-between rounded-md px-3 py-2 text-sm text-zinc-600"
              >
                {label}
                <span className="rounded bg-zinc-800 px-1.5 py-0.5 text-[10px] font-semibold text-zinc-500">
                  Faz 2+
                </span>
              </span>
            ))}
          </div>
        </nav>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between border-b border-zinc-800 bg-zinc-900 px-6 py-3">
          <span className="rounded-full border border-amber-500/40 bg-amber-500/10 px-3 py-1 text-xs font-semibold text-amber-500">
            Katalog v{version}
          </span>
          <LogoutButton />
        </header>
        <main className="flex-1 p-6">{children}</main>
      </div>
    </div>
  );
}

import { prisma } from "@/lib/db";
import { formatDateTR } from "@/lib/format";

/** Dashboard — katalog sürümü, ürün sayıları, son yayın zamanı. */
export default async function AdminDashboardPage() {
  const [state, groups] = await Promise.all([
    prisma.catalogState.findUnique({ where: { id: 1 } }),
    prisma.product.groupBy({ by: ["status"], _count: { _all: true } }),
  ]);

  const counts: Record<string, number> = { published: 0, draft: 0, archived: 0 };
  for (const group of groups) {
    counts[group.status] = group._count._all;
  }

  const version = state?.version ?? 0;
  const lastPublish =
    state && state.version > 0 ? formatDateTR(state.publishedAt) : "Henüz yayın yok";

  const statCards = [
    { label: "Katalog Sürümü", value: `v${version}`, accent: "text-amber-500" },
    { label: "Yayında", value: String(counts.published), accent: "text-emerald-400" },
    { label: "Taslak", value: String(counts.draft), accent: "text-zinc-300" },
    { label: "Arşiv", value: String(counts.archived), accent: "text-red-400" },
  ];

  return (
    <div>
      <h1 className="text-2xl font-bold text-zinc-100">Dashboard</h1>
      <p className="mt-1 text-sm text-zinc-400">Komuta Paneli genel durum görünümü.</p>

      <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {statCards.map((card) => (
          <div
            key={card.label}
            className="rounded-xl border border-zinc-800 bg-zinc-900 p-5"
          >
            <p className="text-xs font-semibold uppercase tracking-wider text-zinc-500">
              {card.label}
            </p>
            <p className={`mt-2 text-3xl font-bold ${card.accent}`}>{card.value}</p>
          </div>
        ))}
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-zinc-800 bg-zinc-900 p-5">
          <p className="text-xs font-semibold uppercase tracking-wider text-zinc-500">
            Son Yayın
          </p>
          <p className="mt-2 text-lg font-semibold text-zinc-100">{lastPublish}</p>
          <p className="mt-1 text-sm text-zinc-500">
            Yayınlama, Mağaza sayfasındaki &quot;Yayınla&quot; düğmesiyle yapılır.
          </p>
        </div>
        <div className="rounded-xl border border-dashed border-zinc-800 bg-zinc-900/50 p-5">
          <div className="flex items-center justify-between">
            <p className="text-xs font-semibold uppercase tracking-wider text-zinc-600">
              Telemetri
            </p>
            <span className="rounded bg-zinc-800 px-1.5 py-0.5 text-[10px] font-semibold text-zinc-500">
              Faz 4
            </span>
          </div>
          <p className="mt-2 text-sm text-zinc-500">
            Oyuncu metrikleri, satın alma hunisi ve dalga istatistikleri burada
            görünecek.
          </p>
        </div>
      </div>
    </div>
  );
}

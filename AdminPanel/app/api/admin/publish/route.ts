import { prisma } from "@/lib/db";
import { requireAdmin } from "@/lib/session";

/** POST /api/admin/publish — katalog sürümünü artırır (CatalogState upsert). */
export async function POST() {
  const denied = await requireAdmin();
  if (denied) return denied;

  const state = await prisma.catalogState.upsert({
    where: { id: 1 },
    update: { version: { increment: 1 } },
    create: { id: 1, version: 1 },
  });

  return Response.json({ version: state.version });
}

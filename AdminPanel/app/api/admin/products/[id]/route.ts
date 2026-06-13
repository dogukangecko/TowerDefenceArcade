import { prisma } from "@/lib/db";
import { requireAdmin } from "@/lib/session";
import { ProductInput, ProductPatch } from "@/lib/validation";

type Context = { params: Promise<{ id: string }> };

/** PATCH /api/admin/products/[id] — kısmi güncelleme. */
export async function PATCH(request: Request, ctx: Context) {
  const denied = await requireAdmin();
  if (denied) return denied;

  const { id } = await ctx.params;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Geçersiz JSON gövdesi" }, { status: 400 });
  }

  const parsed = ProductPatch.safeParse(body);
  if (!parsed.success) {
    return Response.json(
      { error: "Doğrulama hatası", issues: parsed.error.issues },
      { status: 400 },
    );
  }

  const existing = await prisma.product.findUnique({ where: { id } });
  if (!existing) {
    return Response.json({ error: "Ürün bulunamadı" }, { status: 404 });
  }

  // Tür-bağımlı kurallar (kind ↔ effect/assetKey) birleşik nesne üzerinde
  // doğrulanır: mevcut satır + patch → tam ProductInput şeması.
  const merged = ProductInput.safeParse({
    name: existing.name,
    desc: existing.desc,
    icon: existing.icon,
    priceGold: existing.priceGold,
    effectType: existing.effectType,
    effectValue: existing.effectValue,
    premium: existing.premium,
    status: existing.status,
    kind: existing.kind,
    assetKey: existing.assetKey,
    ...parsed.data,
  });
  if (!merged.success) {
    return Response.json(
      { error: "Doğrulama hatası", issues: merged.error.issues },
      { status: 400 },
    );
  }

  const product = await prisma.product.update({
    where: { id },
    data: merged.data,
  });
  return Response.json(product);
}

/** DELETE /api/admin/products/[id] — gerçek silme yok: status=archived. */
export async function DELETE(_request: Request, ctx: Context) {
  const denied = await requireAdmin();
  if (denied) return denied;

  const { id } = await ctx.params;

  const existing = await prisma.product.findUnique({ where: { id } });
  if (!existing) {
    return Response.json({ error: "Ürün bulunamadı" }, { status: 404 });
  }

  const product = await prisma.product.update({
    where: { id },
    data: { status: "archived" },
  });
  return Response.json(product);
}

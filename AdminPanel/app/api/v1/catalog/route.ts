import { prisma } from "@/lib/db";

/**
 * GET /api/v1/catalog — KAMUYA AÇIK oyun kataloğu.
 * Yalnız published ürünler; ETag "v<version>" + If-None-Match → 304.
 * proxy.ts matcher'ı /api/v1'i KAPSAMAZ (yalnız /admin ve /api/admin).
 */
export async function GET(request: Request) {
  const state = await prisma.catalogState.findUnique({ where: { id: 1 } });
  const version = state?.version ?? 0;
  const etag = `"v${version}"`;
  const headers = { ETag: etag, "Cache-Control": "no-cache" };

  if (request.headers.get("if-none-match") === etag) {
    return new Response(null, { status: 304, headers });
  }

  const products = await prisma.product.findMany({
    where: { status: "published" },
    orderBy: { createdAt: "asc" },
  });

  const items = products.map((p) => ({
    id: p.id,
    name: p.name,
    desc: p.desc,
    icon: p.icon,
    priceGold: p.priceGold,
    // effect HER ZAMAN mevcut (oyun non-optional decode eder);
    // skin/tema için nötr {none, 0}.
    effect:
      p.kind === "item"
        ? { type: p.effectType, value: p.effectValue }
        : { type: "none", value: 0 },
    premium: p.premium,
    kind: p.kind,
    assetKey: p.kind === "item" ? null : p.assetKey,
  }));

  return Response.json({ version, items }, { headers });
}

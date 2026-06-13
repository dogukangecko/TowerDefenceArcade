import { prisma } from "@/lib/db";
import ProductsClient from "./products-client";
import type { ProductDTO } from "./types";

/** Mağaza yönetimi — server component: ürünleri doğrudan DB'den okur. */
export default async function ProductsPage() {
  const products = await prisma.product.findMany({
    orderBy: { createdAt: "desc" },
  });

  const dto: ProductDTO[] = products.map((p) => ({
    id: p.id,
    name: p.name,
    desc: p.desc,
    icon: p.icon,
    priceGold: p.priceGold,
    effectType: p.effectType,
    effectValue: p.effectValue,
    premium: p.premium,
    status: p.status,
    kind: p.kind,
    assetKey: p.assetKey,
  }));

  return <ProductsClient products={dto} />;
}

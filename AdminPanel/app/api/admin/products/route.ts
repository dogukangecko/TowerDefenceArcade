import { prisma } from "@/lib/db";
import { requireAdmin } from "@/lib/session";
import { PRODUCT_STATUSES, ProductInput } from "@/lib/validation";

/** GET /api/admin/products — liste; isteğe bağlı ?status= filtresi, en yeni önce. */
export async function GET(request: Request) {
  const denied = await requireAdmin();
  if (denied) return denied;

  const status = new URL(request.url).searchParams.get("status");
  if (status && !(PRODUCT_STATUSES as readonly string[]).includes(status)) {
    return Response.json({ error: "Geçersiz status filtresi" }, { status: 400 });
  }

  const products = await prisma.product.findMany({
    where: status ? { status } : undefined,
    orderBy: { createdAt: "desc" },
  });
  return Response.json(products);
}

/** POST /api/admin/products — yeni ürün oluştur. */
export async function POST(request: Request) {
  const denied = await requireAdmin();
  if (denied) return denied;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Geçersiz JSON gövdesi" }, { status: 400 });
  }

  const parsed = ProductInput.safeParse(body);
  if (!parsed.success) {
    return Response.json(
      { error: "Doğrulama hatası", issues: parsed.error.issues },
      { status: 400 },
    );
  }

  const product = await prisma.product.create({ data: parsed.data });
  return Response.json(product, { status: 201 });
}

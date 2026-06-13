import { createHash, timingSafeEqual } from "node:crypto";
import { getSession } from "@/lib/session";

/**
 * Sabit-zaman karşılaştırma: timingSafeEqual eşit olmayan uzunlukta throw
 * ettiği için iki taraf da önce sha256 ile eşit uzunluğa indirgenir.
 */
function passwordsMatch(candidate: string, expected: string): boolean {
  const a = createHash("sha256").update(candidate, "utf8").digest();
  const b = createHash("sha256").update(expected, "utf8").digest();
  return timingSafeEqual(a, b);
}

export async function POST(request: Request) {
  const expected = process.env.ADMIN_PASSWORD;
  if (!expected) {
    return Response.json({ error: "Sunucu yapılandırması eksik" }, { status: 500 });
  }

  let candidate = "";
  try {
    const body = (await request.json()) as { password?: unknown };
    if (typeof body.password === "string") {
      candidate = body.password;
    }
  } catch {
    // gövde yok/bozuk — boş şifre gibi davran, aşağıda 401
  }

  if (!candidate || !passwordsMatch(candidate, expected)) {
    return Response.json({ error: "Hatalı şifre" }, { status: 401 });
  }

  const session = await getSession();
  session.admin = true;
  await session.save();
  return Response.json({ ok: true });
}

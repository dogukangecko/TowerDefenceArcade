import { getIronSession } from "iron-session";
import { NextResponse, type NextRequest } from "next/server";
import { sessionOptions, type SessionData } from "@/lib/session-options";

/**
 * Next 16: middleware.ts yerine proxy.ts (Node.js runtime'da çalışır).
 * Oturumsuz istekler /admin/* için /login'e yönlendirilir,
 * /api/admin/* için 401 JSON döner. Route handler'lardaki requireAdmin()
 * ve admin layout'taki kontrol derinlemesine savunma sağlar.
 */
export async function proxy(request: NextRequest) {
  const response = NextResponse.next();
  const session = await getIronSession<SessionData>(
    request,
    response,
    sessionOptions,
  );

  if (!session.admin) {
    if (request.nextUrl.pathname.startsWith("/api/admin")) {
      return NextResponse.json({ error: "Yetkisiz" }, { status: 401 });
    }
    return NextResponse.redirect(new URL("/login", request.url));
  }

  return response;
}

export const config = {
  matcher: ["/admin/:path*", "/api/admin/:path*"],
};

import { getIronSession, type IronSession } from "iron-session";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { sessionOptions, type SessionData } from "./session-options";

export { sessionOptions, type SessionData };

/**
 * Route handler'lar ve server component'ler için oturum erişimi.
 * Next 16'da cookies() async — await edilir.
 */
export async function getSession(): Promise<IronSession<SessionData>> {
  const cookieStore = await cookies();
  return getIronSession<SessionData>(cookieStore, sessionOptions);
}

/**
 * Route handler koruması: admin değilse 401 Response döner, adminse null.
 * Kullanım: `const denied = await requireAdmin(); if (denied) return denied;`
 */
export async function requireAdmin(): Promise<Response | null> {
  const session = await getSession();
  if (!session.admin) {
    return Response.json({ error: "Yetkisiz" }, { status: 401 });
  }
  return null;
}

/**
 * Server component koruması: admin değilse /login'e yönlendirir (throw eder).
 */
export async function requireAdminOrRedirect(): Promise<void> {
  const session = await getSession();
  if (!session.admin) {
    redirect("/login");
  }
}

import { sealData } from "iron-session";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * requireAdmin()'in GERÇEK implementasyonu test edilir; yalnız next/headers
 * mock'lanır (request scope dışında cookies() çağrılamadığı için).
 * Mock store, iron-session'ın beklediği CookieStore arayüzünü taklit eder.
 */
const store = new Map<string, string>();

vi.mock("next/headers", () => ({
  cookies: async () => ({
    get: (name: string) => {
      const value = store.get(name);
      return value === undefined ? undefined : { name, value };
    },
    set: (name: string, value: string) => {
      store.set(name, value);
    },
  }),
}));

beforeEach(() => {
  store.clear();
});

describe("requireAdmin", () => {
  it("oturum çerezi yokken 401 döner", async () => {
    const { requireAdmin } = await import("@/lib/session");
    const denied = await requireAdmin();
    expect(denied).not.toBeNull();
    expect(denied?.status).toBe(401);
  });

  it("admin=true mühürlü çerezle null döner (erişim serbest)", async () => {
    const { requireAdmin, sessionOptions } = await import("@/lib/session");
    const sealed = await sealData(
      { admin: true },
      { password: sessionOptions.password as string },
    );
    store.set(sessionOptions.cookieName, sealed);
    const denied = await requireAdmin();
    expect(denied).toBeNull();
  });
});

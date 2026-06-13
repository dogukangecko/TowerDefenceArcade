import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * Yaklaşım: route handler'lar doğrudan Request nesneleriyle, GERÇEK bir test
 * veritabanına (prisma/test.db) karşı çağrılır. requireAdmin() request scope
 * dışında cookies() okuyamadığı için yalnız @/lib/session mock'lanır —
 * mock, gerçek davranışı birebir taklit eder (admin değilse 401 Response,
 * adminse null) ve auth.admin bayrağıyla iki durum da test edilir.
 * requireAdmin'in kendisi tests/session.test.ts'te gerçek haliyle test edilir.
 */
const auth = vi.hoisted(() => ({ admin: true }));

vi.mock("@/lib/session", () => ({
  requireAdmin: async () =>
    auth.admin ? null : Response.json({ error: "Yetkisiz" }, { status: 401 }),
}));

import { prisma } from "@/lib/db";
import {
  GET as listProducts,
  POST as createProduct,
} from "@/app/api/admin/products/route";
import {
  DELETE as archiveProduct,
  PATCH as patchProduct,
} from "@/app/api/admin/products/[id]/route";
import { POST as publish } from "@/app/api/admin/publish/route";
import { GET as getCatalog } from "@/app/api/v1/catalog/route";

const BASE = "http://test.local";

function jsonRequest(path: string, method: string, body?: unknown): Request {
  return new Request(`${BASE}${path}`, {
    method,
    headers: { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

const sampleProduct = {
  name: "Keskin Uçlar",
  desc: "Kule hasarı +%10",
  icon: "🗡️",
  priceGold: 300,
  effectType: "towerDamage",
  effectValue: 0.1,
};

async function createVia(body: Record<string, unknown>) {
  const res = await createProduct(jsonRequest("/api/admin/products", "POST", body));
  expect(res.status).toBe(201);
  return (await res.json()) as { id: string; status: string };
}

beforeEach(async () => {
  auth.admin = true;
  await prisma.product.deleteMany();
  await prisma.catalogState.deleteMany();
});

describe("oturumsuz erişim (requireAdmin 401)", () => {
  it("tüm admin uçları 401 döner", async () => {
    auth.admin = false;
    const responses = await Promise.all([
      listProducts(new Request(`${BASE}/api/admin/products`)),
      createProduct(jsonRequest("/api/admin/products", "POST", sampleProduct)),
      patchProduct(jsonRequest("/api/admin/products/x", "PATCH", { priceGold: 5 }), {
        params: Promise.resolve({ id: "x" }),
      }),
      archiveProduct(new Request(`${BASE}/api/admin/products/x`, { method: "DELETE" }), {
        params: Promise.resolve({ id: "x" }),
      }),
      publish(),
    ]);
    for (const res of responses) {
      expect(res.status).toBe(401);
    }
  });
});

describe("POST /api/admin/products", () => {
  it("geçerli ürünü oluşturur (201) ve varsayılan status=draft atar", async () => {
    const created = await createVia(sampleProduct);
    expect(created.status).toBe("draft");
    const inDb = await prisma.product.findUnique({ where: { id: created.id } });
    expect(inDb?.name).toBe("Keskin Uçlar");
  });

  it("doğrulama hatasında 400 + issues döner", async () => {
    const res = await createProduct(
      jsonRequest("/api/admin/products", "POST", { ...sampleProduct, priceGold: 0 }),
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.issues?.length).toBeGreaterThan(0);
  });

  it("bozuk JSON gövdesinde 400 döner", async () => {
    const res = await createProduct(
      new Request(`${BASE}/api/admin/products`, { method: "POST", body: "{bozuk" }),
    );
    expect(res.status).toBe(400);
  });
});

describe("GET /api/admin/products", () => {
  it("listeler (en yeni önce) ve ?status= filtresi uygular", async () => {
    const a = await createVia({ ...sampleProduct, name: "Eski" });
    await prisma.product.update({
      where: { id: a.id },
      data: { createdAt: new Date(Date.now() - 60_000) },
    });
    await createVia({ ...sampleProduct, name: "Yeni", status: "published" });

    const all = await (await listProducts(new Request(`${BASE}/api/admin/products`))).json();
    expect(all.map((p: { name: string }) => p.name)).toEqual(["Yeni", "Eski"]);

    const drafts = await (
      await listProducts(new Request(`${BASE}/api/admin/products?status=draft`))
    ).json();
    expect(drafts).toHaveLength(1);
    expect(drafts[0].name).toBe("Eski");
  });
});

describe("PATCH ve DELETE /api/admin/products/[id]", () => {
  it("kısmi günceller", async () => {
    const created = await createVia(sampleProduct);
    const res = await patchProduct(
      jsonRequest(`/api/admin/products/${created.id}`, "PATCH", { priceGold: 450 }),
      { params: Promise.resolve({ id: created.id }) },
    );
    expect(res.status).toBe(200);
    const updated = await res.json();
    expect(updated.priceGold).toBe(450);
    expect(updated.name).toBe("Keskin Uçlar");
  });

  it("bilinmeyen id'de 404 döner", async () => {
    const res = await patchProduct(
      jsonRequest("/api/admin/products/yok", "PATCH", { priceGold: 450 }),
      { params: Promise.resolve({ id: "yok" }) },
    );
    expect(res.status).toBe(404);
  });

  it("DELETE gerçek silmez, status=archived yapar", async () => {
    const created = await createVia(sampleProduct);
    const res = await archiveProduct(
      new Request(`${BASE}/api/admin/products/${created.id}`, { method: "DELETE" }),
      { params: Promise.resolve({ id: created.id }) },
    );
    expect(res.status).toBe(200);
    const inDb = await prisma.product.findUnique({ where: { id: created.id } });
    expect(inDb).not.toBeNull();
    expect(inDb?.status).toBe("archived");
  });
});

describe("publish + katalog akışı", () => {
  it("create→publish→catalog: yalnız published görünür, sürüm artar", async () => {
    await createVia({ ...sampleProduct, name: "Taslak Ürün" });
    const pub = await createVia({
      ...sampleProduct,
      name: "Yayında Ürün",
      status: "published",
    });

    const pubRes = await publish();
    expect((await pubRes.json()).version).toBe(1);

    const catRes = await getCatalog(new Request(`${BASE}/api/v1/catalog`));
    expect(catRes.status).toBe(200);
    expect(catRes.headers.get("ETag")).toBe('"v1"');
    expect(catRes.headers.get("Cache-Control")).toBe("no-cache");
    const catalog = await catRes.json();
    expect(catalog.version).toBe(1);
    expect(catalog.items).toHaveLength(1);
    expect(catalog.items[0]).toEqual({
      id: pub.id,
      name: "Yayında Ürün",
      desc: "Kule hasarı +%10",
      icon: "🗡️",
      priceGold: 300,
      effect: { type: "towerDamage", value: 0.1 },
      premium: false,
      kind: "item",
      assetKey: null,
    });

    // İkinci publish sürümü 2'ye çıkarır.
    expect((await (await publish()).json()).version).toBe(2);
  });

  it("eşleşen If-None-Match → 304, boş gövde", async () => {
    await publish(); // version 1
    const res = await getCatalog(
      new Request(`${BASE}/api/v1/catalog`, {
        headers: { "If-None-Match": '"v1"' },
      }),
    );
    expect(res.status).toBe(304);
    expect(await res.text()).toBe("");

    // Eski ETag → 200 + güncel sürüm.
    const stale = await getCatalog(
      new Request(`${BASE}/api/v1/catalog`, {
        headers: { "If-None-Match": '"v0"' },
      }),
    );
    expect(stale.status).toBe(200);
  });

  it("arşivlenen ürün katalogdan düşer", async () => {
    const created = await createVia({ ...sampleProduct, status: "published" });
    await publish();
    await archiveProduct(
      new Request(`${BASE}/api/admin/products/${created.id}`, { method: "DELETE" }),
      { params: Promise.resolve({ id: created.id }) },
    );
    const catalog = await (await getCatalog(new Request(`${BASE}/api/v1/catalog`))).json();
    expect(catalog.items).toHaveLength(0);
  });

  it("hiç publish yokken katalog version 0 ve boş liste döner", async () => {
    const res = await getCatalog(new Request(`${BASE}/api/v1/catalog`));
    expect(res.status).toBe(200);
    const catalog = await res.json();
    expect(catalog).toEqual({ version: 0, items: [] });
    expect(res.headers.get("ETag")).toBe('"v0"');
  });
});

describe("skin/tema ürünleri (kind + assetKey)", () => {
  const sampleSkin = {
    name: "Buz Seti",
    desc: "Kuleler buzul mavisine bürünür.",
    icon: "❄️",
    priceGold: 400,
    kind: "skin",
    assetKey: "buz",
    effectType: "none",
    effectValue: 0,
    premium: true,
    status: "published",
  };

  it("assetKey'siz skin POST 400 döner", async () => {
    const res = await createProduct(
      jsonRequest("/api/admin/products", "POST", { ...sampleSkin, assetKey: null }),
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(
      body.issues.some((i: { path: string[] }) => i.path[0] === "assetKey"),
    ).toBe(true);
  });

  it("PATCH birleşik doğrulama: item'ı assetKey'siz skin'e çevirmek 400 döner", async () => {
    const created = await createVia(sampleProduct);
    const res = await patchProduct(
      jsonRequest(`/api/admin/products/${created.id}`, "PATCH", { kind: "skin" }),
      { params: Promise.resolve({ id: created.id }) },
    );
    expect(res.status).toBe(400);
  });

  it("PATCH tam dönüşüm (kind+assetKey+none) kabul edilir", async () => {
    const created = await createVia(sampleProduct);
    const res = await patchProduct(
      jsonRequest(`/api/admin/products/${created.id}`, "PATCH", {
        kind: "skin",
        assetKey: "kor",
        effectType: "none",
        effectValue: 0,
      }),
      { params: Promise.resolve({ id: created.id }) },
    );
    expect(res.status).toBe(200);
    const updated = await res.json();
    expect(updated.kind).toBe("skin");
    expect(updated.assetKey).toBe("kor");
  });

  it("katalog skin/temayı kind+assetKey ve nötr effect ile döner", async () => {
    const skin = await createVia(sampleSkin);
    const theme = await createVia({
      ...sampleSkin,
      name: "Sonbahar Teması",
      icon: "🍂",
      priceGold: 300,
      kind: "theme",
      assetKey: "sonbahar",
      premium: false,
    });
    await publish();

    const catalog = await (await getCatalog(new Request(`${BASE}/api/v1/catalog`))).json();
    expect(catalog.items).toHaveLength(2);

    const skinItem = catalog.items.find((i: { id: string }) => i.id === skin.id);
    expect(skinItem).toEqual({
      id: skin.id,
      name: "Buz Seti",
      desc: "Kuleler buzul mavisine bürünür.",
      icon: "❄️",
      priceGold: 400,
      effect: { type: "none", value: 0 },
      premium: true,
      kind: "skin",
      assetKey: "buz",
    });

    const themeItem = catalog.items.find((i: { id: string }) => i.id === theme.id);
    expect(themeItem).toMatchObject({
      kind: "theme",
      assetKey: "sonbahar",
      effect: { type: "none", value: 0 },
    });
  });
});

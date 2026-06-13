import { describe, expect, it } from "vitest";
import { ProductInput, ProductPatch } from "@/lib/validation";

const valid = {
  name: "Başlangıç Kesesi",
  priceGold: 120,
  effectType: "startGold",
  effectValue: 50,
};

describe("ProductInput", () => {
  it("geçerli asgari girdiyi kabul eder ve varsayılanları doldurur", () => {
    const result = ProductInput.safeParse(valid);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data).toMatchObject({
      desc: "",
      icon: "⚔️",
      premium: false,
      status: "draft",
    });
  });

  it("boş adı reddeder", () => {
    expect(ProductInput.safeParse({ ...valid, name: "" }).success).toBe(false);
  });

  it("60 karakterden uzun adı reddeder", () => {
    const result = ProductInput.safeParse({ ...valid, name: "a".repeat(61) });
    expect(result.success).toBe(false);
  });

  it("priceGold sınırlarını uygular (1-100000, tamsayı)", () => {
    expect(ProductInput.safeParse({ ...valid, priceGold: 0 }).success).toBe(false);
    expect(ProductInput.safeParse({ ...valid, priceGold: 100001 }).success).toBe(false);
    expect(ProductInput.safeParse({ ...valid, priceGold: 49.5 }).success).toBe(false);
    expect(ProductInput.safeParse({ ...valid, priceGold: 100000 }).success).toBe(true);
  });

  it("bilinmeyen effectType'ı reddeder", () => {
    const result = ProductInput.safeParse({ ...valid, effectType: "luck" });
    expect(result.success).toBe(false);
  });

  it("sıfır/negatif effectValue'yu reddeder", () => {
    expect(ProductInput.safeParse({ ...valid, effectValue: 0 }).success).toBe(false);
    expect(ProductInput.safeParse({ ...valid, effectValue: -1 }).success).toBe(false);
  });

  it("bilinmeyen status'u reddeder", () => {
    const result = ProductInput.safeParse({ ...valid, status: "live" });
    expect(result.success).toBe(false);
  });

  it("200 karakterden uzun açıklamayı reddeder", () => {
    const result = ProductInput.safeParse({ ...valid, desc: "x".repeat(201) });
    expect(result.success).toBe(false);
  });
});

describe("ProductInput — kind kuralları (skin/tema)", () => {
  const validSkin = {
    name: "Buz Seti",
    priceGold: 400,
    kind: "skin",
    assetKey: "buz",
    effectType: "none",
    effectValue: 0,
  };

  it("varsayılan kind=item ve assetKey=null doldurur", () => {
    const result = ProductInput.safeParse(valid);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data.kind).toBe("item");
    expect(result.data.assetKey).toBeNull();
  });

  it("geçerli skin'i kabul eder (effectType none, effectValue 0)", () => {
    const result = ProductInput.safeParse(validSkin);
    expect(result.success).toBe(true);
    if (!result.success) return;
    expect(result.data).toMatchObject({ kind: "skin", assetKey: "buz" });
  });

  it("geçerli temayı kabul eder", () => {
    const result = ProductInput.safeParse({
      ...validSkin,
      name: "Sonbahar Teması",
      kind: "theme",
      assetKey: "sonbahar",
    });
    expect(result.success).toBe(true);
  });

  it("assetKey'siz skin'i reddeder", () => {
    const result = ProductInput.safeParse({ ...validSkin, assetKey: undefined });
    expect(result.success).toBe(false);
    if (result.success) return;
    expect(result.error.issues.some((i) => i.path[0] === "assetKey")).toBe(true);
  });

  it("boş/boşluk assetKey'li skin'i reddeder", () => {
    expect(ProductInput.safeParse({ ...validSkin, assetKey: "" }).success).toBe(false);
    expect(ProductInput.safeParse({ ...validSkin, assetKey: "   " }).success).toBe(false);
  });

  it("etkili skin'i reddeder (effectType startGold)", () => {
    const result = ProductInput.safeParse({
      ...validSkin,
      effectType: "startGold",
      effectValue: 50,
    });
    expect(result.success).toBe(false);
    if (result.success) return;
    expect(result.error.issues.some((i) => i.path[0] === "effectType")).toBe(true);
  });

  it("skin'de sıfırdan farklı effectValue'yu reddeder", () => {
    expect(ProductInput.safeParse({ ...validSkin, effectValue: 5 }).success).toBe(false);
  });

  it("item'da effectType none'ı reddeder", () => {
    const result = ProductInput.safeParse({
      ...valid,
      effectType: "none",
      effectValue: 0,
    });
    expect(result.success).toBe(false);
    if (result.success) return;
    expect(result.error.issues.some((i) => i.path[0] === "effectType")).toBe(true);
  });

  it("bilinmeyen kind'ı reddeder", () => {
    expect(ProductInput.safeParse({ ...valid, kind: "sticker" }).success).toBe(false);
  });
});

describe("ProductPatch", () => {
  it("tek alanlı kısmi güncellemeyi kabul eder", () => {
    const result = ProductPatch.safeParse({ priceGold: 250 });
    expect(result.success).toBe(true);
  });

  it("boş gövdeyi kabul eder (hiçbir alan zorunlu değil)", () => {
    expect(ProductPatch.safeParse({}).success).toBe(true);
  });

  it("kısmi güncellemede de alan kurallarını uygular", () => {
    expect(ProductPatch.safeParse({ name: "" }).success).toBe(false);
    expect(ProductPatch.safeParse({ effectValue: -5 }).success).toBe(false);
  });

  it("verilmeyen alanlara default enjekte etmez (zod 4 partial+default tuzağı)", () => {
    // Regresyon: ProductFields.partial() zod 4'te default'ları tetikler ve
    // {priceGold: 450} → {priceGold: 450, kind: "item", status: "draft", ...}
    // üretirdi; PATCH handler bunu mevcut satırın üstüne yayınca skin/tema
    // ürünleri bozuluyordu.
    expect(ProductPatch.parse({ priceGold: 450 })).toEqual({ priceGold: 450 });
  });

  it("tek başına kind alanını kabul eder (tür kuralları handler'da birleşik doğrulanır)", () => {
    expect(ProductPatch.safeParse({ kind: "skin" }).success).toBe(true);
    expect(ProductPatch.safeParse({ kind: "sticker" }).success).toBe(false);
  });
});

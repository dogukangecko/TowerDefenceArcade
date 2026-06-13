import { z } from "zod";

export const EFFECT_TYPES = ["startGold", "towerDamage", "extraLives", "none"] as const;
export const PRODUCT_STATUSES = ["draft", "published", "archived"] as const;
export const PRODUCT_KINDS = ["item", "skin", "theme"] as const;

/**
 * Çekirdek alan kuralları — DEFAULT'SUZ. PATCH şeması buradan türetilir:
 * zod 4'te `.partial()` default'lu alanları es geçmez, verilmeyen anahtarlara
 * default değerleri ENJEKTE eder ({priceGold: 450} → kind: "item", status:
 * "draft", ...). Bu yüzden default'lar yalnızca tam gövdeye (ProductFields)
 * eklenir.
 */
const BareProductFields = z.object({
  name: z.string().min(1).max(60),
  desc: z.string().max(200),
  icon: z.string().max(8),
  priceGold: z.number().int().min(1).max(100000),
  effectType: z.enum(EFFECT_TYPES),
  effectValue: z.number().min(0),
  premium: z.boolean(),
  status: z.enum(PRODUCT_STATUSES),
  kind: z.enum(PRODUCT_KINDS),
  assetKey: z.string().max(40).nullable(),
});

/** Tam gövde alanları — tür kuralları (kind ↔ effect/assetKey) ayrıca superRefine ile. */
const ProductFields = BareProductFields.extend({
  desc: BareProductFields.shape.desc.default(""),
  icon: BareProductFields.shape.icon.default("⚔️"),
  premium: BareProductFields.shape.premium.default(false),
  status: BareProductFields.shape.status.default("draft"),
  kind: BareProductFields.shape.kind.default("item"),
  assetKey: BareProductFields.shape.assetKey.default(null),
});

type ProductFieldsType = z.infer<typeof ProductFields>;

/**
 * Tür-bağımlı kurallar:
 * - kind=item       → gerçek bir etki zorunlu (effectType≠none, effectValue>0)
 * - kind=skin/theme → assetKey zorunlu; etki olamaz (effectType=none, effectValue=0)
 */
function applyKindRules(data: ProductFieldsType, ctx: z.RefinementCtx) {
  if (data.kind === "item") {
    if (data.effectType === "none") {
      ctx.addIssue({
        code: "custom",
        path: ["effectType"],
        message: "Item türünde gerçek bir etki zorunludur (none olamaz)",
      });
    }
    if (data.effectValue <= 0) {
      ctx.addIssue({
        code: "custom",
        path: ["effectValue"],
        message: "Etki değeri pozitif olmalı",
      });
    }
  } else {
    if (!data.assetKey || data.assetKey.trim() === "") {
      ctx.addIssue({
        code: "custom",
        path: ["assetKey"],
        message: "Skin/tema için varlık anahtarı (assetKey) zorunludur",
      });
    }
    if (data.effectType !== "none") {
      ctx.addIssue({
        code: "custom",
        path: ["effectType"],
        message: "Skin/tema ürünlerinde etki türü 'none' olmalı",
      });
    }
    if (data.effectValue !== 0) {
      ctx.addIssue({
        code: "custom",
        path: ["effectValue"],
        message: "Skin/tema ürünlerinde etki değeri 0 olmalı",
      });
    }
  }
}

/** Ürün oluşturma gövdesi (POST /api/admin/products). */
export const ProductInput = ProductFields.superRefine(applyKindRules);

/**
 * Kısmi güncelleme gövdesi (PATCH /api/admin/products/[id]).
 * Default'suz çekirdekten türetilir ki verilmeyen alanlar çıktıda yer almasın.
 * Tür kuralları burada UYGULANMAZ — PATCH handler mevcut satırla birleştirip
 * tam ProductInput şemasından geçirir (bkz. app/api/admin/products/[id]/route.ts).
 */
export const ProductPatch = BareProductFields.partial();

export type ProductInputType = z.infer<typeof ProductInput>;
export type ProductPatchType = z.infer<typeof ProductPatch>;

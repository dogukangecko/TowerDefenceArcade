"use client";

import { type FormEvent, useState } from "react";
import { formatEffect } from "@/lib/format";
import type { ProductDTO } from "./types";

const EFFECT_OPTIONS = [
  { value: "startGold", label: "Başlangıç Altını" },
  { value: "towerDamage", label: "Kule Hasarı (oran: 0.10 = %10)" },
  { value: "extraLives", label: "Ekstra Can" },
];

const STATUS_OPTIONS = [
  { value: "draft", label: "Taslak" },
  { value: "published", label: "Yayında" },
  { value: "archived", label: "Arşiv" },
];

const KIND_OPTIONS = [
  { value: "item", label: "Item (etki)" },
  { value: "skin", label: "Skin (görünüm seti)" },
  { value: "theme", label: "Tema (harita görünümü)" },
];

type ZodIssue = { path: (string | number)[]; message: string };

const inputBase =
  "w-full rounded-md border bg-zinc-950 px-3 py-2 text-sm text-zinc-100 outline-none transition focus:border-amber-500 focus:ring-1 focus:ring-amber-500";

/**
 * Yeni ürün / düzenleme modal formu. `initial` verilirse PATCH, yoksa POST.
 * API 400 yanıtındaki zod `issues` dizisi alan bazlı hatalara eşlenir.
 */
export default function ProductForm({
  initial,
  onClose,
  onSaved,
}: {
  initial: ProductDTO | null;
  onClose: () => void;
  onSaved: (message: string) => void;
}) {
  const [fields, setFields] = useState({
    name: initial?.name ?? "",
    desc: initial?.desc ?? "",
    icon: initial?.icon ?? "⚔️",
    priceGold: initial ? String(initial.priceGold) : "",
    effectType: initial?.effectType ?? "startGold",
    effectValue: initial ? String(initial.effectValue) : "",
    premium: initial?.premium ?? false,
    status: initial?.status ?? "draft",
    kind: initial?.kind ?? "item",
    assetKey: initial?.assetKey ?? "",
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [formError, setFormError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  function set<K extends keyof typeof fields>(key: K, value: (typeof fields)[K]) {
    setFields((f) => ({ ...f, [key]: value }));
  }

  function border(field: string) {
    return errors[field] ? "border-red-500" : "border-zinc-700";
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setErrors({});
    setFormError(null);

    // Skin/tema'da etki alanları zorla nötrlenir (gizli oldukları için):
    // effectType "none", effectValue 0; item'da assetKey null gider.
    const isItem = fields.kind === "item";
    const payload = {
      name: fields.name.trim(),
      desc: fields.desc,
      icon: fields.icon,
      priceGold: Number(fields.priceGold),
      effectType: isItem ? fields.effectType : "none",
      effectValue: isItem ? Number(fields.effectValue) : 0,
      premium: fields.premium,
      status: fields.status,
      kind: fields.kind,
      assetKey: isItem ? null : fields.assetKey.trim(),
    };

    try {
      const res = await fetch(
        initial ? `/api/admin/products/${initial.id}` : "/api/admin/products",
        {
          method: initial ? "PATCH" : "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        },
      );

      if (res.ok) {
        onSaved(initial ? "Ürün güncellendi." : "Ürün oluşturuldu.");
        return;
      }

      const data = await res.json().catch(() => null);
      if (res.status === 400 && Array.isArray(data?.issues)) {
        const fieldErrors: Record<string, string> = {};
        for (const issue of data.issues as ZodIssue[]) {
          const key = String(issue.path[0] ?? "");
          if (key && !fieldErrors[key]) fieldErrors[key] = issue.message;
        }
        setErrors(fieldErrors);
        setFormError("Lütfen işaretli alanları düzeltin.");
      } else {
        setFormError(data?.error ?? "Beklenmeyen bir hata oluştu.");
      }
    } catch {
      setFormError("Sunucuya ulaşılamadı.");
    } finally {
      setBusy(false);
    }
  }

  const previewValue = Number(fields.effectValue);

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/70 p-4 sm:items-center"
      role="dialog"
      aria-modal="true"
      aria-label={initial ? "Ürünü düzenle" : "Yeni ürün"}
    >
      <div className="w-full max-w-lg rounded-xl border border-zinc-800 bg-zinc-900 p-6 shadow-2xl shadow-black/50">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-zinc-100">
            {initial ? "Ürünü Düzenle" : "Yeni Ürün"}
          </h2>
          <button
            type="button"
            onClick={onClose}
            aria-label="Kapat"
            className="rounded-md px-2 py-1 text-zinc-400 transition hover:bg-zinc-800 hover:text-zinc-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-500"
          >
            ✕
          </button>
        </div>

        <form onSubmit={handleSubmit} className="mt-4 space-y-4">
          <div className="grid gap-4 sm:grid-cols-[1fr_5.5rem]">
            <label className="block">
              <span className="mb-1 block text-sm font-medium text-zinc-300">Ad</span>
              <input
                value={fields.name}
                onChange={(e) => set("name", e.target.value)}
                autoFocus
                className={`${inputBase} ${border("name")}`}
              />
              {errors.name && <p className="mt-1 text-xs text-red-400">{errors.name}</p>}
            </label>
            <label className="block">
              <span className="mb-1 block text-sm font-medium text-zinc-300">İkon</span>
              <input
                value={fields.icon}
                onChange={(e) => set("icon", e.target.value)}
                className={`${inputBase} text-center ${border("icon")}`}
              />
              {errors.icon && <p className="mt-1 text-xs text-red-400">{errors.icon}</p>}
            </label>
          </div>

          <label className="block">
            <span className="mb-1 block text-sm font-medium text-zinc-300">Açıklama</span>
            <textarea
              value={fields.desc}
              onChange={(e) => set("desc", e.target.value)}
              rows={2}
              className={`${inputBase} resize-none ${border("desc")}`}
            />
            {errors.desc && <p className="mt-1 text-xs text-red-400">{errors.desc}</p>}
          </label>

          <div className="grid gap-4 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1 block text-sm font-medium text-zinc-300">Tür</span>
              <select
                value={fields.kind}
                onChange={(e) => {
                  const kind = e.target.value;
                  setFields((f) => ({
                    ...f,
                    kind,
                    // Skin/tema'dan item'a dönüşte gizli kalan "none" temizlenir.
                    effectType:
                      kind === "item" && f.effectType === "none"
                        ? "startGold"
                        : f.effectType,
                  }));
                }}
                className={`${inputBase} ${border("kind")}`}
              >
                {KIND_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </select>
              {errors.kind && <p className="mt-1 text-xs text-red-400">{errors.kind}</p>}
            </label>
            {fields.kind !== "item" && (
              <label className="block">
                <span className="mb-1 block text-sm font-medium text-zinc-300">
                  Varlık Anahtarı (assetKey)
                </span>
                <input
                  value={fields.assetKey}
                  onChange={(e) => set("assetKey", e.target.value)}
                  placeholder={fields.kind === "skin" ? "ör. buz" : "ör. sonbahar"}
                  className={`${inputBase} ${border("assetKey")}`}
                />
                {errors.assetKey && (
                  <p className="mt-1 text-xs text-red-400">{errors.assetKey}</p>
                )}
              </label>
            )}
          </div>

          {fields.kind === "item" && (
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1 block text-sm font-medium text-zinc-300">Etki Türü</span>
              <select
                value={fields.effectType}
                onChange={(e) => set("effectType", e.target.value)}
                className={`${inputBase} ${border("effectType")}`}
              >
                {EFFECT_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </select>
              {errors.effectType && (
                <p className="mt-1 text-xs text-red-400">{errors.effectType}</p>
              )}
            </label>
            <label className="block">
              <span className="mb-1 block text-sm font-medium text-zinc-300">Etki Değeri</span>
              <input
                type="number"
                step="any"
                min="0"
                value={fields.effectValue}
                onChange={(e) => set("effectValue", e.target.value)}
                className={`${inputBase} ${border("effectValue")}`}
              />
              {errors.effectValue && (
                <p className="mt-1 text-xs text-red-400">{errors.effectValue}</p>
              )}
            </label>
          </div>
          )}

          {fields.kind === "item" && Number.isFinite(previewValue) && previewValue > 0 && (
            <p className="rounded-md border border-zinc-800 bg-zinc-950 px-3 py-2 text-xs text-amber-400">
              Etki önizleme: {formatEffect(fields.effectType, previewValue)}
            </p>
          )}

          <div className="grid gap-4 sm:grid-cols-2">
            <label className="block">
              <span className="mb-1 block text-sm font-medium text-zinc-300">Fiyat (altın)</span>
              <input
                type="number"
                min="1"
                step="1"
                value={fields.priceGold}
                onChange={(e) => set("priceGold", e.target.value)}
                className={`${inputBase} ${border("priceGold")}`}
              />
              {errors.priceGold && (
                <p className="mt-1 text-xs text-red-400">{errors.priceGold}</p>
              )}
            </label>
            <label className="block">
              <span className="mb-1 block text-sm font-medium text-zinc-300">Durum</span>
              <select
                value={fields.status}
                onChange={(e) => set("status", e.target.value)}
                className={`${inputBase} ${border("status")}`}
              >
                {STATUS_OPTIONS.map((o) => (
                  <option key={o.value} value={o.value}>
                    {o.label}
                  </option>
                ))}
              </select>
              {errors.status && <p className="mt-1 text-xs text-red-400">{errors.status}</p>}
            </label>
          </div>

          <label className="flex items-center gap-2 text-sm text-zinc-300">
            <input
              type="checkbox"
              checked={fields.premium}
              onChange={(e) => set("premium", e.target.checked)}
              className="h-4 w-4 rounded border-zinc-700 accent-amber-500"
            />
            Premium ürün
          </label>

          {formError && (
            <p role="alert" className="text-sm text-red-400">
              {formError}
            </p>
          )}

          <div className="flex justify-end gap-2 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-md border border-zinc-700 px-4 py-2 text-sm font-medium text-zinc-300 transition hover:bg-zinc-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-500"
            >
              Vazgeç
            </button>
            <button
              type="submit"
              disabled={busy}
              className="rounded-md bg-amber-500 px-4 py-2 text-sm font-semibold text-zinc-950 transition hover:bg-amber-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-300 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {busy ? "Kaydediliyor…" : initial ? "Güncelle" : "Oluştur"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

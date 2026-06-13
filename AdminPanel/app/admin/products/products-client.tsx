"use client";

import { useRouter } from "next/navigation";
import { useCallback, useEffect, useRef, useState } from "react";
import { formatEffect, formatPrice } from "@/lib/format";
import ProductForm from "./product-form";
import type { ProductDTO } from "./types";

const STATUS_BADGE: Record<string, { label: string; className: string }> = {
  draft: {
    label: "Taslak",
    className: "border-zinc-600 bg-zinc-800 text-zinc-300",
  },
  published: {
    label: "Yayında",
    className: "border-emerald-500/40 bg-emerald-500/10 text-emerald-400",
  },
  archived: {
    label: "Arşiv",
    className: "border-red-500/40 bg-red-500/10 text-red-400 line-through",
  },
};

function StatusBadge({ status }: { status: string }) {
  const badge = STATUS_BADGE[status] ?? STATUS_BADGE.draft;
  return (
    <span
      className={`inline-block rounded-full border px-2.5 py-0.5 text-xs font-semibold ${badge.className}`}
    >
      {badge.label}
    </span>
  );
}

const KIND_BADGE: Record<string, { label: string; className: string }> = {
  skin: {
    label: "Skin",
    className: "border-sky-500/40 bg-sky-500/10 text-sky-400",
  },
  theme: {
    label: "Tema",
    className: "border-violet-500/40 bg-violet-500/10 text-violet-400",
  },
};

/** kind=item için rozet basılmaz; skin/tema renkli rozet alır. */
function KindBadge({ kind }: { kind: string }) {
  const badge = KIND_BADGE[kind];
  if (!badge) return null;
  return (
    <span
      className={`inline-block rounded-full border px-2.5 py-0.5 text-xs font-semibold ${badge.className}`}
    >
      {badge.label}
    </span>
  );
}

function PremiumBadge() {
  return (
    <span className="inline-block rounded-full border border-amber-500/40 bg-amber-500/10 px-2.5 py-0.5 text-xs font-semibold text-amber-500">
      Premium
    </span>
  );
}

const actionButton =
  "rounded-md border border-zinc-700 px-2.5 py-1 text-xs font-medium text-zinc-300 transition hover:bg-zinc-800 hover:text-zinc-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-500 disabled:cursor-not-allowed disabled:opacity-50";

type ConfirmState = {
  title: string;
  message: string;
  confirmLabel: string;
  destructive?: boolean;
  onConfirm: () => Promise<void>;
};

type ToastState = { text: string; ok: boolean };

export default function ProductsClient({ products }: { products: ProductDTO[] }) {
  const router = useRouter();
  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState<ProductDTO | null>(null);
  const [confirm, setConfirm] = useState<ConfirmState | null>(null);
  const [confirmBusy, setConfirmBusy] = useState(false);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [toast, setToast] = useState<ToastState | null>(null);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const showToast = useCallback((text: string, ok = true) => {
    if (toastTimer.current) clearTimeout(toastTimer.current);
    setToast({ text, ok });
    toastTimer.current = setTimeout(() => setToast(null), 4000);
  }, []);

  useEffect(() => {
    return () => {
      if (toastTimer.current) clearTimeout(toastTimer.current);
    };
  }, []);

  function openCreate() {
    setEditing(null);
    setFormOpen(true);
  }

  function openEdit(product: ProductDTO) {
    setEditing(product);
    setFormOpen(true);
  }

  async function patchStatus(product: ProductDTO, status: string, message: string) {
    setBusyId(product.id);
    try {
      const res = await fetch(`/api/admin/products/${product.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status }),
      });
      if (res.ok) {
        showToast(message);
        router.refresh();
      } else {
        const data = await res.json().catch(() => null);
        showToast(data?.error ?? "İşlem başarısız oldu.", false);
      }
    } catch {
      showToast("Sunucuya ulaşılamadı.", false);
    } finally {
      setBusyId(null);
    }
  }

  function askArchive(product: ProductDTO) {
    setConfirm({
      title: "Ürünü arşivle",
      message: `"${product.name}" arşive taşınacak ve katalogdan çıkacak. Devam edilsin mi?`,
      confirmLabel: "Arşivle",
      destructive: true,
      onConfirm: async () => {
        const res = await fetch(`/api/admin/products/${product.id}`, {
          method: "DELETE",
        });
        if (res.ok) {
          showToast(`"${product.name}" arşivlendi.`);
          router.refresh();
        } else {
          const data = await res.json().catch(() => null);
          showToast(data?.error ?? "Arşivleme başarısız oldu.", false);
        }
      },
    });
  }

  function askPublishCatalog() {
    setConfirm({
      title: "Kataloğu yayınla",
      message:
        "Taslak değişiklikler canlıya çıkar, katalog sürümü artar. Devam edilsin mi?",
      confirmLabel: "Yayınla",
      onConfirm: async () => {
        const res = await fetch("/api/admin/publish", { method: "POST" });
        if (res.ok) {
          const data = await res.json().catch(() => null);
          showToast(`Katalog v${data?.version ?? "?"} yayında 🎉`);
          router.refresh();
        } else {
          const data = await res.json().catch(() => null);
          showToast(data?.error ?? "Yayınlama başarısız oldu.", false);
        }
      },
    });
  }

  async function runConfirm() {
    if (!confirm) return;
    setConfirmBusy(true);
    try {
      await confirm.onConfirm();
    } finally {
      setConfirmBusy(false);
      setConfirm(null);
    }
  }

  function rowActions(product: ProductDTO) {
    const busy = busyId === product.id;
    return (
      <div className="flex flex-wrap items-center gap-1.5">
        <button
          type="button"
          disabled={busy}
          onClick={() => openEdit(product)}
          className={actionButton}
        >
          Düzenle
        </button>
        {product.status === "draft" && (
          <button
            type="button"
            disabled={busy}
            onClick={() =>
              patchStatus(product, "published", `"${product.name}" yayına alındı.`)
            }
            className={`${actionButton} border-emerald-500/40 text-emerald-400 hover:bg-emerald-500/10 hover:text-emerald-300`}
          >
            Yayınla
          </button>
        )}
        {product.status === "published" && (
          <button
            type="button"
            disabled={busy}
            onClick={() =>
              patchStatus(product, "draft", `"${product.name}" yayından kaldırıldı.`)
            }
            className={actionButton}
          >
            Yayından Kaldır
          </button>
        )}
        {product.status === "archived" ? (
          <button
            type="button"
            disabled={busy}
            onClick={() =>
              patchStatus(product, "draft", `"${product.name}" taslağa geri alındı.`)
            }
            className={actionButton}
          >
            Geri Al
          </button>
        ) : (
          <button
            type="button"
            disabled={busy}
            onClick={() => askArchive(product)}
            className={`${actionButton} border-red-500/40 text-red-400 hover:bg-red-500/10 hover:text-red-300`}
          >
            Arşivle
          </button>
        )}
      </div>
    );
  }

  return (
    <div>
      {/* Üst bar: başlık + ana eylemler */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-zinc-100">Mağaza</h1>
          <p className="mt-1 text-sm text-zinc-400">
            Ürünleri yönet, durumlarını değiştir ve kataloğu yayınla.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={openCreate}
            className="rounded-md border border-zinc-700 bg-zinc-900 px-4 py-2 text-sm font-semibold text-zinc-100 transition hover:bg-zinc-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-500"
          >
            + Yeni Ürün
          </button>
          <button
            type="button"
            onClick={askPublishCatalog}
            className="rounded-md bg-amber-500 px-4 py-2 text-sm font-bold text-zinc-950 shadow-lg shadow-amber-500/20 transition hover:bg-amber-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-300"
          >
            Yayınla
          </button>
        </div>
      </div>

      {products.length === 0 ? (
        <div className="mt-8 rounded-xl border border-dashed border-zinc-800 bg-zinc-900/50 p-10 text-center text-sm text-zinc-400">
          Henüz ürün yok. &quot;Yeni Ürün&quot; ile ilk ürünü ekleyin.
        </div>
      ) : (
        <>
          {/* Masaüstü: tablo */}
          <div className="mt-6 hidden overflow-x-auto rounded-xl border border-zinc-800 md:block">
            <table className="w-full min-w-[720px] text-left text-sm">
              <thead className="border-b border-zinc-800 bg-zinc-900 text-xs uppercase tracking-wider text-zinc-500">
                <tr>
                  <th scope="col" className="px-4 py-3">Ürün</th>
                  <th scope="col" className="px-4 py-3">Etki</th>
                  <th scope="col" className="px-4 py-3">Fiyat</th>
                  <th scope="col" className="px-4 py-3">Premium</th>
                  <th scope="col" className="px-4 py-3">Durum</th>
                  <th scope="col" className="px-4 py-3">Eylemler</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-800/70 bg-zinc-900/40">
                {products.map((product) => (
                  <tr key={product.id} className="transition hover:bg-zinc-900">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <span className="text-xl" aria-hidden>
                          {product.icon}
                        </span>
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <p
                              className={`font-semibold text-zinc-100 ${
                                product.status === "archived" ? "line-through text-zinc-500" : ""
                              }`}
                            >
                              {product.name}
                            </p>
                            <KindBadge kind={product.kind} />
                          </div>
                          {product.desc && (
                            <p className="truncate text-xs text-zinc-500">{product.desc}</p>
                          )}
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-zinc-300">
                      {formatEffect(product.effectType, product.effectValue)}
                    </td>
                    <td className="px-4 py-3 whitespace-nowrap font-medium text-amber-400">
                      {formatPrice(product.priceGold)}
                    </td>
                    <td className="px-4 py-3">
                      {product.premium ? (
                        <PremiumBadge />
                      ) : (
                        <span className="text-zinc-600">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <StatusBadge status={product.status} />
                    </td>
                    <td className="px-4 py-3">{rowActions(product)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Mobil: kart listesi */}
          <ul className="mt-6 space-y-3 md:hidden">
            {products.map((product) => (
              <li
                key={product.id}
                className="rounded-xl border border-zinc-800 bg-zinc-900 p-4"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="flex min-w-0 items-center gap-3">
                    <span className="text-2xl" aria-hidden>
                      {product.icon}
                    </span>
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <p
                          className={`font-semibold text-zinc-100 ${
                            product.status === "archived" ? "line-through text-zinc-500" : ""
                          }`}
                        >
                          {product.name}
                        </p>
                        <KindBadge kind={product.kind} />
                      </div>
                      <p className="text-xs text-zinc-400">
                        {formatEffect(product.effectType, product.effectValue)}
                      </p>
                    </div>
                  </div>
                  <StatusBadge status={product.status} />
                </div>
                <div className="mt-3 flex items-center gap-2 text-sm">
                  <span className="font-medium text-amber-400">
                    {formatPrice(product.priceGold)}
                  </span>
                  {product.premium && <PremiumBadge />}
                </div>
                <div className="mt-3 border-t border-zinc-800 pt-3">
                  {rowActions(product)}
                </div>
              </li>
            ))}
          </ul>
        </>
      )}

      {/* Yeni ürün / düzenleme formu */}
      {formOpen && (
        <ProductForm
          initial={editing}
          onClose={() => setFormOpen(false)}
          onSaved={(message) => {
            setFormOpen(false);
            showToast(message);
            router.refresh();
          }}
        />
      )}

      {/* Onay diyaloğu */}
      {confirm && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
          role="alertdialog"
          aria-modal="true"
          aria-label={confirm.title}
        >
          <div className="w-full max-w-sm rounded-xl border border-zinc-800 bg-zinc-900 p-6 shadow-2xl shadow-black/50">
            <h2 className="text-lg font-bold text-zinc-100">{confirm.title}</h2>
            <p className="mt-2 text-sm text-zinc-400">{confirm.message}</p>
            <div className="mt-5 flex justify-end gap-2">
              <button
                type="button"
                disabled={confirmBusy}
                onClick={() => setConfirm(null)}
                className="rounded-md border border-zinc-700 px-4 py-2 text-sm font-medium text-zinc-300 transition hover:bg-zinc-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-500"
              >
                Vazgeç
              </button>
              <button
                type="button"
                disabled={confirmBusy}
                onClick={runConfirm}
                autoFocus
                className={`rounded-md px-4 py-2 text-sm font-semibold transition focus-visible:outline-none focus-visible:ring-2 disabled:cursor-not-allowed disabled:opacity-60 ${
                  confirm.destructive
                    ? "bg-red-600 text-white hover:bg-red-500 focus-visible:ring-red-400"
                    : "bg-amber-500 text-zinc-950 hover:bg-amber-400 focus-visible:ring-amber-300"
                }`}
              >
                {confirmBusy ? "İşleniyor…" : confirm.confirmLabel}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Toast */}
      {toast && (
        <div
          role="status"
          className={`fixed bottom-4 right-4 z-50 rounded-lg border px-4 py-3 text-sm font-medium shadow-xl shadow-black/40 ${
            toast.ok
              ? "border-emerald-500/40 bg-zinc-900 text-emerald-400"
              : "border-red-500/40 bg-zinc-900 text-red-400"
          }`}
        >
          {toast.text}
        </div>
      )}
    </div>
  );
}

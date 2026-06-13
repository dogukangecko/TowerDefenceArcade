import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

// Sabit slug id'ler: oyunun gömülü default_catalog.json'ı ile birebir aynı.
// Sahiplik oyunda item id'siyle saklanır; çevrimdışı (gömülü katalog) alınan
// bir item çevrimiçi katalogda da AYNI id'yle gelmeli ki sahiplik korunsun.
// Panelden eklenen YENİ ürünler cuid almaya devam eder (sorun değil — onlar
// yalnız canlı katalogdan gelir).
const items = [
  {
    id: "baslangic-kesesi",
    name: "Başlangıç Kesesi",
    desc: "Her tura +50 başlangıç altınıyla başla.",
    icon: "💰",
    priceGold: 120,
    effectType: "startGold",
    effectValue: 50,
    premium: false,
    status: "published",
  },
  {
    id: "keskin-uclar",
    name: "Keskin Uçlar",
    desc: "Tüm kulelerin hasarı %10 artar.",
    icon: "🗡️",
    priceGold: 300,
    effectType: "towerDamage",
    effectValue: 0.1,
    premium: false,
    status: "published",
  },
  {
    id: "tas-duvarlar",
    name: "Taş Duvarlar",
    desc: "Her tura +2 ekstra canla başla.",
    icon: "🧱",
    priceGold: 250,
    effectType: "extraLives",
    effectValue: 2,
    premium: false,
    status: "published",
  },
  {
    id: "buyuk-kese",
    name: "Büyük Kese",
    desc: "Her tura +100 başlangıç altınıyla başla.",
    icon: "👑",
    priceGold: 400,
    effectType: "startGold",
    effectValue: 100,
    premium: true,
    status: "draft",
  },
  {
    id: "savas-sanati",
    name: "Savaş Sanatı",
    desc: "Tüm kulelerin hasarı %20 artar.",
    icon: "⚔️",
    priceGold: 700,
    effectType: "towerDamage",
    effectValue: 0.2,
    premium: true,
    status: "draft",
  },
  {
    id: "kale-takviyesi",
    name: "Kale Takviyesi",
    desc: "Her tura +5 ekstra canla başla.",
    icon: "🏰",
    priceGold: 600,
    effectType: "extraLives",
    effectValue: 5,
    premium: true,
    status: "draft",
  },
  // Faz 2 — görünüm içerikleri (skin setleri + tema). Etki yok: effectType "none".
  {
    id: "buz-seti",
    name: "Buz Seti",
    desc: "Kuleler buzul mavisine bürünür.",
    icon: "❄️",
    priceGold: 400,
    effectType: "none",
    effectValue: 0,
    premium: true,
    status: "published",
    kind: "skin",
    assetKey: "buz",
  },
  {
    id: "kor-seti",
    name: "Kor Seti",
    desc: "Kuleler kor kızılıyla alev alır.",
    icon: "🔥",
    priceGold: 400,
    effectType: "none",
    effectValue: 0,
    premium: true,
    status: "published",
    kind: "skin",
    assetKey: "kor",
  },
  {
    id: "zehir-seti",
    name: "Zehir Seti",
    desc: "Kuleler zehir yeşiline döner.",
    icon: "☠️",
    priceGold: 400,
    effectType: "none",
    effectValue: 0,
    premium: true,
    status: "published",
    kind: "skin",
    assetKey: "zehir",
  },
  {
    id: "sonbahar-temasi",
    name: "Sonbahar Teması",
    desc: "Harita sıcak sonbahar tonlarına bürünür.",
    icon: "🍂",
    priceGold: 300,
    effectType: "none",
    effectValue: 0,
    premium: false,
    status: "published",
    kind: "theme",
    assetKey: "sonbahar",
  },
];

async function main() {
  for (const item of items) {
    // Eski tohumlardan kalmış aynı adlı-ama-cuid'li satırları temizle
    // (tohum item'ı tek doğru kimlikle, slug id'yle yaşamalı).
    await prisma.product.deleteMany({
      where: { name: item.name, id: { not: item.id } },
    });
    await prisma.product.upsert({
      where: { id: item.id },
      update: item,
      create: item,
    });
  }

  await prisma.catalogState.upsert({
    where: { id: 1 },
    update: {},
    create: { id: 1, version: 0 },
  });

  const count = await prisma.product.count();
  console.log(`Seed tamam: ${count} ürün, CatalogState hazır.`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());

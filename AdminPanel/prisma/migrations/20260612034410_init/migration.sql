-- CreateTable
CREATE TABLE "Product" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL,
    "desc" TEXT NOT NULL DEFAULT '',
    "icon" TEXT NOT NULL DEFAULT '⚔️',
    "priceGold" INTEGER NOT NULL,
    "effectType" TEXT NOT NULL,
    "effectValue" REAL NOT NULL,
    "premium" BOOLEAN NOT NULL DEFAULT false,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "storeProductId" TEXT,
    "priceTier" INTEGER
);

-- CreateTable
CREATE TABLE "CatalogState" (
    "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT DEFAULT 1,
    "version" INTEGER NOT NULL DEFAULT 0,
    "publishedAt" DATETIME NOT NULL
);

-- RedefineTables
PRAGMA defer_foreign_keys=ON;
PRAGMA foreign_keys=OFF;
CREATE TABLE "new_Product" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL,
    "desc" TEXT NOT NULL DEFAULT '',
    "icon" TEXT NOT NULL DEFAULT '⚔️',
    "priceGold" INTEGER NOT NULL,
    "effectType" TEXT NOT NULL,
    "effectValue" REAL NOT NULL,
    "kind" TEXT NOT NULL DEFAULT 'item',
    "assetKey" TEXT,
    "premium" BOOLEAN NOT NULL DEFAULT false,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "createdAt" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" DATETIME NOT NULL,
    "storeProductId" TEXT,
    "priceTier" INTEGER
);
INSERT INTO "new_Product" ("createdAt", "desc", "effectType", "effectValue", "icon", "id", "name", "premium", "priceGold", "priceTier", "status", "storeProductId", "updatedAt") SELECT "createdAt", "desc", "effectType", "effectValue", "icon", "id", "name", "premium", "priceGold", "priceTier", "status", "storeProductId", "updatedAt" FROM "Product";
DROP TABLE "Product";
ALTER TABLE "new_Product" RENAME TO "Product";
PRAGMA foreign_keys=ON;
PRAGMA defer_foreign_keys=OFF;

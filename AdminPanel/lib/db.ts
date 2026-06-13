import { PrismaClient } from "@prisma/client";

/**
 * PrismaClient singleton'ı. Dev'de hot reload her modül yeniden
 * yüklendiğinde yeni bağlantı açmasın diye globalThis'te önbellenir.
 */
const globalForPrisma = globalThis as unknown as { prisma?: PrismaClient };

export const prisma = globalForPrisma.prisma ?? new PrismaClient();

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}

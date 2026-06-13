/**
 * Her test worker'ında, test dosyaları import edilmeden ÖNCE koşar.
 * lib/db.ts ve lib/session-options.ts env'i import anında okuduğu için
 * DATABASE_URL/SESSION_SECRET burada ayarlanır.
 * SQLite göreli yolu Prisma şema dizinine göre çözülür → prisma/test.db.
 */
process.env.DATABASE_URL = "file:./test.db";
process.env.SESSION_SECRET = "test-secret-test-secret-test-secret-1234";
process.env.ADMIN_PASSWORD = "test-parola";

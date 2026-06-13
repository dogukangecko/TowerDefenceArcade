import { execSync } from "node:child_process";
import { rmSync } from "node:fs";
import path from "node:path";

const root = path.resolve(__dirname, "..");
const testDb = path.join(root, "prisma", "test.db");

/** Test veritabanını şemayla oluşturur (file:./test.db → prisma/test.db). */
export function setup() {
  rmSync(testDb, { force: true });
  execSync("npx prisma db push --skip-generate", {
    cwd: root,
    env: { ...process.env, DATABASE_URL: "file:./test.db" },
    stdio: "pipe",
  });
}

export function teardown() {
  rmSync(testDb, { force: true });
  rmSync(`${testDb}-journal`, { force: true });
}

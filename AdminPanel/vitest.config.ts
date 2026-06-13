import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    globalSetup: ["./tests/global-setup.ts"],
    setupFiles: ["./tests/setup-env.ts"],
    // Paylaşılan SQLite test veritabanı — dosyalar sırayla koşsun.
    fileParallelism: false,
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname),
    },
  },
});

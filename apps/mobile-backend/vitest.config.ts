import { defineConfig } from "vitest/config"

export default defineConfig({
  test: {
    // All test files share a single real mongodb-memory-server instance
    // (one globalSetup for the whole run - see tests/setup/globalSetup.ts),
    // and tests/setup/testSetup.ts's afterEach wipes ALL collections, not
    // just the ones the current file touched. With vitest's default
    // file-level parallelism, two files running concurrently can wipe out
    // each other's in-flight fixtures mid-test, producing flaky
    // "expected 1, got 0" failures. Running files sequentially keeps every
    // file's own beforeEach/afterEach cycle isolated against the shared DB.
    fileParallelism: false,
    globalSetup: ["tests/setup/globalSetup.ts"],
    setupFiles: ["tests/setup/testSetup.ts"],
    // Dummy secrets so importing src/config/env.ts doesn't throw in tests —
    // nothing ever actually connects to Redis. MONGODB_URI is intentionally
    // NOT set here: tests/setup/testSetup.ts sets it (from the in-memory
    // Mongo instance started in globalSetup.ts) before any test file's own
    // imports run.
    env: {
      JWT_SECRET: "test-jwt-secret",
      REFRESH_SECRET: "test-refresh-secret",
      REDIS_URL: "redis://localhost:6379/0",
      BREVO_API_KEY: "test-brevo-api-key",
      BREVO_SENDER_EMAIL: "test@example.com",
    },
    reporters: ["default", "junit"],
    outputFile: {
      junit: "reports/junit.xml",
    },
    coverage: {
      provider: "v8",
      reporter: ["text", "html", "json"],
      reportsDirectory: "coverage",
      // Real measured baseline was 62.9% stmts/lines, 72.1% branch, 54.5%
      // funcs (config/queues/realtime/services intentionally uncovered —
      // they need real Redis/replica-set Mongo/Firebase/S3, see
      // docs/testing/README.md). Threshold set a few points below that so
      // this is a genuine regression gate, not a number that flakes on
      // every run, and not an aspirational number nothing meets yet.
      thresholds: {
        lines: 58,
        statements: 58,
        functions: 48,
        branches: 65,
      },
    },
  },
})

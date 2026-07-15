# Integration tests

Scope: multi-module behavior exercised against a **real in-memory MongoDB**
(via `mongodb-memory-server`, wired up in `tests/setup/globalSetup.ts`).

- No HTTP layer here — import services/models/modules directly and drive them
  through Mongoose, not through Express routes or supertest.
- Use this suite for things like: a controller-adjacent service function that
  reads/writes multiple collections, cross-collection consistency, Mongoose
  hooks/middleware, aggregation pipelines, etc.
- Use `tests/factories` and `tests/fixtures` to build input data, and
  `tests/setup/testSetup.ts` (wired as a global `setupFiles` entry) takes care
  of clearing collections between tests so state doesn't leak across files.
- Run with `pnpm test:integration`.

No test files exist here yet — this README exists to record the intended
scope before feature tests are written.

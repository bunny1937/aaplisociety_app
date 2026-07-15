# API tests

Scope: HTTP-level tests driven through `supertest` against the app returned
by `createApp()` (see `tests/helpers/app.ts`), running the full Express
middleware/router stack without starting a real server, DB connection isn't
required by the app itself but most routes will need one — use the in-memory
Mongo from `tests/setup/globalSetup.ts`.

- Use `tests/helpers/auth.ts` (`bearerToken`) to mint a JWT and send it as
  `Authorization: Bearer <token>` — the auth middleware also accepts an
  httpOnly `token` cookie, but the Bearer header is simpler in supertest.
- Use `tests/mocks` to stub `sendFcmToUser` and the storage/S3 functions so
  no test ever calls real Firebase or AWS.
- Run with `pnpm test:api`.

No endpoint tests exist here yet — this README exists to record the intended
scope before feature tests are written.

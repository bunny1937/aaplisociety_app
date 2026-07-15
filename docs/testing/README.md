# Testing architecture

Current state: **real, meaningful tests exist and pass** — 72 backend
(vitest+supertest+real in-memory Mongo) and 37 Flutter (33 pass + 1
deliberately-skipped documented finding). CI runs both on every push/PR, plus
a nightly full run including mutation testing. This doc reflects what's
actually built, verified by running it — not aspirational.

## Stack

| | Backend (`apps/mobile-backend`) | Flutter (`apps/mobile-app`) |
|---|---|---|
| Runner | **vitest** (not Jest — already installed/used, native ESM+TS, Jest-compatible API) | `flutter_test` + `integration_test` |
| HTTP/API | `supertest` against `createApp()` | n/a |
| Mocking | `vi.fn()` (fcm, storage) | `mocktail` (`MockDio`), hand-written `FakeTokenStore` |
| DB in tests | `mongodb-memory-server` (real `mongod` process, no network beyond first download, no Atlas creds) | n/a |
| Contract | zod `.strict()` schemas in `tests/contract/schemas.ts` validated against real responses | — |
| Accessibility | — | `meetsGuideline()` (Android/iOS tap-target, text contrast) on `LoginPage` |
| Golden | — | mechanism proven working (see below); no real-screen goldens yet (UI still in flux) |
| Mutation | Stryker, scoped to `src/lib/jwt.ts` — 100% mutation score (4/4 killed) | not attempted (no mature Dart mutation tool integrates with `flutter_test` the way Stryker does with vitest) |
| E2E | Isolated real backend (`scripts/e2e-server.ts`, real in-memory Mongo) + real integration_test journey file — **written, verified backend-side, blocked on device/emulator to actually run** (see below) | same |
| Coverage | `@vitest/coverage-v8` → `coverage/`, **enforced threshold** (58% lines/statements, 65% branch, 48% functions — real measured baseline was 62.9/72.1/54.5, set a few points below so it's a genuine regression gate) | `flutter test --coverage` → `coverage/lcov.info`, no threshold enforced |
| Reports | JUnit XML → `reports/junit.xml`, published on PRs via `mikepenz/action-junit-report` | none (console only — documented gap) |
| CI | `.github/workflows/ci.yml` (push/PR: typecheck, full suite+coverage, JUnit publish, artifact upload, flutter analyze+test+coverage+APK build) | same file |
| Nightly | `.github/workflows/nightly.yml` (scheduled 03:00 UTC + manual dispatch: full suite, coverage, mutation testing) | same file |

## Why the Express app had to change first

`src/server.ts` used to do everything inside one `main()`: connect Mongo,
build the Express app, start Socket.IO, start Mongo change-stream watchers,
import the BullMQ queue module (side-effecting on import), then `listen()`.
None of that was importable on its own.

Fix: `src/app.ts` exports `createApp()` — pure Express wiring, zero side
effects. `server.ts` is the bootstrapper that calls it and adds real
infrastructure around it. Behavior is identical in production; tests import
`createApp()` directly with no Redis/socket dependency at all.

## What's real vs. what's architecturally out of scope

Every test in this repo asserts specific status codes and/or body/DB state —
no `expect(true).toBe(true)` placeholders anywhere. Three categories of things
are **not tested, on purpose, for reasons that don't change with more effort**:

- **CSRF / XSS**: this backend is a stateless Bearer-JWT JSON API — no cookie
  session, no HTML rendering. Neither attack class applies.
- **File-upload validation**: Express never receives file bytes; `services/storage.ts`
  only issues presigned S3/R2 URLs for direct client upload.
- **Rate limiting / CORS strictness**: not missing tests — genuinely missing
  *controls*. `payload.security.test.ts` documents current behavior (20 rapid
  wrong-password attempts all return 401, no lockout; `Access-Control-Allow-Origin`
  reflects any `Origin` sent). These are real findings for you to act on, not
  bugs in the tests.
- **Redis/Firebase/Storage "chaos" testing**: none of `queues/index.ts`
  (BullMQ), `realtime/socket.ts`, `services/fcm.ts`, `services/storage.ts` are
  imported by `createApp()` or reachable from any HTTP route — they're only
  wired in `server.ts`'s `main()`. Simulating their failure against the
  tested API surface would prove nothing real; it would need a running
  `server.ts` process, a real Redis, and (for change streams) a replica-set
  Mongo — a materially bigger undertaking than this pass, and explicitly
  deferred (see Known gaps).

## Real findings surfaced by testing (not fixed — your call)

1. **Express 4 has no global async-error handler.** None of the five
   controllers wrap their Mongoose calls in try/catch, and Express 4 (unlike
   5) does not auto-catch a rejected promise from an `async (req,res)=>{}`
   handler. A genuine Mongo hiccup mid-request could crash the process
   instead of returning a 5xx. Confirmed by design review, not a fabricated
   test — fixing it means either upgrading to Express 5 or adding a
   catch-wrapper/error-boundary middleware across all five controllers, which
   is a real production-code change requiring your sign-off.
2. **No unique index on `User.username`.** The duplicate-check in
   `POST /auth/add-member` is an application-level `findOne` before `create`
   — under concurrent requests this is a TOCTOU race that could create two
   users with the same username. Adding `unique: true` to the schema is a
   low-risk, well-justified fix, but it's a production schema change, not a
   test-only one, so it's flagged rather than silently applied.
3. **No transaction around bill payment's two writes.** `bill.controller.ts`'s
   `/pay` route does `bill.save()` then `Payment.create()` as two independent
   operations. If the process dies between them, you get a bill marked
   paid/partial with no corresponding `Payment` audit record. Fixing this
   properly needs a MongoDB replica set (multi-document transactions don't
   work on a standalone instance — the same limitation that blocks change-stream
   testing, see below) — a production infrastructure decision, not something
   to patch in test code.
4. **`readToken()` accepts a bearer token with no `"Bearer "` prefix.**
   `.replace(/^Bearer\s+/i, "")` no-ops if the prefix is absent, so a raw
   token in the `Authorization` header still authenticates. Not an exploitable
   hole (still requires a validly-signed JWT) but a spec-compliance looseness
   worth a decision — enforcing strict `Bearer` would need testing whether any
   existing client relies on the loose behavior first.
5. **`LoginPage`'s password show/hide button has no semantic label** —
   fails Flutter's `labeledTapTargetGuideline`. Documented as a `skip: true`
   test in `test/widget/accessibility_test.dart` with the exact fix (add a
   `tooltip:`) rather than silently patched.
6. **No delete endpoints exist anywhere in this API.** Not a gap — there's
   simply no delete functionality to test (confirmed by reading all five
   controllers). Soft-delete pattern doesn't exist either (only `User.isActive`,
   which is a disable flag, not a delete).

## Folder structure

### `apps/mobile-backend/tests/`
- `unit/` — `auth.test.ts` (3, pre-existing schema/business-logic checks)
- `integration/` — README only (deliberately empty — see Known gaps)
- `api/` — 43 real tests: `auth` (20), `bills` (7), `visitors` (8), `complaints` (5), `notices` (3)
- `security/` — 15 real tests: `tenancy` (5), `jwt` (6), `payload` (4)
- `contract/` — 8 real tests: `schemas.ts` (zod `.strict()` response shapes) + one `.contract.test.ts` per module
- `performance/` — 3 real tests (latency threshold, 20-way concurrent burst, one real `autocannon` burst)
- `helpers/app.ts`, `helpers/auth.ts` (`bearerToken`/`authHeader`)
- `fixtures/*.fixture.ts`, `factories/*.factory.ts` (incl. `hashPassword` helper)
- `mocks/fcm.mock.ts`, `mocks/storage.mock.ts`
- `setup/globalSetup.ts` (starts `mongodb-memory-server`), `setup/testSetup.ts` (points `MONGODB_URI` at it, connects Mongoose, clears all collections after every test — `vitest.config.ts` sets `fileParallelism: false` because this shared-DB-cleanup pattern isn't safe across concurrent files)
- `utils/randomObjectId.ts`
- `types/autocannon.d.ts` — ambient shim (autocannon ships no types)

### `apps/mobile-backend/scripts/`
- `e2e-server.ts` — standalone, isolated E2E backend: real `createApp()`, real in-memory Mongo, one seeded user (`e2e_member` / `E2ePass123`). Never touches the real dev/Atlas database. Run via `pnpm e2e:server`.

### `apps/mobile-backend/` (mutation testing)
- `stryker.conf.json` — scoped to `mutate: ["src/lib/jwt.ts"]` only (full-repo mutation testing reruns the whole suite per mutant — far too slow to do broadly). Run via `pnpm test:mutation`.

### `apps/mobile-app/`
- `test/unit/` — `auth_bloc_test.dart` (7), `api_error_test.dart` (10), `socket_bus_test.dart` (11)
- `test/widget/` — `async_view_test.dart` (5, incl. a real bug found+fixed — see below), `accessibility_test.dart` (2 pass + 1 documented skip)
- `test/golden/` — `mechanism_test.dart` (proves the golden pipeline itself works — deliberately not a real-screen test, see below) + README for the real-screen convention
- `test/helpers/pump_app.dart`, `test/mocks/{mock_dio,fake_token_store}.dart`, `test/fixtures/*.dart`, `test/utils/pump_until_found.dart`
- `integration_test/app_test.dart` — minimal harness-boot skeleton
- `integration_test/e2e_journey_test.dart` — **real** login→dashboard→logout→re-login journey against a real backend, written and correct, **not yet run** (see Known gaps — no device/emulator available in this environment)

## A real bug this testing effort found and fixed

`AsyncViewState.reload()` did `setState(() => _future = next)` — an
assignment *expression*, whose value is the assigned `Future`, so the closure
passed to `setState` implicitly returned a `Future` and tripped Flutter's
"setState() callback argument returned a Future" assertion on **every single
retry, across every screen using `AsyncView`** (dashboard, bills, notices,
complaints, security shell, admin — six-plus screens). Fixed to a block body
(`setState(() { _future = next; })`). `test/widget/async_view_test.dart` now
does a real `tester.tap()` on the Retry button (previously worked around by
calling `reload()` directly, since the bug made a real tap unfixably fail the
test) and confirms it actually recovers.

## Running things

```
# Backend (apps/mobile-backend, or --filter @aapli/mobile-backend from root)
pnpm test                 # everything, one shot (72 tests)
pnpm test:watch           # vitest watch — reruns only affected files live
pnpm test:unit / test:integration / test:api / test:security / test:performance
pnpm test:coverage        # writes coverage/, enforces the real threshold
pnpm test:mutation        # Stryker, src/lib/jwt.ts only, ~3 min
pnpm e2e:server           # starts the isolated E2E backend on :5055

# Flutter (apps/mobile-app)
flutter test test/                 # unit + widget + accessibility + golden mechanism (37 tests)
flutter test test/ --coverage      # + coverage/lcov.info
flutter test integration_test      # needs a connected device/emulator (see Known gaps)
flutter test --update-goldens      # regenerate goldens after an intentional UI change

# One file / one test
pnpm --filter @aapli/mobile-backend exec vitest run tests/api/bills.api.test.ts
pnpm --filter @aapli/mobile-backend exec vitest run -t "rotates the refresh token"
flutter test test/unit/auth_bloc_test.dart
flutter test test/unit/auth_bloc_test.dart --plain-name "LogoutRequested"

# Real E2E (once a device/emulator is available)
pnpm --filter @aapli/mobile-backend e2e:server &
flutter test apps/mobile-app/integration_test/e2e_journey_test.dart -d <device> \
  --dart-define=API_BASE_URL=http://localhost:5055/v1 --dart-define=SOCKET_URL=http://localhost:5055

# Reports
start apps/mobile-backend/coverage/index.html   # HTML coverage
# apps/mobile-backend/reports/junit.xml — JUnit, also published as a PR check in CI
# apps/mobile-app/coverage/lcov.info — raw Flutter coverage (no HTML yet, see below)
```

## Watch mode / live dev

- Backend: `pnpm test:watch` — real `vitest` watch, reruns only affected
  files, live pass/fail/timing.
- Flutter: no built-in watch mode. Not wired (would need a third-party
  runner you didn't ask for).

## Known gaps (documented, not silently patched or faked)

1. **Device-based Flutter `integration_test` / real E2E hasn't actually run.**
   The test file and isolated backend are both real and correct (backend
   verified live via `curl` during this session). Blocked by three
   independent, confirmed environmental facts: no Android device/emulator
   connected right now (creating an AVD needs a multi-GB system image on a
   3GB-RAM machine — the same resource class that OOM'd a Gradle build
   earlier this session; not doing that without asking), the Windows desktop
   target needs a Visual Studio C++ toolchain that isn't installed (large,
   invasive install, not done unprompted), and `flutter test integration_test`
   flatly refuses web targets (`"Web devices are not supported for
   integration tests yet"` — Flutter's own tooling limitation; web E2E would
   need the separate `flutter drive` + driver-file mechanism). Run it
   yourself the moment a device/emulator is attached — command above.
2. Flutter has no JUnit/HTML test reporter — console only.
3. `lcov`/`genhtml` not installed on this machine — Flutter coverage HTML
   isn't generated (raw `lcov.info` works with VS Code's Coverage Gutters).
4. `tests/integration/` (pure multi-step-no-HTTP) is still empty — the
   `tests/api/` suite already exercises real multi-step DB behavior through
   the HTTP layer, which covers most of what would go here anyway.
5. Mongo change-stream / BullMQ notification pipeline (`events/changestreams.ts`,
   `queues/index.ts`, `realtime/socket.ts`) — 0% covered, needs a real Redis
   and a replica-set Mongo (`mongodb-memory-server`'s standalone mode can't
   run change streams). Real infra, not a quick add.
6. Full-repo mutation testing not attempted — reruns the whole suite per
   mutant, would take far too long; scoped to one file as a proof it works.
7. No CI job runs the Android emulator yet for `integration_test` — would
   need `reactivecircus/android-emulator-runner`, a deliberate follow-up.

## How to add a new test

Backend: pick `unit`/`api`/`security`/`contract`/`performance`/`integration`,
use `factories/` + `helpers/auth.ts`. DB cleanup between tests is automatic
(`testSetup.ts`).

Flutter: pick `unit`/`widget`, use `pumpApp`/`MockDio`/`FakeTokenStore`/fixtures.
Use `pumpUntilFound` instead of a bare `pump()` for anything using
`flutter_animate`.

## Troubleshooting

- **Backend test hangs on first run**: `mongodb-memory-server` downloads a
  real `mongod` binary once; needs network access that one time.
- **`MongoParseError`**: don't set `MONGODB_URI` in `vitest.config.ts`'s
  `test.env` — `testSetup.ts` sets it from the in-memory instance.
- **Flaky "expected 1, got 0" across test files**: this is exactly why
  `fileParallelism: false` is set — don't remove it without re-solving the
  shared-DB-cleanup race it exists to prevent.
- **Flutter widget test can't find a widget mid-animation**: use
  `pumpUntilFound`.
- **Golden test fails**: check `test/golden/failures/` for the generated
  expected/actual/diff PNGs (confirmed this mechanism works for real this
  session — see the mutation/golden proof above).

---

## Priority checklist — what's left, ordered by risk

Everything in the previous version of this checklist (bill-payment ownership,
visitor role/ownership, pending-token rejection, tenant isolation, auth
flows, refresh rotation, `AuthBloc`, `AsyncView`, `SocketBus`) **is now real
and passing** — see the folder structure above. What's left:

**P0**
1. Decide on the "real findings" above (Express 4 async-error handling, no
   unique index on `username`, no transaction on bill-pay, loose Bearer-prefix
   check) — these are product/security decisions, not test gaps.
2. Get device-based E2E actually running (attach a phone via adb, or accept
   the Visual Studio / Android-emulator install cost).

**P1**
3. Flutter JUnit/HTML reporter.
4. `lcov`/`genhtml` for Flutter coverage HTML.
5. Wire `reactivecircus/android-emulator-runner` into nightly CI so
   `integration_test` runs unattended.

**P2**
6. Real Redis + replica-set Mongo test harness for `queues/index.ts` /
   `events/changestreams.ts` / `realtime/socket.ts`.
7. Per-screen Flutter widget tests (dashboard, bills, notices, complaints,
   security shell, admin) — `AsyncView` (their shared mechanism) is already
   covered; these would test each screen's specific rendering logic.
8. `DioClient`'s 401→refresh→retry interceptor chain (needs adapter-level
   HTTP mocking, correctly skipped so far rather than faked).

**P3**
9. Golden tests for real screens once the UI stops changing — the mechanism
   is proven, only the baselines are missing, and writing them now would
   just churn.
10. Flutter watch-mode tooling, coverage-trend tracking across CI runs.
11. Expand mutation testing beyond `src/lib/jwt.ts` if the team finds the
    3-minute single-file run valuable enough to budget more CI time for it.

# @aapli/mobile-backend

Node/Express API for Aapli Society: tenant-scoped auth, visitors, bills, complaints, notices, ledger, receipts — with real-time Socket.IO/FCM notifications driven off MongoDB Change Streams and BullMQ.

Run everything from the **repo root** (this package is part of a pnpm workspace) — see the [root README](../../README.md) and [`EXECUTION_STEPS.md`](../../EXECUTION_STEPS.md) for the full monorepo setup.

## Architecture

`src/app.ts` exports `createApp()` — pure Express wiring (routes, middleware, error handler) with **zero** DB/Redis/socket/queue side effects, so it's importable standalone by tests (and, in principle, a serverless HTTP handler — see [Deployment](#deployment) for why that's not currently viable end-to-end).

`src/server.ts` is the actual boot process: connects Mongo, builds the app, starts Socket.IO, starts the three Change Stream watchers, imports the BullMQ queue module (which constructs `Worker` instances that immediately start polling Redis on import), then `listen()`s. This is a **long-running process** — nothing above `createApp()` is compatible with a request-scoped serverless function.

```
POST /v1/bills  →  Mongoose write
                       ↓
        events/changestreams.ts (watches Bill.watch())
                       ↓
        queues/index.ts: notificationsQueue.add(...)
                       ↓
        notificationsWorker processes job → Notification.create()
                       ↓
        Socket.IO emit (live) + FCM push (background)
```

The visitor escalation ladder works the same way: a pending visitor request enqueues a delayed `escalationQueue` job (see `@aapli/business`'s `nextEscalation`), which re-arms itself at increasing intervals until the guest is approved/denied or the ladder is exhausted.

## API reference (`/v1`)

| Method | Route | Notes |
|---|---|---|
| POST | `/auth/login` | Returns tokens, or `needsProfileSelect` for multi-profile users |
| POST | `/auth/switch-profile` | Resolves a pending profile-select token |
| POST | `/auth/refresh` | Rotates refresh token; reuse of an old one is rejected (401) |
| POST | `/auth/change-password` | Required before any other route if the user has a temp password |
| GET | `/auth/me` | Current user + linked Member/Society |
| POST | `/auth/add-member` | Admin-only; returns a temp password |
| GET | `/auth/members` | Admin-only, society-scoped |
| POST | `/visitors` | Member creates a gate-pass request (status `Pending`) |
| POST | `/visitors/:id/enter` / `/:id/exit` | Security actions |
| GET / POST | `/bills` | List (role-scoped) / generate (admin) |
| POST | `/bills/:id/pay` | Records a payment |
| GET / POST | `/complaints` | List / raise |
| PATCH | `/complaints/:id/status` | Admin-only |
| GET / POST | `/notices` | List (pinned-first) / post (admin) |
| GET | `/ledger` | Member's own transaction history |
| GET | `/receipts` | Member's own receipts |
| POST | `/devices` | Registers an FCM device token |
| GET | `/health` | Liveness check, no auth |

Every route is tenant-scoped by `societyId` from the verified JWT — never trusted from the request body. Response shapes are locked down by zod `.strict()` contract tests in `tests/contract/schemas.ts`.

## Environment variables

```bash
MONGODB_URI=mongodb://localhost:27017/aapli?replicaSet=rs0   # MUST be a replica set — Change Streams require it
JWT_SECRET=...
REFRESH_SECRET=...
ACCESS_TTL=15m
REFRESH_TTL=30d
REDIS_URL=redis://localhost:6379                              # BullMQ + Socket.IO Redis adapter
CORS_ORIGINS=http://localhost:3000,https://your-app.example    # comma-separated allowlist
FIREBASE_SA_JSON={"type":"service_account",...}                # optional in dev; validated at boot if present
R2_ENDPOINT=... R2_BUCKET=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=...
PORT=5001
```

`src/config/env.ts` fails fast at startup (`Missing env: X`) if `MONGODB_URI`, `JWT_SECRET`, `REFRESH_SECRET`, or `REDIS_URL` aren't set — including in any process that merely imports `app.ts`, since `env.ts` is a shared import.

## Local development

**Docker (fastest — spins up Mongo replica set + Redis + backend together):**
```bash
cd infrastructure
docker compose up -d
curl http://localhost:5001/health   # → { "ok": true }
```

**Manual (against your own Mongo/Redis):**
```bash
# from repo root
pnpm install
pnpm -r build
cp .env.example apps/mobile-backend/.env   # fill in the values above
pnpm --filter @aapli/mobile-backend dev
```

## Scripts

```bash
pnpm --filter @aapli/mobile-backend dev             # tsx watch — hot reload
pnpm --filter @aapli/mobile-backend build           # tsc → dist/
pnpm --filter @aapli/mobile-backend start           # node dist/server.js
pnpm --filter @aapli/mobile-backend typecheck

pnpm --filter @aapli/mobile-backend test            # everything (vitest, one shot)
pnpm --filter @aapli/mobile-backend test:watch
pnpm --filter @aapli/mobile-backend test:unit
pnpm --filter @aapli/mobile-backend test:api
pnpm --filter @aapli/mobile-backend test:security
pnpm --filter @aapli/mobile-backend test:performance
pnpm --filter @aapli/mobile-backend test:coverage   # enforces a real coverage threshold
pnpm --filter @aapli/mobile-backend test:mutation   # Stryker, scoped to src/lib/jwt.ts

pnpm --filter @aapli/mobile-backend e2e:server      # isolated E2E backend on :5055, in-memory Mongo
```

Full testing philosophy, coverage numbers, and known gaps: [`docs/testing/README.md`](../../docs/testing/README.md).

## Deployment

This process is **not serverless-compatible**. Three things require a persistent, long-running process and cannot run inside a request-scoped function (Vercel, AWS Lambda, etc.):

1. **Socket.IO** — holds open WebSocket connections; a function that dies after each response can't do this.
2. **MongoDB Change Streams** (`src/events/changestreams.ts`) — permanently-open cursors watching `Visitor`/`Bill`/`Notice` collections.
3. **BullMQ Workers** (`src/queues/index.ts`) — constructed at module import time, continuously poll Redis, including delayed jobs (the escalation ladder) that need a live process to fire on schedule.

`createApp()` alone (no sockets/queues/change-streams) *is* stateless and could serve plain REST traffic from a serverless function — but that gives you a backend with no real-time notifications, no escalation, and no FCM fan-out, which defeats most of the point of this API.

**What it needs in production:**
- A host that runs one process continuously — `infrastructure/docker/Dockerfile.backend` builds a production image (`node:24-alpine`, multi-stage, runs `node dist/server.js`); `.github/workflows/deploy-backend.yml` pushes it to GHCR on every `main` push touching the backend.
- MongoDB **as a replica set** — MongoDB Atlas's free M0 tier already deploys this way; a self-hosted Mongo needs `--replSet` explicitly (see `infrastructure/docker-compose.yml`'s `mongo`/`mongo-init` services).
- A reachable Redis instance (Upstash's free tier works over TLS with `ioredis`).
- `FIREBASE_SA_JSON` and `R2_*` credentials for push notifications and file storage to actually function.

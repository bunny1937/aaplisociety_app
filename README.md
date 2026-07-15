# Aapli Society — Multi-tenant Society Management SaaS

A fixed & revamped implementation of the Aapli Society platform, built as a pnpm + Turbo monorepo: a Flutter client (Members, Security, Admin) backed by a Node/Express/MongoDB/Socket.IO/BullMQ API with tenant-scoped JWT auth and real-time notifications.

## What's inside

```
aapli-society/
  apps/
    mobile-app/        Flutter app (Members, Security, Admin) - modern UI, motion, haptics, dark mode
    mobile-backend/     Node + Express + MongoDB + Socket.IO + BullMQ API (port 5001, /v1) — see apps/mobile-backend/README.md
  packages/
    shared-constants/   roles, visitor/bill status, notification types, socket rooms
    shared-types/       DTOs and JWT claim types
    shared-validation/  zod request schemas
    shared-business/    billing engine + visitor escalation ladder
  infrastructure/       Dockerfile, docker-compose (mongo replica set + redis + backend)
  .github/workflows/    CI + backend deploy
```

## Roles
SuperAdmin, Admin, Secretary, Accountant, Security, Member. Login routes each role to the right home:
- **Member** → dashboard, bills, visitors, notices, complaints, profile
- **Security** → guard dashboard, gate-pass scan, swipe approve/deny
- **Admin / Secretary / Accountant** → admin console (post notice, generate bill, add member, manage complaints)

## Tech stack

| Layer | Tech |
|---|---|
| Mobile client | Flutter (flutter_bloc, go_router, dio, hive, socket_io_client, firebase_messaging/remote_config) |
| Backend API | Node 20+, Express 4, TypeScript (strict, NodeNext ESM) |
| Database | MongoDB (Mongoose) — **must be a replica set**, Change Streams depend on it |
| Real-time | Socket.IO (+ Redis adapter for horizontal scaling) |
| Background jobs | BullMQ (Redis) — notification fan-out + visitor escalation ladder |
| Auth | JWT (15m access + rotating 30d refresh), bcrypt password hashing |
| Push | Firebase Cloud Messaging |
| File storage | S3-compatible (Cloudflare R2) via presigned URLs |
| Monorepo tooling | pnpm workspaces + Turborepo |

## Backend API (`/v1`)
| Area | Endpoints |
|------|-----------|
| Auth | `POST /auth/login`, `/auth/switch-profile`, `/auth/refresh`, `/auth/change-password`, `GET /auth/me` |
| Visitors | `POST /visitors`, `/visitors/:id/enter`, `/visitors/:id/exit` |
| Bills | `GET /bills`, `POST /bills` (admin), `POST /bills/:id/pay` |
| Complaints | `GET /complaints`, `POST /complaints`, `PATCH /complaints/:id/status` (admin) |
| Notices | `GET /notices`, `POST /notices` (admin) |
| Ledger / Receipts / Devices | `GET /ledger`, `GET /receipts`, `POST /devices` |

Every query is tenant-scoped by `societyId` taken from the verified JWT (never the request body). Change Streams → domain events → BullMQ → Socket.IO / FCM fan-out. Full endpoint-by-endpoint detail lives in [`apps/mobile-backend/README.md`](apps/mobile-backend/README.md).

## Two separate toolchains (important)
- **`apps/mobile-app`** is a **Flutter** project → needs the Flutter SDK (`flutter pub get`, `flutter run`). It is NOT a Node project; never run npm/pnpm inside it.
- **Everything else** (backend + shared packages) is **Node/TypeScript** → run `pnpm install` and `pnpm -r build` from the **repo root**.

See [`EXECUTION_STEPS.md`](EXECUTION_STEPS.md) for full setup instructions for both stacks.

## Testing

CI (`.github/workflows/ci.yml`) runs on every push/PR: backend build + typecheck + full test suite with coverage, and Flutter analyze + test + coverage + debug APK build. A nightly job additionally runs mutation testing.

Backend: 119 tests across unit/api/security/contract/performance suites, all real assertions against `mongodb-memory-server` (no mocked DB). See [`docs/testing/README.md`](docs/testing/README.md) for the full breakdown, known gaps, and how to add a new test.

```bash
pnpm test                 # backend: everything, one shot
pnpm test:coverage        # backend: writes coverage/, enforces threshold
flutter test test/        # flutter: unit + widget + accessibility + golden mechanism
```

## Deployment notes

The backend is a **persistent Node process**, not a serverless-friendly one: it holds open Socket.IO connections, runs BullMQ workers that poll Redis continuously, and watches MongoDB Change Streams for real-time notification fan-out. That rules out platforms built around short-lived request/response functions (e.g. Vercel) — it needs a host that keeps one process running (Render, Railway, Fly, a VM, etc.), plus:
- MongoDB deployed **as a replica set** (MongoDB Atlas free tier already is one — self-hosted Mongo needs `--replSet` explicitly, see `infrastructure/docker-compose.yml`)
- A reachable Redis instance (BullMQ + Socket.IO adapter)
- Firebase service-account JSON (FCM push) and R2/S3 credentials (file storage) as env vars

`infrastructure/Dockerfile.backend` builds a production image; `.github/workflows/deploy-backend.yml` pushes it to GHCR on every `main` push touching the backend.

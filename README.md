# Aapli Society - Multi-tenant Society Management SaaS

A fixed & revamped implementation of the Aapli Society platform, built as a pnpm + Turbo monorepo and aligned to the approved architecture (multi-tenant, role-based, real-time, Firebase Remote Config gating).

## What's inside

```
aapli-society/
  apps/
    mobile-app/        Flutter app (Members, Security, Admin) - modern UI, motion, haptics, dark mode
    mobile-backend/    Node + Express + MongoDB + Socket.IO + BullMQ API (port 5001, /v1)
    admin-web/         (optional) your existing Next.js admin portal - not required to run the mobile stack
  packages/
    shared-constants/  roles, visitor/bill status, notification types, socket rooms
    shared-types/      DTOs and JWT claim types
    shared-validation/ zod request schemas
    shared-business/   billing engine + visitor escalation ladder
  infrastructure/      Dockerfile, docker-compose (mongo replica set + redis + backend)
  .github/workflows/   CI + backend deploy
```

## Roles
SuperAdmin, Admin, Secretary, Accountant, Security, Member. Login routes each role to the right home:
- **Member** -> dashboard, bills, visitors, notices, complaints, profile
- **Security** -> guard dashboard, gate-pass scan, swipe approve/deny
- **Admin / Secretary / Accountant** -> admin console (post notice, generate bill, add member, manage complaints)

## Backend API (\`/v1\`)
| Area | Endpoints |
|------|-----------|
| Auth | \`POST /auth/login\`, \`/auth/switch-profile\`, \`/auth/refresh\`, \`/auth/change-password\`, \`GET /auth/me\` |
| Visitors | \`POST /visitors\`, \`/visitors/:id/enter\`, \`/visitors/:id/exit\` |
| Bills | \`GET /bills\`, \`POST /bills\` (admin), \`POST /bills/:id/pay\` |
| Complaints | \`GET /complaints\`, \`POST /complaints\`, \`PATCH /complaints/:id/status\` (admin) |
| Notices | \`GET /notices\`, \`POST /notices\` (admin) |

Every query is tenant-scoped by \`societyId\` taken from the verified JWT (never the request body). JWT: 15m access + rotating 30d refresh. Change Streams -> domain events -> BullMQ -> Socket.IO / FCM fan-out.

## Two separate toolchains (important)
- **\`apps/mobile-app\`** is a **Flutter** project -> needs the Flutter SDK (\`flutter pub get\`, \`flutter run\`). It is NOT a Node project; never run npm/pnpm inside it.
- **Everything else** (backend + shared packages) is **Node/TypeScript** -> run \`pnpm install\` and \`pnpm -r build\` from the **repo root**.

See EXECUTION_STEPS.md for full setup.

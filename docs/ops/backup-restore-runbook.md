# Backup & Restore Runbook

Covers the shared infrastructure both `apps/mobile-backend` (this repo) and
`aaplisoceity_web` (the Next.js app, separate repo) depend on: MongoDB,
Redis, and Cloudflare R2. Nothing here existed before this doc — there was
no backup/recovery procedure anywhere in either repo.

## 1. MongoDB (system of record — highest priority)

Both backends read/write the same MongoDB cluster. This is the only
datastore where data loss is unrecoverable without a backup.

**Configuration (one-time, in MongoDB Atlas):**
- Enable **Cloud Backup** on the cluster (Atlas UI → cluster → Backup).
  Use **Continuous Cloud Backup** if the plan tier supports it — it gives
  point-in-time recovery to any second in the last 24h–7 days (tier-
  dependent), not just daily snapshot granularity.
- Set a snapshot schedule: daily snapshots retained 7 days, weekly
  retained 4 weeks, monthly retained 12 months is a reasonable default —
  adjust retention to your actual compliance/cost needs.
- Confirm the cluster is a **replica set** (Atlas clusters always are —
  this is also enforced by a startup check in `apps/mobile-backend`, see
  `src/config/db.ts`'s `assertReplicaSet()`, which logs loudly if it isn't).
  A standalone/non-replica-set Mongo has no oplog for continuous backup
  *and* silently breaks every change-stream-driven notification in this app.

**Restore procedure:**
1. In Atlas, go to the cluster's **Backup** tab → pick a snapshot or a
   point-in-time target.
2. **Restore to a new cluster**, never in-place onto production — this
   lets you verify the restored data before cutting traffic over, and
   keeps the broken production cluster available for forensics if the
   incident needs investigating.
3. Point a scratch copy of `apps/mobile-backend` and `aaplisoceity_web` at
   the new cluster's connection string (`MONGODB_URI` / equivalent) and
   confirm:
   - `apps/mobile-backend` logs `[db] replica set confirmed` at startup
     (not the "NOT running as a replica set" warning).
   - A test write to `visitors`/`bills`/`notices` fires a change-stream
     event (watch the server logs for `[changestream] watching ...` at
     startup, then confirm a notification is created after a test write).
   - Spot-check row counts on `users`, `members`, `bills`, `transactions`
     against the last known-good snapshot's counts.
4. Only after verification: update the production `MONGODB_URI` in both
   apps' environment config to point at the restored cluster (or restore
   in-place if Atlas's restore-to-same-cluster path was used instead —
   confirm with Atlas support/docs for the exact mechanics of your plan tier).
5. Restart both backends so `assertReplicaSet()` and the change-stream
   watchers re-establish against the new connection.

**What a restore does NOT cover:** R2-stored files (tenant documents,
visitor photos) are referenced by key from Mongo docs but stored
separately — restoring Mongo without restoring/preserving R2 leaves those
keys pointing at files that may not exist. R2 has its own versioning (see
§3) — don't assume a Mongo restore alone makes the app whole again if R2
objects were also deleted/corrupted in the same incident.

## 2. Redis (queues, socket adapter, cache — not a system of record)

Redis in this stack is used for BullMQ job queues (`apps/mobile-backend`),
the Socket.IO adapter (both apps, see `lib/socket-server.js` in the web
app), and caching (`lib/cache.js` in the web app, matching mobile's
`config/redis.js`). Nothing stored in Redis is the only copy of anything —
it's safe to treat as ephemeral and not back up.

**What a Redis outage/data-loss actually costs:**
- **Queued-but-not-yet-processed BullMQ jobs are lost** — e.g. an
  escalation timer mid-countdown, or a notification job that hadn't run
  yet. The underlying domain event (the Mongo write that triggered it) is
  not lost, but the notification for it won't fire. There is currently no
  replay mechanism for this — a lost queue job is just lost.
- Socket.IO adapter loss just means realtime events won't fan out across
  instances until Redis reconnects (both apps' adapters degrade to
  single-instance behavior automatically, they don't crash).
- Cache loss just means the next read is a cache miss — no correctness
  impact.

**Recovery:** provision a fresh Redis instance (managed Redis — e.g.
Upstash, Redis Cloud, or Atlas's own Redis offering — provisioning is
outside this doc's scope since it's plan/vendor-specific), point
`REDIS_URL` at it in both apps, restart. No data migration needed.

## 3. Cloudflare R2 (tenant documents, visitor photos)

**Configuration:**
- Enable **bucket versioning** in the R2 dashboard so an accidental
  overwrite/delete of an object (e.g. a bad re-upload) is recoverable —
  R2 supports S3-compatible versioning.
- Set a lifecycle rule to expire noncurrent (old) versions after a
  reasonable window (e.g. 90 days) so versioning doesn't grow storage
  unbounded.
- R2 itself is already replicated by Cloudflare at the infrastructure
  level — this section is about protecting against *application-level*
  mistakes (bad overwrite, accidental delete), not datacenter loss.

**Restore procedure:** in the R2 dashboard or via `aws s3api
list-object-versions --bucket <bucket> --prefix <key>` (R2 is
S3-API-compatible), find the prior version of the affected object key and
restore/copy it back to the current version.

## 4. Incident checklist (quick reference)

1. Identify scope: Mongo data loss, R2 object loss, or both?
2. If Mongo: restore to a **new** cluster first, verify, then cut over
   (§1). Do not restore in-place until verified.
3. If R2: restore the specific object versions affected (§3) — this is
   usually narrower in scope than a full Mongo incident.
4. After any Mongo cluster change, confirm both backends log a healthy
   replica-set connection and that change streams are watching
   (`apps/mobile-backend` logs this at startup — see `src/server.ts` and
   `src/events/changestreams.ts`).
5. Redis: just repoint and restart (§2) — no data recovery needed.
6. Post-incident: check `apps/mobile-backend`'s BullMQ queues
   (`notifications`, `escalation`, `tenancy`) for a backlog once Redis is
   back — jobs added before the incident but not yet processed will
   still be there (BullMQ persists queued/waiting jobs in Redis; only
   jobs Redis itself lost data for are gone).

## Known gaps this runbook does not close

- No automated backup-verification job (e.g. a scheduled restore-and-check
  to a scratch cluster) — restores are currently untested in practice,
  this runbook is procedural guidance, not a rehearsed/drilled process.
- No monitoring/alerting on backup job failures, replica-set health, or
  change-stream watcher death (a crashed watcher currently only produces
  a log line — see the original architecture audit's Phase 6 finding,
  still open).
- No documented RPO/RTO targets — pick these based on actual business
  requirements and size the Atlas backup tier/retention accordingly.

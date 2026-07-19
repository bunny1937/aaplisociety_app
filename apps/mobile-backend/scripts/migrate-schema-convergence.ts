// One-off migration: renames document fields already written under the old
// mobile-only field names to web's canonical field names (see
// docs/superpowers/plans — schema convergence work). Idempotent: every
// filter only matches documents that still have the old field, so re-running
// this script is always a no-op on already-migrated rows.
//
// Run with: cd apps/mobile-backend && npx tsx scripts/migrate-schema-convergence.ts
// Requires MONGODB_URI to point at the real target database.
import mongoose from "mongoose"
import { env } from "../src/config/env.js"

async function main() {
  await mongoose.connect(env.mongoUri)
  const db = mongoose.connection.db!
  const visitors = db.collection("visitors")
  const notifications = db.collection("notifications")

  console.log("[migrate] visitors: enteredAt -> entryTime")
  const r1 = await visitors.updateMany(
    { enteredAt: { $exists: true }, entryTime: { $exists: false } },
    [{ $set: { entryTime: "$enteredAt" } }, { $unset: "enteredAt" }],
  )
  console.log(`  matched=${r1.matchedCount} modified=${r1.modifiedCount}`)

  console.log("[migrate] visitors: exitedAt -> exitTime")
  const r2 = await visitors.updateMany(
    { exitedAt: { $exists: true }, exitTime: { $exists: false } },
    [{ $set: { exitTime: "$exitedAt" } }, { $unset: "exitedAt" }],
  )
  console.log(`  matched=${r2.matchedCount} modified=${r2.modifiedCount}`)

  console.log("[migrate] visitors: escalationLevel -> escalation.level")
  const r3 = await visitors.updateMany(
    { escalationLevel: { $exists: true }, "escalation.level": { $exists: false } },
    [{ $set: { escalation: { level: "$escalationLevel", stopped: false, history: [] } } }, { $unset: "escalationLevel" }],
  )
  console.log(`  matched=${r3.matchedCount} modified=${r3.modifiedCount}`)

  console.log("[migrate] visitors: default entryMethod where missing")
  const r4 = await visitors.updateMany(
    { entryMethod: { $exists: false } },
    { $set: { entryMethod: "Manual" } },
  )
  console.log(`  matched=${r4.matchedCount} modified=${r4.modifiedCount}`)

  console.log("[migrate] notifications: body -> message")
  const r5 = await notifications.updateMany(
    { body: { $exists: true }, message: { $exists: false } },
    [{ $set: { message: "$body" } }, { $unset: "body" }],
  )
  console.log(`  matched=${r5.matchedCount} modified=${r5.modifiedCount}`)

  console.log("[migrate] notifications: readBy array-of-ids -> array-of-{userId,readAt}")
  const staleReadBy = await notifications.find({
    readBy: { $exists: true, $not: { $size: 0 } },
    "readBy.0": { $type: "objectId" }, // old shape: raw ObjectId elements, not {userId,readAt} subdocs
  }).toArray()
  for (const doc of staleReadBy) {
    const migrated = (doc.readBy as any[]).map((userId) => ({ userId, readAt: doc.updatedAt ?? doc.createdAt ?? new Date() }))
    await notifications.updateOne({ _id: doc._id }, { $set: { readBy: migrated } })
  }
  console.log(`  migrated=${staleReadBy.length}`)

  await mongoose.disconnect()
  console.log("[migrate] done")
}

main().catch((err) => {
  console.error("[migrate] failed", err)
  process.exit(1)
})

// One-off migration: assigns an ObjectId to any familyMembers subdocument
// written before FamilyMemberSchema gained _id (see profile-restructure
// design spec — edit/remove requests need a stable per-person reference).
// Idempotent: only touches subdocuments still missing an _id.
//
// Run with: cd apps/mobile-backend && npx tsx scripts/backfill-family-member-ids.ts
// Requires MONGODB_URI to point at the real target database.
import mongoose from "mongoose"
import { env } from "../src/config/env.js"

async function main() {
  await mongoose.connect(env.mongoUri)
  const members = mongoose.connection.db!.collection("members")

  console.log("[backfill] members: assigning _id to familyMembers subdocuments missing one")
  const cursor = members.find({ "familyMembers._id": { $exists: false }, familyMembers: { $exists: true, $not: { $size: 0 } } })
  let scanned = 0
  let updated = 0
  for await (const doc of cursor) {
    scanned++
    const familyMembers = (doc.familyMembers as any[]).map((m) => (m._id ? m : { ...m, _id: new mongoose.Types.ObjectId() }))
    await members.updateOne({ _id: doc._id }, { $set: { familyMembers } })
    updated++
  }
  console.log(`  scanned=${scanned} updated=${updated}`)

  await mongoose.disconnect()
  console.log("[backfill] done")
}

main().catch((err) => {
  console.error("[backfill] failed", err)
  process.exit(1)
})

import { beforeAll, afterAll, afterEach, inject } from "vitest"
import mongoose from "mongoose"

// Runs before every test file (wired as vitest's `setupFiles`). Set at
// module (not hook) scope so it runs before the test file's own top-level
// imports — anything that imports src/config/env.ts (which reads
// MONGODB_URI eagerly, at import time) needs this already in place.
process.env.MONGODB_URI = inject("mongoUri")

// Connects the default Mongoose connection to the in-memory Mongo instance
// started in globalSetup.ts, and clears all collections between tests so
// state never leaks from one test to the next.
beforeAll(async () => {
  if (mongoose.connection.readyState === 0) {
    await mongoose.connect(process.env.MONGODB_URI as string)
  }
})

afterEach(async () => {
  if (mongoose.connection.readyState !== 1 || !mongoose.connection.db) return
  const collections = await mongoose.connection.db.collections()
  await Promise.all(collections.map((collection) => collection.deleteMany({})))
})

afterAll(async () => {
  await mongoose.disconnect()
})

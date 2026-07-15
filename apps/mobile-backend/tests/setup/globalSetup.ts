import type { GlobalSetupContext } from "vitest/node"
import { MongoMemoryServer } from "mongodb-memory-server"

// Makes `inject("mongoUri")` available inside test/setup files (see testSetup.ts).
declare module "vitest" {
  export interface ProvidedContext {
    mongoUri: string
  }
}

// Runs once, before any test file/worker starts. Spins up a real (but
// in-memory, disposable) MongoDB instance so tests never touch the real
// Atlas cluster configured in .env. The returned function is vitest's
// teardown hook, run once after the whole suite finishes.
export default async function globalSetup({ provide }: GlobalSetupContext) {
  const mongod = await MongoMemoryServer.create()
  provide("mongoUri", mongod.getUri())

  return async () => {
    await mongod.stop()
  }
}

import mongoose from "mongoose"
import { env } from "./env.js"
import { logger } from "../lib/logger.js"

export async function connectDb(): Promise<void> {
  mongoose.set("strictQuery", true)
  await mongoose.connect(env.mongoUri)
  logger.info("[db] connected")
  await assertReplicaSet()
}

// Every realtime notification in this app (visitors, bills, notices,
// complaints, payments, lease-expiry) is driven by Mongo change streams,
// which require a replica set and fail *silently* on a standalone server —
// reads/writes still work, so nothing crashes, but every notification
// simply never fires and there is no error anywhere to notice. This check
// doesn't stop startup (the API is otherwise fully functional without a
// replica set) but logs loudly enough that it should trip a log-based alert
// instead of being discovered by a user reporting "I never got notified".
async function assertReplicaSet(): Promise<void> {
  try {
    const result = await mongoose.connection.db!.admin().command({ hello: 1 })
    if (!result.setName) {
      logger.error(
        "[db] MongoDB is NOT running as a replica set. Change streams " +
        "(visitor/bill/notice/complaint/transaction watchers -> the entire " +
        "notification/FCM/socket pipeline) will silently never fire. The " +
        "API itself will otherwise work normally. Fix: point MONGODB_URI at " +
        "a replica-set-enabled cluster (Atlas clusters are replica sets by " +
        "default; a local/self-hosted mongod needs --replSet configured).",
      )
    } else {
      logger.info({ replicaSet: result.setName }, "[db] replica set confirmed — change streams will work")
    }
  } catch (err) {
    logger.error({ err }, "[db] failed to verify replica-set status — assuming the worst, check change-stream logs at startup")
  }
}

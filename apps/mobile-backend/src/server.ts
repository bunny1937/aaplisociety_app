import http from "node:http"
import mongoose from "mongoose"
import { env } from "./config/env.js"
import { connectDb } from "./config/db.js"
import { initSocket, io } from "./realtime/socket.js"
import { watchVisitors, watchBills, watchNotices } from "./events/changestreams.js"
import { createApp } from "./app.js"
import { notificationsWorker, escalationWorker } from "./queues/index.js" // start workers
import { redis, redisSub } from "./config/redis.js"
import { validateFirebaseConfig } from "./config/firebase.js"
import { logger } from "./lib/logger.js"

async function main() {
  validateFirebaseConfig()
  await connectDb()
  const app = createApp()

  const server = http.createServer(app)
  initSocket(server)
  watchVisitors()
  watchBills()
  watchNotices()

  server.listen(env.port, () => logger.info(`[api] http://localhost:${env.port}`))

  let shuttingDown = false
  async function shutdown(signal: string) {
    if (shuttingDown) return
    shuttingDown = true
    logger.info({ signal }, "[shutdown] starting graceful shutdown")

    server.close(() => logger.info("[shutdown] http server closed"))
    await io.close()
    // Let in-flight BullMQ jobs finish (default close() waits on the current job).
    await Promise.all([notificationsWorker.close(), escalationWorker.close()])
    await mongoose.disconnect()
    await Promise.all([redis.quit(), redisSub.quit()])

    logger.info("[shutdown] done")
    process.exit(0)
  }

  process.on("SIGTERM", () => void shutdown("SIGTERM"))
  process.on("SIGINT", () => void shutdown("SIGINT"))
}

main().catch((e) => { logger.error({ err: e }, "[startup] fatal"); process.exit(1) })

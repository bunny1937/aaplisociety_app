import http from "node:http"
import mongoose from "mongoose"
import { env } from "./config/env.js"
import { connectDb } from "./config/db.js"
import { initSocket, io } from "./realtime/socket.js"
import { watchVisitors, watchBills, watchNotices, watchComplaints, watchTransactions } from "./events/changestreams.js"
import { createApp } from "./app.js"
import { notificationsWorker, escalationWorker, scheduleLeaseExpiryCheck } from "./queues/index.js" // start workers
import { redis, redisSub } from "./config/redis.js"
import { validateFirebaseConfig } from "./config/firebase.js"
import { logger } from "./lib/logger.js"
import { getHealthReport } from "./lib/health.js"

async function main() {
  validateFirebaseConfig()
  await connectDb()
  const app = createApp()

  // Separate from the bare GET /health in app.ts (which stays dependency-free
  // on purpose — see its own comment — so it can be used by tests without a
  // live Mongo/Redis). This one actually checks Mongo/Redis reachability and
  // replica-set status, for a load balancer or uptime check that wants to
  // know if the app is truly healthy, not just that the process is up.
  app.get("/health/deep", async (_req, res) => {
    const report = await getHealthReport()
    res.status(report.ok ? 200 : 503).json(report)
  })

  const server = http.createServer(app)
  initSocket(server)
  watchVisitors()
  watchBills()
  watchNotices()
  watchComplaints()
  watchTransactions()
  await scheduleLeaseExpiryCheck()

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

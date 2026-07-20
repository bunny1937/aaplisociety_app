import "express-async-errors"
import express from "express"
import { createRequire } from "node:module"
import cors from "cors"
import cookieParser from "cookie-parser"
import { pinoHttp } from "pino-http"
import { logger } from "./lib/logger.js"
import { errorHandler } from "./middleware/errorHandler.js"
import { authRouter } from "./modules/auth/auth.controller.js"
import { visitorRouter } from "./modules/visitors/visitor.controller.js"
import { billRouter } from "./modules/bills/bill.controller.js"
import { ledgerRouter } from "./modules/ledger/ledger.controller.js"
import { receiptRouter } from "./modules/receipts/receipt.controller.js"
import { complaintRouter } from "./modules/complaints/complaint.controller.js"
import { noticeRouter } from "./modules/notices/notice.controller.js"
import { deviceRouter } from "./modules/devices/device.controller.js"
import { tenantRequestRouter } from "./modules/tenantRequests/tenantRequest.controller.js"
import { rentPaymentRouter } from "./modules/rentPayments/rentPayment.controller.js"
import { profileEditRequestRouter } from "./modules/profileEditRequests/profileEditRequest.controller.js"
import { tenantHistoryRouter } from "./modules/tenantHistory/tenantHistory.controller.js"
import { notificationRouter } from "./modules/notifications/notification.controller.js"
import { env } from "./config/env.js"
import type { Express } from "express"

// helmet's package.json exports map has no "types" condition, so under
// moduleResolution:NodeNext a static `import helmet from "helmet"` resolves
// its .d.cts inconsistently across platforms (clean on Windows/pnpm, fails
// on Vercel's Linux build with "not callable"). require() sidesteps that
// static resolution entirely.
const require = createRequire(import.meta.url)
const helmet = require("helmet") as () => express.RequestHandler

// Pure Express wiring, no DB/Redis/socket/queue side effects - importable by tests on its own.
export function createApp(): Express {
  const app = express()
  app.use(helmet())
  app.use(cors({
    origin(origin, callback) {
      if (!origin || env.corsOrigins.includes(origin)) return callback(null, true)
      return callback(null, false)
    },
    credentials: true,
  }))
  app.use(express.json())
  app.use(cookieParser())
  app.use(pinoHttp({
    logger,
    redact: ["req.headers.authorization", "req.headers.cookie", "res.headers[\"set-cookie\"]"],
  }))

  app.get("/health", (_req, res) => res.json({ ok: true }))
  app.use("/v1/auth", authRouter)
  app.use("/v1/visitors", visitorRouter)
  app.use("/v1/bills", billRouter)
  app.use("/v1/ledger", ledgerRouter)
  app.use("/v1/receipts", receiptRouter)
  app.use("/v1/complaints", complaintRouter)
  app.use("/v1/notices", noticeRouter)
  app.use("/v1/devices", deviceRouter)
  app.use("/v1/tenant-requests", tenantRequestRouter)
  app.use("/v1/rent-payments", rentPaymentRouter)
  app.use("/v1/profile-edit-requests", profileEditRequestRouter)
  app.use("/v1/tenant-history", tenantHistoryRouter)
  app.use("/v1/notifications", notificationRouter)

  app.use(errorHandler)

  return app
}

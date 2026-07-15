import "express-async-errors"
import express from "express"
import helmet from "helmet"
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
import { env } from "./config/env.js"

// Pure Express wiring, no DB/Redis/socket/queue side effects - importable by tests on its own.
export function createApp() {
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

  app.use(errorHandler)

  return app
}

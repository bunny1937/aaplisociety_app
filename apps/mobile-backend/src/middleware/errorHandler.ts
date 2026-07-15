import type { Request, Response, NextFunction } from "express"

// Last middleware in the chain. Never leaks err.message/stack to the client -
// only a generic message - the real detail goes to the structured log
// (req.log, attached by pino-http) for whoever's watching logs/traces.
export function errorHandler(err: unknown, req: Request, res: Response, next: NextFunction) {
  ;(req as any).log.error({ err }, "unhandled error")
  if (res.headersSent) return next(err)
  res.status(500).json({ error: "Internal server error" })
}

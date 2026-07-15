import type { Request, Response, NextFunction } from "express"

// Every query must be scoped by societyId from the verified token, never from the client body.
export function withTenant(req: Request, res: Response, next: NextFunction) {
  if (!req.auth?.societyId) return res.status(403).json({ error: "No society scope" })
  ;(req as any).societyId = req.auth.societyId
  next()
}

import type { Request, Response, NextFunction } from "express"
import type { JwtClaims } from "@aapli/types"
import { Role, VISITOR_ACCESS_ROLES, ROLES } from "@aapli/constants"
import { verifyAccess } from "../lib/jwt.js"

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request { auth?: JwtClaims }
  }
}

function readToken(req: Request): string | undefined {
  const fromCookie = (req as any).cookies?.token as string | undefined
  const fromHeader = req.headers.authorization?.replace(/^Bearer\s+/i, "")
  return fromCookie ?? fromHeader
}

export function requireAuth(req: Request, res: Response, next: NextFunction) {
  const token = readToken(req)
  if (!token) return res.status(401).json({ error: "No token" })
  try {
    const claims = verifyAccess(token)
    if (claims.pending) return res.status(403).json({ error: "Profile selection required" })
    if (claims.mustChangePassword && req.baseUrl !== "/v1/auth") {
      return res.status(403).json({ error: "Password change required" })
    }
    req.auth = claims
    next()
  } catch {
    return res.status(401).json({ error: "Invalid token" })
  }
}

// Only for the profile-select handshake: accepts a pending (profile-not-yet-chosen) token.
export function requireAuthAllowPending(req: Request, res: Response, next: NextFunction) {
  const token = readToken(req)
  if (!token) return res.status(401).json({ error: "No token" })
  try {
    req.auth = verifyAccess(token)
    next()
  } catch {
    return res.status(401).json({ error: "Invalid token" })
  }
}

export function requireRoles(...roles: Role[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.auth) return res.status(401).json({ error: "No auth" })
    if (!roles.includes(req.auth.role)) return res.status(403).json({ error: "Forbidden" })
    next()
  }
}

export const requireVisitorAccess = requireRoles(...VISITOR_ACCESS_ROLES)
export const requireSecurity = requireRoles(ROLES.SECURITY, ROLES.ADMIN, ROLES.SECRETARY)

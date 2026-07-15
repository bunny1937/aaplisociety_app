import jwt from "jsonwebtoken"
import type { JwtClaims } from "@aapli/types"
import { env } from "../config/env.js"

export function signAccess(claims: JwtClaims): string {
  return jwt.sign(claims, env.jwtSecret, { expiresIn: env.accessTtl } as any)
}
export function signRefresh(payload: { userId: string; jti: string }): string {
  return jwt.sign(payload, env.refreshSecret, { expiresIn: env.refreshTtl } as any)
}
export function verifyAccess(token: string): JwtClaims {
  return jwt.verify(token, env.jwtSecret) as JwtClaims
}
export function verifyRefresh(token: string): { userId: string; jti: string } {
  return jwt.verify(token, env.refreshSecret) as { userId: string; jti: string }
}
// Single source of truth for a refresh token's expiry: read it back from
// the token's own `exp` claim rather than recomputing env.refreshTtl
// separately, so the DB revocation window can never drift from the JWT.
export function refreshExpiresAt(token: string): Date {
  const { exp } = jwt.decode(token) as { exp: number }
  return new Date(exp * 1000)
}

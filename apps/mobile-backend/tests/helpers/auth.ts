import type { JwtClaims } from "@aapli/types"
import { ROLES } from "@aapli/constants"
import { signAccess } from "../../src/lib/jwt.js"
import { randomObjectId } from "../utils/randomObjectId.js"

// Mints a signed access token for tests. Fills in sensible defaults so
// callers only need to override the claims that matter for the case at hand,
// e.g. bearerToken({ role: ROLES.SECURITY }) or
// bearerToken({ societyId: someOtherSocietyId }).
export function bearerToken(claims: Partial<JwtClaims> = {}): string {
  const fullClaims: JwtClaims = {
    userId: randomObjectId().toString(),
    role: ROLES.MEMBER,
    societyId: randomObjectId().toString(),
    memberId: randomObjectId().toString(),
    activeProfileId: randomObjectId().toString(),
    ...claims,
  }
  return signAccess(fullClaims)
}

// Convenience for supertest: request(app).get(...).set(...authHeader(token))
export function authHeader(token: string): { Authorization: string } {
  return { Authorization: `Bearer ${token}` }
}

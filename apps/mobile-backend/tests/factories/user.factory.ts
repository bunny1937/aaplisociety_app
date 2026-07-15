import bcrypt from "bcryptjs"
import { ROLES } from "@aapli/constants"
import { randomObjectId } from "../utils/randomObjectId.js"

// Real bcrypt hash for tests that need a login round-trip to actually
// succeed (auth.controller.ts compares with bcrypt.compare against this).
export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, 10)
}

// Plain-object builder matching the UserSchema shape in src/models/index.ts.
// Not saved to the DB — callers decide whether/when to persist it
// (e.g. `await User.create(makeUser())` in an integration test).
export function makeUser(overrides: Record<string, unknown> = {}) {
  const societyId = randomObjectId()
  return {
    username: `member${Math.floor(Math.random() * 100000)}`,
    email: `member${Math.floor(Math.random() * 100000)}@example.com`,
    passwordHash: "$2a$10$fixturefixturefixturefixturefixturefixturefixture..", // not a real bcrypt hash
    role: ROLES.MEMBER,
    societyId,
    memberId: randomObjectId(),
    profiles: [],
    activeProfileId: undefined,
    isActive: true,
    ...overrides,
  }
}

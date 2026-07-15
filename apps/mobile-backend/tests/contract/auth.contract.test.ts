import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { authHeader } from "../helpers/auth.js"
import { hashPassword } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { User } from "../../src/models/index.js"
import {
  loginSuccessSchema,
  needsProfileSelectSchema,
  meResponseSchema,
} from "./schemas.js"

const app = createApp()
const PASSWORD = "Passw0rd!"

// Whole-shape contract checks: unlike tests/api/auth.api.test.ts (which
// spot-checks individual fields), these assert the ENTIRE response body
// matches an explicit zod schema with no extra/missing/mistyped fields.

describe("contract: POST /v1/auth/login", () => {
  it("single-profile login response matches loginSuccessSchema exactly", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const passwordHash = await hashPassword(PASSWORD)
    const user = await User.create({
      username: `contract.member.${Math.floor(Math.random() * 1e6)}`,
      email: `contract.member.${Math.floor(Math.random() * 1e6)}@example.com`,
      passwordHash,
      role: ROLES.MEMBER,
      societyId,
      memberId,
      profiles: [{
        societyId, memberId, role: ROLES.MEMBER,
        flatNo: "A-101", wing: "A", societyName: "Sunrise CHS", status: "active",
      }],
      isActive: true,
    })

    const res = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    expect(res.status).toBe(200)

    const parsed = loginSuccessSchema.safeParse(res.body)
    if (!parsed.success) console.error(JSON.stringify(parsed.error.format(), null, 2))
    expect(parsed.success).toBe(true)
  })

  it("multi-profile needsProfileSelect response matches needsProfileSelectSchema exactly", async () => {
    const societyId1 = randomObjectId()
    const societyId2 = randomObjectId()
    const passwordHash = await hashPassword(PASSWORD)
    const user = await User.create({
      username: `contract.multi.${Math.floor(Math.random() * 1e6)}`,
      email: `contract.multi.${Math.floor(Math.random() * 1e6)}@example.com`,
      passwordHash,
      role: ROLES.MEMBER,
      societyId: societyId1,
      memberId: randomObjectId(),
      profiles: [
        { societyId: societyId1, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "A-101", wing: "A", societyName: "Sunrise CHS", status: "active" },
        { societyId: societyId2, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "B-202", wing: "B", societyName: "Palm Residency", status: "active" },
      ],
      isActive: true,
    })

    const res = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    expect(res.status).toBe(200)

    const parsed = needsProfileSelectSchema.safeParse(res.body)
    if (!parsed.success) console.error(JSON.stringify(parsed.error.format(), null, 2))
    expect(parsed.success).toBe(true)
  })
})

describe("contract: GET /v1/auth/me", () => {
  it("response matches meResponseSchema exactly, and passwordHash cannot be present (schema forbids it via .strict())", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const passwordHash = await hashPassword(PASSWORD)
    const user = await User.create({
      username: `contract.me.${Math.floor(Math.random() * 1e6)}`,
      email: `contract.me.${Math.floor(Math.random() * 1e6)}@example.com`,
      passwordHash,
      role: ROLES.MEMBER,
      societyId,
      memberId,
      profiles: [{
        societyId, memberId, role: ROLES.MEMBER,
        flatNo: "A-101", wing: "A", societyName: "Sunrise CHS", status: "active",
      }],
      isActive: true,
    })

    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    const res = await request(app).get("/v1/auth/me").set(authHeader(loginRes.body.tokens.accessToken))
    expect(res.status).toBe(200)

    const parsed = meResponseSchema.safeParse(res.body)
    if (!parsed.success) console.error(JSON.stringify(parsed.error.format(), null, 2))
    expect(parsed.success).toBe(true)
  })
})

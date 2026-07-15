import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { makeVisitor } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Visitor } from "../../src/models/index.js"
import { visitorItemSchema } from "./schemas.js"

const app = createApp()

// Whole-shape contract check for a Visitor list item, complementing the
// field-by-field spot checks in tests/api/visitors.api.test.ts.
describe("contract: GET /v1/visitors", () => {
  it("each item in the list matches visitorItemSchema exactly", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Visitor.create(makeVisitor({ societyId, memberId, name: "Contract Visitor" }))

    const token = bearerToken({ role: ROLES.SECURITY, societyId: String(societyId) })
    const res = await request(app).get("/v1/visitors").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body.length).toBeGreaterThan(0)

    for (const item of res.body) {
      const parsed = visitorItemSchema.safeParse(item)
      if (!parsed.success) console.error(JSON.stringify(parsed.error.format(), null, 2))
      expect(parsed.success).toBe(true)
    }
  })

  it("a visitor that has entered (enteredAt set) still matches the schema", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const visitor = await Visitor.create(makeVisitor({ societyId, memberId, status: "Approved" }))
    const securityToken = bearerToken({ role: ROLES.SECURITY, societyId: String(societyId) })

    const enterRes = await request(app).post(`/v1/visitors/${visitor._id}/enter`).set(authHeader(securityToken)).send({})
    expect(enterRes.status).toBe(200)

    const parsed = visitorItemSchema.safeParse(enterRes.body)
    if (!parsed.success) console.error(JSON.stringify(parsed.error.format(), null, 2))
    expect(parsed.success).toBe(true)
  })
})

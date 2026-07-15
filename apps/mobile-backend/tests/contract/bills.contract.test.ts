import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { makeBill } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Bill } from "../../src/models/index.js"
import { billItemSchema } from "./schemas.js"

const app = createApp()

// Whole-shape contract check for a Bill list item, complementing the
// field-by-field spot checks in tests/api/bills.api.test.ts.
describe("contract: GET /v1/bills", () => {
  it("each item in the list matches billItemSchema exactly", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Bill.create(makeBill({ societyId, memberId, amount: 1500, dueDate: new Date("2026-09-01") }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).get("/v1/bills").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body.length).toBeGreaterThan(0)

    for (const item of res.body) {
      const parsed = billItemSchema.safeParse(item)
      if (!parsed.success) console.error(JSON.stringify(parsed.error.format(), null, 2))
      expect(parsed.success).toBe(true)
    }
  })
})

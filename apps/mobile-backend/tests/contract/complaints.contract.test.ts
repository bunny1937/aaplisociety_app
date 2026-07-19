import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { complaintItemSchema } from "./schemas.js"

const app = createApp()

// Whole-shape contract check for a Complaint list item, complementing the
// field-by-field spot checks in tests/api/complaints.api.test.ts.
describe("contract: GET /v1/complaints", () => {
  it("each item in the list matches complaintItemSchema exactly (including an anonymous complaint, which still carries memberId — anonymity is a display concept via anonymousName, matching web's own behavior)", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    await request(app).post("/v1/complaints").set(authHeader(token)).send({
      category: "noise", title: "Loud music complaint", description: "Neighbors playing loud music every night past midnight",
    })
    await request(app).post("/v1/complaints").set(authHeader(token)).send({
      category: "security", title: "Suspicious activity report", description: "Someone was loitering near the gate at night",
      anonymous: true,
    })

    const res = await request(app).get("/v1/complaints").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(2)

    for (const item of res.body) {
      const parsed = complaintItemSchema.safeParse(item)
      if (!parsed.success) console.error(JSON.stringify(parsed.error.format(), null, 2))
      expect(parsed.success).toBe(true)
    }
  })
})

import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Notice } from "../../src/models/index.js"
import { noticeItemSchema } from "./schemas.js"

const app = createApp()

// Whole-shape contract check for a Notice list item, complementing the
// field-by-field spot checks in tests/api/notices.api.test.ts.
describe("contract: GET /v1/notices", () => {
  it("each item in the list matches noticeItemSchema exactly, including a posted (postedBy set) notice", async () => {
    const societyId = randomObjectId()
    await Notice.create({ societyId, title: "Regular update", body: "Nothing urgent", pinned: false })

    const adminToken = bearerToken({ role: ROLES.ADMIN, societyId: String(societyId) })
    await request(app).post("/v1/notices").set(authHeader(adminToken)).send({
      title: "AGM Scheduled", body: "Annual general meeting on the 15th", tag: "Event", pinned: true,
    })

    const res = await request(app).get("/v1/notices").set(authHeader(adminToken))
    expect(res.status).toBe(200)
    expect(res.body.length).toBeGreaterThanOrEqual(2)

    for (const item of res.body) {
      const parsed = noticeItemSchema.safeParse(item)
      if (!parsed.success) console.error(JSON.stringify(parsed.error.format(), null, 2))
      expect(parsed.success).toBe(true)
    }
  })
})

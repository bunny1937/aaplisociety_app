import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Notice } from "../../src/models/index.js"

const app = createApp()

describe("GET /v1/notices", () => {
  it("is readable by any authenticated role, with pinned notices sorted first", async () => {
    const societyId = randomObjectId()
    const unpinned = await Notice.create({
      societyId, createdBy: randomObjectId(), createdByName: "Admin One",
      type: "maintenance", title: "Regular update", description: "Nothing urgent", pinned: false,
    })
    const pinned = await Notice.create({
      societyId, createdBy: randomObjectId(), createdByName: "Admin One",
      type: "water", title: "Water shutdown notice", description: "Water off 10am-2pm for maintenance work", pinned: true,
    })

    const memberToken = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId) })
    const memberRes = await request(app).get("/v1/notices").set(authHeader(memberToken))
    expect(memberRes.status).toBe(200)
    expect(memberRes.body).toHaveLength(2)
    expect(memberRes.body[0]._id).toBe(String(pinned._id))
    expect(memberRes.body[1]._id).toBe(String(unpinned._id))

    const securityToken = bearerToken({ role: ROLES.SECURITY, societyId: String(societyId) })
    const securityRes = await request(app).get("/v1/notices").set(authHeader(securityToken))
    expect(securityRes.status).toBe(200)
    expect(securityRes.body[0]._id).toBe(String(pinned._id))
  })
})

describe("POST /v1/notices", () => {
  it("rejects Member with 403", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const res = await request(app).post("/v1/notices").set(authHeader(token)).send({
      type: "custom", title: "Notice title here", description: "Notice body text long enough to pass validation.",
    })
    expect(res.status).toBe(403)
    expect(res.body).toEqual({ error: "Forbidden" })
  })

  it("creates a notice as Admin", async () => {
    const societyId = randomObjectId()
    const token = bearerToken({ role: ROLES.ADMIN, societyId: String(societyId) })
    const res = await request(app).post("/v1/notices").set(authHeader(token)).send({
      type: "meeting", title: "AGM Scheduled Meeting", description: "Annual general meeting on the 15th at the clubhouse.", pinned: true,
    })
    expect(res.status).toBe(201)
    expect(res.body.title).toBe("AGM Scheduled Meeting")
    expect(res.body.societyId).toBe(String(societyId))
    expect(res.body.pinned).toBe(true)
    expect(res.body.createdBy).toEqual(expect.any(String))
    expect(res.body.createdByName).toEqual(expect.any(String))
  })
})

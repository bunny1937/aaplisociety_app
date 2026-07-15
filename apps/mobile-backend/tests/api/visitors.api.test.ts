import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { makeVisitor } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Visitor } from "../../src/models/index.js"

const app = createApp()

describe("POST /v1/visitors", () => {
  it("creates a visitor as Member with status Pending", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).post("/v1/visitors").set(authHeader(token)).send({
      name: "John Doe", phone: "9876543210", purpose: "Delivery",
    })
    expect(res.status).toBe(201)
    expect(res.body.status).toBe("Pending")
    expect(res.body.memberId).toBe(String(memberId))
    expect(res.body.societyId).toBe(String(societyId))
  })

  it("rejects Security role with 403 (role-gate regression)", async () => {
    const token = bearerToken({ role: ROLES.SECURITY })
    const res = await request(app).post("/v1/visitors").set(authHeader(token)).send({
      name: "Jane Doe", phone: "9876543211", purpose: "Delivery",
    })
    expect(res.status).toBe(403)
    expect(res.body).toEqual({ error: "Forbidden" })
  })
})

describe("GET /v1/visitors", () => {
  it("a member sees only their own visitors, security sees the whole society", async () => {
    const societyId = randomObjectId()
    const member1 = randomObjectId()
    const member2 = randomObjectId()
    const v1 = await Visitor.create(makeVisitor({ societyId, memberId: member1, name: "Visitor One" }))
    const v2 = await Visitor.create(makeVisitor({ societyId, memberId: member2, name: "Visitor Two" }))

    const memberToken = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(member1) })
    const memberRes = await request(app).get("/v1/visitors").set(authHeader(memberToken))
    expect(memberRes.status).toBe(200)
    expect(memberRes.body).toHaveLength(1)
    expect(memberRes.body[0]._id).toBe(String(v1._id))

    const securityToken = bearerToken({ role: ROLES.SECURITY, societyId: String(societyId) })
    const securityRes = await request(app).get("/v1/visitors").set(authHeader(securityToken))
    expect(securityRes.status).toBe(200)
    const ids = securityRes.body.map((v: any) => v._id).sort()
    expect(ids).toEqual([String(v1._id), String(v2._id)].sort())
  })
})

describe("POST /v1/visitors/:id/decision", () => {
  it("the owning member can approve their own pending visitor", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const visitor = await Visitor.create(makeVisitor({ societyId, memberId, status: "Pending" }))
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).post(`/v1/visitors/${visitor._id}/decision`).set(authHeader(token)).send({
      decision: "approve",
    })
    expect(res.status).toBe(200)
    expect(res.body.status).toBe("Approved")
  })

  it("critical: a different member cannot decide on a visitor they don't own (404)", async () => {
    const societyId = randomObjectId()
    const owner = randomObjectId()
    const intruder = randomObjectId()
    const visitor = await Visitor.create(makeVisitor({ societyId, memberId: owner, status: "Pending" }))
    const intruderToken = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(intruder) })

    const res = await request(app).post(`/v1/visitors/${visitor._id}/decision`).set(authHeader(intruderToken)).send({
      decision: "approve",
    })
    expect(res.status).toBe(404)
    expect(res.body).toEqual({ error: "Not found or already decided" })

    const unchanged = await Visitor.findById(visitor._id)
    expect(unchanged!.status).toBe("Pending")
  })

  it("deciding again after already decided returns 404 Not found or already decided", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const visitor = await Visitor.create(makeVisitor({ societyId, memberId, status: "Pending" }))
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const first = await request(app).post(`/v1/visitors/${visitor._id}/decision`).set(authHeader(token)).send({ decision: "approve" })
    expect(first.status).toBe(200)

    const second = await request(app).post(`/v1/visitors/${visitor._id}/decision`).set(authHeader(token)).send({ decision: "approve" })
    expect(second.status).toBe(404)
    expect(second.body).toEqual({ error: "Not found or already decided" })
  })
})

describe("POST /v1/visitors/:id/enter and /exit", () => {
  it("security can mark entry, member cannot", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const visitor = await Visitor.create(makeVisitor({ societyId, memberId, status: "Approved" }))

    const memberToken = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const forbidden = await request(app).post(`/v1/visitors/${visitor._id}/enter`).set(authHeader(memberToken)).send({})
    expect(forbidden.status).toBe(403)

    const securityToken = bearerToken({ role: ROLES.SECURITY, societyId: String(societyId) })
    const res = await request(app).post(`/v1/visitors/${visitor._id}/enter`).set(authHeader(securityToken)).send({})
    expect(res.status).toBe(200)
    expect(res.body.status).toBe("Entered")
    expect(res.body.enteredAt).toBeTruthy()
  })

  it("security can mark exit", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const visitor = await Visitor.create(makeVisitor({ societyId, memberId, status: "Entered" }))
    const securityToken = bearerToken({ role: ROLES.SECURITY, societyId: String(societyId) })

    const res = await request(app).post(`/v1/visitors/${visitor._id}/exit`).set(authHeader(securityToken)).send({})
    expect(res.status).toBe(200)
    expect(res.body.status).toBe("Exited")
    expect(res.body.exitedAt).toBeTruthy()
  })
})

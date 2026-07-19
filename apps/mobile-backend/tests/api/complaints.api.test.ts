import { describe, it, expect, beforeEach, afterEach } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Complaint } from "../../src/models/index.js"

const app = createApp()

describe("POST /v1/complaints", () => {
  it("creates a complaint as Member with status PENDING and the member attached", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).post("/v1/complaints").set(authHeader(token)).send({
      category: "noise", title: "Loud music complaint", description: "Neighbors playing loud music every night past midnight",
    })
    expect(res.status).toBe(201)
    expect(res.body.status).toBe("PENDING")
    expect(res.body.memberId).toBe(String(memberId))
  })

  // Web's own complaint routes always store memberId and always generate a
  // pseudonym (anonymousName) regardless of the anonymous flag — "anonymous"
  // is a display concept there, not an untraceable one. Mobile matches that
  // exactly now: memberId is always present, anonymousName is always set.
  it("an anonymous complaint still stores memberId (for admin accountability) and gets a generated anonymousName", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).post("/v1/complaints").set(authHeader(token)).send({
      category: "security", title: "Suspicious activity report", description: "Someone was loitering near the gate at night",
      anonymous: true,
    })
    expect(res.status).toBe(201)
    expect(res.body.memberId).toBe(String(memberId))
    expect(res.body.anonymousName).toEqual(expect.any(String))
    expect(res.body.anonymousName.length).toBeGreaterThan(0)

    const stored = await Complaint.findById(res.body._id)
    expect(String(stored!.memberId)).toBe(String(memberId))
  })
})

describe("GET /v1/complaints", () => {
  it("a member sees only their own complaints, an admin sees all", async () => {
    const societyId = randomObjectId()
    const member1 = randomObjectId()
    const member2 = randomObjectId()
    const c1 = await Complaint.create({ societyId, memberId: member1, anonymousName: "TestPseudonym11", category: "noise", title: "T1", description: "D1 description long enough", status: "PENDING" })
    const c2 = await Complaint.create({ societyId, memberId: member2, anonymousName: "TestPseudonym22", category: "water", title: "T2", description: "D2 description long enough", status: "PENDING" })

    const memberToken = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(member1) })
    const memberRes = await request(app).get("/v1/complaints").set(authHeader(memberToken))
    expect(memberRes.status).toBe(200)
    expect(memberRes.body).toHaveLength(1)
    expect(memberRes.body[0]._id).toBe(String(c1._id))

    const adminToken = bearerToken({ role: ROLES.ADMIN, societyId: String(societyId) })
    const adminRes = await request(app).get("/v1/complaints").set(authHeader(adminToken))
    expect(adminRes.status).toBe(200)
    const ids = adminRes.body.map((c: any) => c._id).sort()
    expect(ids).toEqual([String(c1._id), String(c2._id)].sort())
  })
})

describe("PATCH /v1/complaints/:id/status", () => {
  it("rejects Member with 403", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const complaint = await Complaint.create({ societyId, memberId, anonymousName: "TestPseudonym33", category: "noise", title: "T", description: "Description long enough", status: "PENDING" })
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).patch(`/v1/complaints/${complaint._id}/status`).set(authHeader(token)).send({ status: "Resolved" })
    expect(res.status).toBe(403)
    expect(res.body).toEqual({ error: "Forbidden" })
  })

  // Mobile's status vocabulary doesn't map cleanly onto web's canonical enum
  // yet (see complaintStatusWritesEnabled's doc comment in config/env.ts) —
  // disabled by default until that mapping is decided.
  it("is disabled by default: rejects an otherwise-valid Admin/Secretary request with 403 and leaves the complaint unchanged", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const complaint = await Complaint.create({ societyId, memberId, anonymousName: "TestPseudonym44", category: "noise", title: "T", description: "Description long enough", status: "PENDING" })
    const token = bearerToken({ role: ROLES.SECRETARY, societyId: String(societyId) })

    const res = await request(app).patch(`/v1/complaints/${complaint._id}/status`).set(authHeader(token)).send({
      status: "Resolved", resolutionNote: "Spoke with the resident, issue resolved.",
    })
    expect(res.status).toBe(403)
    expect(res.body).toEqual({ error: "Complaint status updates are temporarily disabled." })

    const stored = await Complaint.findById(complaint._id)
    expect(stored!.status).toBe("PENDING")
  })

  describe("when COMPLAINT_STATUS_WRITES_ENABLED=true", () => {
    beforeEach(() => {
      process.env.COMPLAINT_STATUS_WRITES_ENABLED = "true"
    })
    afterEach(() => {
      delete process.env.COMPLAINT_STATUS_WRITES_ENABLED
    })

    it("Admin/Secretary can update status and persist the resolutionNote", async () => {
      const societyId = randomObjectId()
      const memberId = randomObjectId()
      const complaint = await Complaint.create({ societyId, memberId, anonymousName: "TestPseudonym55", category: "noise", title: "T", description: "Description long enough", status: "PENDING" })
      const token = bearerToken({ role: ROLES.SECRETARY, societyId: String(societyId) })

      const res = await request(app).patch(`/v1/complaints/${complaint._id}/status`).set(authHeader(token)).send({
        status: "Resolved", resolutionNote: "Spoke with the resident, issue resolved.",
      })
      expect(res.status).toBe(200)
      expect(res.body.status).toBe("Resolved")
      expect(res.body.resolutionNote).toBe("Spoke with the resident, issue resolved.")

      const stored = await Complaint.findById(complaint._id)
      expect(stored!.status).toBe("Resolved")
      expect(stored!.resolutionNote).toBe("Spoke with the resident, issue resolved.")
    })

    it("returns 404 (not 403) for a complaint in a different society, even though writes are enabled", async () => {
      const societyA = randomObjectId()
      const societyB = randomObjectId()
      const memberId = randomObjectId()
      const complaint = await Complaint.create({ societyId: societyB, memberId, anonymousName: "TestPseudonym66", category: "noise", title: "T", description: "Description long enough", status: "PENDING" })
      const tokenA = bearerToken({ role: ROLES.SECRETARY, societyId: String(societyA) })

      const res = await request(app).patch(`/v1/complaints/${complaint._id}/status`).set(authHeader(tokenA)).send({ status: "Resolved" })
      expect(res.status).toBe(404)
    })
  })
})

// The single most important file in this pass: proves a token scoped to
// society A can never see or mutate society B's documents across every
// list/read/write endpoint on all 5 routers. A cross-tenant leak here would
// be the worst possible bug for a multi-tenant app.
import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { makeBill, makeVisitor } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Bill, Visitor, Complaint, Notice, User, TenantRequest, RentPayment } from "../../src/models/index.js"

const app = createApp()

async function seedSociety() {
  const societyId = randomObjectId()
  const memberId = randomObjectId()
  const bill = await Bill.create(makeBill({ societyId, memberId }))
  const visitor = await Visitor.create(makeVisitor({ societyId, memberId, status: "Pending" }))
  const complaint = await Complaint.create({
    societyId, memberId, anonymousName: "TestPseudonym42", category: "noise",
    title: "T", description: "Some long enough description", status: "PENDING",
  })
  const notice = await Notice.create({
    societyId, createdBy: randomObjectId(), createdByName: "Test Admin",
    type: "custom", title: "N", description: "Notice body text",
  })
  const tenantRequest = await TenantRequest.create({
    societyId, memberId, requestedByUserId: randomObjectId(),
    tenantName: "Rohan Mehta", tenantPhone: "9876543210", tenantEmail: "rohan@example.com",
    leaseStartDate: new Date(), leaseEndDate: new Date(), rentPerMonth: 18000,
    documents: { contractKey: "k1", signatureKey: "k2", aadhaarKey: "k3", policeVerificationKey: "k4" },
    status: "Pending",
  })
  const rentPayment = await RentPayment.create({
    societyId, memberId, recordedByUserId: randomObjectId(),
    month: "2026-08", amount: 18000, paymentMode: "UPI", paidAt: new Date(),
  })
  return { societyId, memberId, bill, visitor, complaint, notice, tenantRequest, rentPayment }
}

describe("cross-tenant isolation", () => {
  it("bills: society A cannot list, or pay, society B's bill", async () => {
    const a = await seedSociety()
    const b = await seedSociety()
    const adminA = bearerToken({ role: ROLES.ADMIN, societyId: String(a.societyId) })

    const listRes = await request(app).get("/v1/bills").set(authHeader(adminA))
    expect(listRes.status).toBe(200)
    expect(listRes.body.map((x: any) => x._id)).not.toContain(String(b.bill._id))

    const payRes = await request(app).post(`/v1/bills/${b.bill._id}/pay`).set(authHeader(adminA)).send({
      amount: 100, paymentMode: "Cash",
    })
    expect(payRes.status).toBe(404)

    const unchanged = await Bill.findById(b.bill._id)
    expect(unchanged!.amountPaid).toBe(0)
  })

  it("visitors: society A cannot list, decide, enter, or exit society B's visitor", async () => {
    const a = await seedSociety()
    const b = await seedSociety()
    const adminA = bearerToken({ role: ROLES.ADMIN, societyId: String(a.societyId) })
    const memberA = bearerToken({ role: ROLES.MEMBER, societyId: String(a.societyId), memberId: String(a.memberId) })
    const securityA = bearerToken({ role: ROLES.SECURITY, societyId: String(a.societyId) })

    const listRes = await request(app).get("/v1/visitors").set(authHeader(adminA))
    expect(listRes.status).toBe(200)
    expect(listRes.body.map((x: any) => x._id)).not.toContain(String(b.visitor._id))

    const decisionRes = await request(app).post(`/v1/visitors/${b.visitor._id}/decision`).set(authHeader(memberA)).send({
      decision: "approve",
    })
    expect(decisionRes.status).toBe(404)

    const enterRes = await request(app).post(`/v1/visitors/${b.visitor._id}/enter`).set(authHeader(securityA)).send({})
    expect(enterRes.status).toBe(404)

    const exitRes = await request(app).post(`/v1/visitors/${b.visitor._id}/exit`).set(authHeader(securityA)).send({})
    expect(exitRes.status).toBe(404)

    const unchanged = await Visitor.findById(b.visitor._id)
    expect(unchanged!.status).toBe("Pending")
  })

  it("complaints: society A cannot list or update society B's complaint", async () => {
    const a = await seedSociety()
    const b = await seedSociety()
    const adminA = bearerToken({ role: ROLES.ADMIN, societyId: String(a.societyId) })

    const listRes = await request(app).get("/v1/complaints").set(authHeader(adminA))
    expect(listRes.status).toBe(200)
    expect(listRes.body.map((x: any) => x._id)).not.toContain(String(b.complaint._id))

    const patchRes = await request(app).patch(`/v1/complaints/${b.complaint._id}/status`).set(authHeader(adminA)).send({
      status: "Resolved",
    })
    expect(patchRes.status).toBe(404)

    const unchanged = await Complaint.findById(b.complaint._id)
    expect(unchanged!.status).toBe("PENDING")
  })

  it("notices: society A cannot see society B's notices, and cannot force a cross-society write via body.societyId", async () => {
    const a = await seedSociety()
    const b = await seedSociety()
    const adminA = bearerToken({ role: ROLES.ADMIN, societyId: String(a.societyId) })

    const listRes = await request(app).get("/v1/notices").set(authHeader(adminA))
    expect(listRes.status).toBe(200)
    expect(listRes.body.map((x: any) => x._id)).not.toContain(String(b.notice._id))

    // Even if the client tries to inject a foreign societyId in the body,
    // the server must only ever use the societyId carried in the verified token.
    const createRes = await request(app).post("/v1/notices").set(authHeader(adminA)).send({
      type: "custom", title: "Injected Notice Title", description: "This description is long enough to pass validation checks.",
      societyId: String(b.societyId),
    })
    expect(createRes.status).toBe(201)
    expect(createRes.body.societyId).toBe(String(a.societyId))
  })

  it("tenant-requests: society A cannot list or confirm-move-out society B's request", async () => {
    const a = await seedSociety()
    const b = await seedSociety()
    const memberA = bearerToken({ role: ROLES.MEMBER, societyId: String(a.societyId), memberId: String(a.memberId) })

    const listRes = await request(app).get("/v1/tenant-requests").set(authHeader(memberA))
    expect(listRes.status).toBe(200)
    expect(listRes.body.map((x: any) => x._id)).not.toContain(String(b.tenantRequest._id))

    const confirmRes = await request(app)
      .post(`/v1/tenant-requests/${b.tenantRequest._id}/confirm-move-out`)
      .set(authHeader(memberA))
    expect(confirmRes.status).toBe(404)

    const unchanged = await TenantRequest.findById(b.tenantRequest._id)
    expect(unchanged!.ownerConfirmedMoveOutAt).toBeFalsy()
  })

  it("rent-payments: society A cannot see society B's rent payment history", async () => {
    const a = await seedSociety()
    const b = await seedSociety()
    const memberA = bearerToken({ role: ROLES.MEMBER, societyId: String(a.societyId), memberId: String(a.memberId) })

    const listRes = await request(app).get("/v1/rent-payments").set(authHeader(memberA))
    expect(listRes.status).toBe(200)
    expect(listRes.body.map((x: any) => x._id)).not.toContain(String(b.rentPayment._id))
  })

  it("auth/members: an admin only sees members of their own society", async () => {
    const societyA = randomObjectId()
    const societyB = randomObjectId()
    const passwordHash = "$2a$10$fixturefixturefixturefixturefixturefixturefixture.."
    await User.create({
      username: "member.society.a", email: "a@example.com", passwordHash, role: ROLES.MEMBER,
      societyId: societyA, memberId: randomObjectId(),
      profiles: [{ societyId: societyA, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "A-1", wing: "A", societyName: "Society A", status: "Active" }],
      isActive: true,
    })
    await User.create({
      username: "member.society.b", email: "b@example.com", passwordHash, role: ROLES.MEMBER,
      societyId: societyB, memberId: randomObjectId(),
      profiles: [{ societyId: societyB, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "B-1", wing: "B", societyName: "Society B", status: "Active" }],
      isActive: true,
    })

    const adminA = bearerToken({ role: ROLES.ADMIN, societyId: String(societyA) })
    const res = await request(app).get("/v1/auth/members").set(authHeader(adminA))
    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    expect(res.body[0].username).toBe("member.society.a")
  })
})

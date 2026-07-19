import { describe, it, expect, vi } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { TenantRequest, Member } from "../../src/models/index.js"

// Storage is mocked so this suite never calls real S3/R2 — see
// tests/mocks/storage.mock.ts and tests/api/README.md. The factory imports
// the mock module dynamically (rather than referencing top-level imported
// bindings) so it isn't affected by vi.mock's hoisting to the top of the file.
vi.mock("../../src/services/storage.js", async () => {
  const mock = await import("../mocks/storage.mock.js")
  return {
    buildKey: mock.buildKeyMock,
    presignUpload: mock.presignUploadMock,
    presignDownload: mock.presignDownloadMock,
    uploadBuffer: mock.uploadBufferMock,
  }
})

const app = createApp()

function validPayload(overrides: Record<string, unknown> = {}) {
  return {
    tenantName: "Rohan Mehta",
    tenantPhone: "9876543210",
    tenantEmail: "rohan@example.com",
    leaseStartDate: "2026-08-01T00:00:00.000Z",
    leaseEndDate: "2027-07-31T00:00:00.000Z",
    rentPerMonth: 18000,
    depositAmount: 36000,
    documents: {
      contractKey: "society1/tenant-requests/contract/uuid.pdf",
      signatureKey: "society1/tenant-requests/signature/uuid.png",
      aadhaarKey: "society1/tenant-requests/aadhaar/uuid.png",
      policeVerificationKey: "society1/tenant-requests/policeVerification/uuid.png",
    },
    ...overrides,
  }
}

describe("POST /v1/tenant-requests/upload/:field", () => {
  it("rejects an oversized contract PDF with 400", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const oversized = Buffer.alloc(1_048_577, 1) // 1 byte over the 1MB cap
    const res = await request(app)
      .post("/v1/tenant-requests/upload/contract")
      .set(authHeader(token))
      .attach("file", oversized, { filename: "contract.pdf", contentType: "application/pdf" })
    expect(res.status).toBe(400)
  })

  it("rejects a wrong content-type for the signature field with 400", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const res = await request(app)
      .post("/v1/tenant-requests/upload/signature")
      .set(authHeader(token))
      .attach("file", Buffer.from("not an image"), { filename: "sig.txt", contentType: "text/plain" })
    expect(res.status).toBe(400)
  })

  it("rejects an unknown field name with 400", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const res = await request(app)
      .post("/v1/tenant-requests/upload/passport")
      .set(authHeader(token))
      .attach("file", Buffer.from("x"), { filename: "x.png", contentType: "image/png" })
    expect(res.status).toBe(400)
  })

  it("accepts a valid contract PDF within the size cap and returns a key", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const res = await request(app)
      .post("/v1/tenant-requests/upload/contract")
      .set(authHeader(token))
      .attach("file", Buffer.alloc(1000, 1), { filename: "contract.pdf", contentType: "application/pdf" })
    expect(res.status).toBe(201)
    expect(res.body.key).toEqual(expect.any(String))
    expect(res.body.key.length).toBeGreaterThan(0)
  })

  it("rejects the upload endpoint for a Tenant-occupancy caller with 403", async () => {
    const token = bearerToken({ role: ROLES.MEMBER, occupancyType: "Tenant" } as any)
    const res = await request(app)
      .post("/v1/tenant-requests/upload/contract")
      .set(authHeader(token))
      .attach("file", Buffer.alloc(1000, 1), { filename: "contract.pdf", contentType: "application/pdf" })
    expect(res.status).toBe(403)
  })
})

describe("POST /v1/tenant-requests", () => {
  it("creates a Pending request for the caller's own flat", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).post("/v1/tenant-requests").set(authHeader(token)).send(validPayload())
    expect(res.status).toBe(201)
    expect(res.body.status).toBe("Pending")
    expect(res.body.memberId).toBe(String(memberId))
    expect(res.body.societyId).toBe(String(societyId))
    expect(res.body.tenantName).toBe("Rohan Mehta")
  })

  it("rejects a Tenant-occupancy caller with 403", async () => {
    const token = bearerToken({ role: ROLES.MEMBER, occupancyType: "Tenant" } as any)
    const res = await request(app).post("/v1/tenant-requests").set(authHeader(token)).send(validPayload())
    expect(res.status).toBe(403)
  })

  it("rejects an invalid payload with 400", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const res = await request(app).post("/v1/tenant-requests").set(authHeader(token)).send(validPayload({ tenantPhone: "123" }))
    expect(res.status).toBe(400)
  })
})

describe("GET /v1/tenant-requests", () => {
  it("an owner sees all statuses of their own flat's requests", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    await TenantRequest.create({
      societyId, memberId, requestedByUserId: randomObjectId(),
      tenantName: "A", tenantPhone: "9876543210", tenantEmail: "a@example.com",
      leaseStartDate: new Date(), leaseEndDate: new Date(), rentPerMonth: 1000,
      documents: { contractKey: "k1", signatureKey: "k2", aadhaarKey: "k3", policeVerificationKey: "k4" },
      status: "Rejected", rejectionReason: "Incomplete documents",
    })
    const res = await request(app).get("/v1/tenant-requests").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    expect(res.body[0].status).toBe("Rejected")
  })

  it("a Tenant-occupancy caller only sees Approved requests for their flat", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await TenantRequest.create({
      societyId, memberId, requestedByUserId: randomObjectId(),
      tenantName: "A", tenantPhone: "9876543210", tenantEmail: "a@example.com",
      leaseStartDate: new Date(), leaseEndDate: new Date(), rentPerMonth: 1000,
      documents: { contractKey: "k1", signatureKey: "k2", aadhaarKey: "k3", policeVerificationKey: "k4" },
      status: "Pending",
    })
    const approved = await TenantRequest.create({
      societyId, memberId, requestedByUserId: randomObjectId(),
      tenantName: "B", tenantPhone: "9876543211", tenantEmail: "b@example.com",
      leaseStartDate: new Date(), leaseEndDate: new Date(), rentPerMonth: 2000,
      documents: { contractKey: "k1", signatureKey: "k2", aadhaarKey: "k3", policeVerificationKey: "k4" },
      status: "Approved",
    })
    const tenantToken = bearerToken({
      role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId), occupancyType: "Tenant",
    } as any)
    const res = await request(app).get("/v1/tenant-requests").set(authHeader(tenantToken))
    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    expect(res.body[0]._id).toBe(String(approved._id))
  })
})

describe("POST /v1/tenant-requests/:id/confirm-move-out", () => {
  it("sets ownerConfirmedMoveOutAt and does not finalize yet if admin hasn't confirmed", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const created = await TenantRequest.create({
      societyId, memberId, requestedByUserId: randomObjectId(),
      tenantName: "Rohan Mehta", tenantPhone: "9876543210", tenantEmail: "rohan@example.com",
      leaseStartDate: new Date(), leaseEndDate: new Date(), rentPerMonth: 18000,
      documents: { contractKey: "k1", signatureKey: "k2", aadhaarKey: "k3", policeVerificationKey: "k4" },
      status: "Approved",
    })

    const res = await request(app).post(`/v1/tenant-requests/${created._id}/confirm-move-out`).set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body.ownerConfirmedMoveOutAt).toEqual(expect.any(String))
    expect(res.body.status).toBe("Approved") // not finalized yet

    const stillThere = await TenantRequest.findById(created._id)
    expect(stillThere!.status).toBe("Approved")
  })

  it("finalizes (status Closed) when admin had already confirmed first", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Member.create({ _id: memberId, societyId, ownerName: "Owner Name", flatNo: "A-1", currentTenant: { name: "Rohan Mehta", isCurrent: true } } as any)
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const created = await TenantRequest.create({
      societyId, memberId, requestedByUserId: randomObjectId(),
      tenantName: "Rohan Mehta", tenantPhone: "9876543210", tenantEmail: "rohan@example.com",
      leaseStartDate: new Date(), leaseEndDate: new Date(), rentPerMonth: 18000,
      documents: { contractKey: "k1", signatureKey: "k2", aadhaarKey: "k3", policeVerificationKey: "k4" },
      status: "Approved", adminConfirmedMoveOutAt: new Date(),
    })

    const res = await request(app).post(`/v1/tenant-requests/${created._id}/confirm-move-out`).set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body.status).toBe("Closed")

    const finalized = await Member.findById(memberId)
    expect((finalized as any).currentTenant).toBeFalsy()
    expect((finalized as any).ownershipType).toBe("Owner-Occupied")
  })

  it("rejects a Tenant-occupancy caller with 403", async () => {
    const token = bearerToken({ role: ROLES.MEMBER, occupancyType: "Tenant" } as any)
    const res = await request(app).post(`/v1/tenant-requests/${randomObjectId()}/confirm-move-out`).set(authHeader(token))
    expect(res.status).toBe(403)
  })

  it("returns 404 for a request belonging to a different flat", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const otherRequest = await TenantRequest.create({
      societyId: randomObjectId(), memberId: randomObjectId(), requestedByUserId: randomObjectId(),
      tenantName: "A", tenantPhone: "9876543210", tenantEmail: "a@example.com",
      leaseStartDate: new Date(), leaseEndDate: new Date(), rentPerMonth: 1000,
      documents: { contractKey: "k1", signatureKey: "k2", aadhaarKey: "k3", policeVerificationKey: "k4" },
      status: "Approved",
    })
    const res = await request(app).post(`/v1/tenant-requests/${otherRequest._id}/confirm-move-out`).set(authHeader(token))
    expect(res.status).toBe(404)
  })
})

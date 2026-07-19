import { describe, it, expect } from "vitest"
import { TenantRequest, RentPayment, User } from "../../src/models/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"

describe("TenantRequest model", () => {
  it("persists and reads back a full tenant request, defaulting status to Pending", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const requestedByUserId = randomObjectId()
    const created = await TenantRequest.create({
      societyId, memberId, requestedByUserId,
      tenantName: "Rohan Mehta", tenantPhone: "9876543210", tenantEmail: "rohan@example.com",
      leaseStartDate: new Date("2026-08-01"), leaseEndDate: new Date("2027-07-31"),
      rentPerMonth: 18000, depositAmount: 36000,
      documents: {
        contractKey: "k1", signatureKey: "k2", aadhaarKey: "k3", policeVerificationKey: "k4",
      },
    })
    expect(created.status).toBe("Pending")

    const found = await TenantRequest.findById(created._id)
    expect(found!.tenantName).toBe("Rohan Mehta")
    expect((found as any).documents.contractKey).toBe("k1")
  })
})

describe("RentPayment model", () => {
  it("persists and reads back a rent payment", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const recordedByUserId = randomObjectId()
    const created = await RentPayment.create({
      societyId, memberId, recordedByUserId,
      month: "2026-08", amount: 18000, paymentMode: "UPI", paidAt: new Date("2026-08-03"),
    })
    const found = await RentPayment.findById(created._id)
    expect(found!.amount).toBe(18000)
    expect(found!.paymentMode).toBe("UPI")
  })
})

describe("User.profiles occupancyType", () => {
  it("defaults occupancyType to Owner when not specified", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const user = await User.create({
      username: `occ.${Math.floor(Math.random() * 1e6)}`,
      passwordHash: "$2a$10$fixturefixturefixturefixturefixturefixturefixture..",
      role: "Member",
      societyId, memberId,
      profiles: [{ societyId, memberId, role: "Member", flatNo: "A-1", wing: "A", societyName: "S", status: "Active" }],
      isActive: true,
    })
    expect((user.profiles[0] as any).occupancyType).toBe("Owner")
  })

  it("stores occupancyType: Tenant when set explicitly", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const user = await User.create({
      username: `occ.${Math.floor(Math.random() * 1e6)}`,
      passwordHash: "$2a$10$fixturefixturefixturefixturefixturefixturefixture..",
      role: "Member",
      societyId, memberId,
      profiles: [{ societyId, memberId, role: "Member", flatNo: "A-1", wing: "A", societyName: "S", status: "Active", occupancyType: "Tenant" }],
      isActive: true,
    })
    expect((user.profiles[0] as any).occupancyType).toBe("Tenant")
  })
})

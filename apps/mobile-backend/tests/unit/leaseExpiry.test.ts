import { describe, it, expect } from "vitest"
import { checkLeaseExpiry } from "../../src/queues/index.js"
import { TenantRequest, User } from "../../src/models/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"

async function makeApprovedTenant(overrides: Record<string, unknown> = {}) {
  const societyId = randomObjectId()
  const memberId = randomObjectId()
  const tenantUser = await User.create({
    username: `tenant.${Math.floor(Math.random() * 1e6)}`,
    passwordHash: "$2a$10$fixturefixturefixturefixturefixturefixturefixture..",
    role: "Member",
    societyId, memberId,
    profiles: [{ societyId, memberId, role: "Member", flatNo: "A-1", wing: "A", societyName: "S", status: "Active", occupancyType: "Tenant" }],
    isActive: true,
  })
  const request = await TenantRequest.create({
    societyId, memberId, requestedByUserId: randomObjectId(),
    tenantName: "Rohan Mehta", tenantPhone: "9876543210", tenantEmail: "rohan@example.com",
    leaseStartDate: new Date("2026-01-01"),
    leaseEndDate: overrides.leaseEndDate ?? new Date("2026-01-01"), // expired by default
    rentPerMonth: 18000,
    documents: { contractKey: "k1", signatureKey: "k2", aadhaarKey: "k3", policeVerificationKey: "k4" },
    status: "Approved",
    ...overrides,
  })
  return { societyId, memberId, tenantUser, request }
}

describe("checkLeaseExpiry", () => {
  it("suspends the tenant's login and stamps leaseExpiredAt when the lease has ended", async () => {
    const { tenantUser, request } = await makeApprovedTenant({ leaseEndDate: new Date("2020-01-01") })
    await checkLeaseExpiry()

    const updatedUser = await User.findById(tenantUser._id)
    expect(updatedUser!.isActive).toBe(false)

    const updatedRequest = await TenantRequest.findById(request._id)
    expect(updatedRequest!.leaseExpiredAt).not.toBeNull()
  })

  it("does not touch a tenant whose lease has not ended yet", async () => {
    const future = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
    const { tenantUser, request } = await makeApprovedTenant({ leaseEndDate: future })
    await checkLeaseExpiry()

    const updatedUser = await User.findById(tenantUser._id)
    expect(updatedUser!.isActive).toBe(true)

    const updatedRequest = await TenantRequest.findById(request._id)
    expect(updatedRequest!.leaseExpiredAt).toBeFalsy()
  })

  it("does not re-process a request whose leaseExpiredAt is already set", async () => {
    const { request } = await makeApprovedTenant({ leaseEndDate: new Date("2020-01-01"), leaseExpiredAt: new Date("2020-01-02") })
    await checkLeaseExpiry()
    const updatedRequest = await TenantRequest.findById(request._id)
    expect(updatedRequest!.leaseExpiredAt!.toISOString()).toBe(new Date("2020-01-02").toISOString())
  })
})

import { describe, it, expect } from "vitest"
import { tenantRequestCreateSchema, rentPaymentCreateSchema } from "@aapli/validation"

describe("tenantRequestCreateSchema", () => {
  const valid = {
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
  }

  it("accepts a fully valid payload", () => {
    expect(tenantRequestCreateSchema.safeParse(valid).success).toBe(true)
  })

  it("rejects a 9-digit phone number", () => {
    const parsed = tenantRequestCreateSchema.safeParse({ ...valid, tenantPhone: "987654321" })
    expect(parsed.success).toBe(false)
  })

  it("rejects a missing document key", () => {
    const { policeVerificationKey, ...rest } = valid.documents
    const parsed = tenantRequestCreateSchema.safeParse({ ...valid, documents: rest })
    expect(parsed.success).toBe(false)
  })

  it("rejects a non-positive rentPerMonth", () => {
    const parsed = tenantRequestCreateSchema.safeParse({ ...valid, rentPerMonth: 0 })
    expect(parsed.success).toBe(false)
  })
})

describe("rentPaymentCreateSchema", () => {
  const valid = {
    month: "2026-08",
    amount: 18000,
    paymentMode: "UPI",
    paidAt: "2026-08-03T10:00:00.000Z",
  }

  it("accepts a fully valid payload", () => {
    expect(rentPaymentCreateSchema.safeParse(valid).success).toBe(true)
  })

  it("rejects an invalid paymentMode", () => {
    const parsed = rentPaymentCreateSchema.safeParse({ ...valid, paymentMode: "Crypto" })
    expect(parsed.success).toBe(false)
  })

  it("rejects a malformed month", () => {
    const parsed = rentPaymentCreateSchema.safeParse({ ...valid, month: "Aug-2026" })
    expect(parsed.success).toBe(false)
  })
})

import { describe, it, expect } from "vitest"
import { loginSchema } from "@aapli/validation"
import { computeBill, financialYear } from "@aapli/business"

describe("validation", () => {
  it("rejects short password", () => {
    expect(loginSchema.safeParse({ identifier: "abc", password: "123" }).success).toBe(false)
  })
})

describe("billing", () => {
  it("adds interest after grace days", () => {
    const r = computeBill({
      openingPrincipal: 1000, openingInterest: 0, currentCharges: 500,
      interestRatePctPerMonth: 2, interestAfterDays: 10, daysOverdue: 40,
    })
    expect(r.currentInterest).toBeGreaterThan(0)
    expect(r.closingTotal).toBe(r.totalBillDue)
  })
  it("computes Indian financial year", () => {
    expect(financialYear(new Date("2026-05-01"))).toBe("2026-2027")
    expect(financialYear(new Date("2026-02-01"))).toBe("2025-2026")
  })
})

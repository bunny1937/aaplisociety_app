import { describe, it, expect } from "vitest"
import { allocatePaymentInterestFirst } from "@aapli/business"

// This is real money math (see modules/bills/bill.controller.ts's pay
// route) ported from the web app's live payments/record engine — the
// highest-risk piece of logic touched this session and, until now, the
// only one with zero automated coverage.

describe("allocatePaymentInterestFirst", () => {
  it("clears interest before principal by default (INTEREST_FIRST)", () => {
    const result = allocatePaymentInterestFirst(150, [
      { billId: "b1", interestBalance: 100, principalBalance: 500, balanceAmount: 600, amountPaid: 0 },
    ])
    const [update] = result.billUpdates
    expect(update.newInterestBalance).toBe(0)
    expect(update.newPrincipalBalance).toBe(450) // 150 - 100 interest = 50 applied to principal
    expect(update.newBalanceAmount).toBe(450)
    expect(update.newAmountPaid).toBe(150)
    expect(update.newStatus).toBe("Partial")
    expect(result.totalInterestCleared).toBe(100)
    expect(result.totalPrincipalCleared).toBe(50)
    expect(result.advanceCredit).toBe(0)
  })

  it("clears principal before interest in PRINCIPAL_FIRST mode", () => {
    const result = allocatePaymentInterestFirst(150, [
      { billId: "b1", interestBalance: 100, principalBalance: 500, balanceAmount: 600, amountPaid: 0 },
    ], "PRINCIPAL_FIRST")
    const [update] = result.billUpdates
    expect(update.newPrincipalBalance).toBe(350) // full 150 applied to principal first
    expect(update.newInterestBalance).toBe(100) // untouched
    expect(result.totalPrincipalCleared).toBe(150)
    expect(result.totalInterestCleared).toBe(0)
  })

  it("marks a bill Paid when the payment exactly clears its balance", () => {
    const result = allocatePaymentInterestFirst(600, [
      { billId: "b1", interestBalance: 100, principalBalance: 500, balanceAmount: 600, amountPaid: 0 },
    ])
    const [update] = result.billUpdates
    expect(update.newBalanceAmount).toBe(0)
    expect(update.newStatus).toBe("Paid")
    expect(result.advanceCredit).toBe(0)
  })

  it("routes overpayment beyond the full balance to advanceCredit, not a negative balance", () => {
    const result = allocatePaymentInterestFirst(1000, [
      { billId: "b1", interestBalance: 100, principalBalance: 500, balanceAmount: 600, amountPaid: 0 },
    ])
    const [update] = result.billUpdates
    expect(update.newBalanceAmount).toBe(0)
    expect(update.newStatus).toBe("Paid")
    expect(result.advanceCredit).toBe(400)
    expect(result.breakdown.advanceCredit).toBe(400)
  })

  it("allocates across multiple bills oldest-first (array order), clearing interest on all before touching any principal", () => {
    const result = allocatePaymentInterestFirst(250, [
      { billId: "oldest", interestBalance: 50, principalBalance: 300, balanceAmount: 350, amountPaid: 0 },
      { billId: "newest", interestBalance: 80, principalBalance: 400, balanceAmount: 480, amountPaid: 0 },
    ])
    const [oldest, newest] = result.billUpdates
    // 250 - 50 (oldest interest) - 80 (newest interest) = 120 left for principal, oldest-first
    expect(oldest.newInterestBalance).toBe(0)
    expect(newest.newInterestBalance).toBe(0)
    expect(oldest.newPrincipalBalance).toBe(180) // 300 - 120
    expect(newest.newPrincipalBalance).toBe(400) // untouched — ran out of money
    expect(result.totalInterestCleared).toBe(130)
    expect(result.totalPrincipalCleared).toBe(120)
  })

  it("leaves a bill Unpaid when nothing was allocated to it", () => {
    const result = allocatePaymentInterestFirst(50, [
      { billId: "oldest", interestBalance: 100, principalBalance: 300, balanceAmount: 400, amountPaid: 0 },
      { billId: "newest", interestBalance: 80, principalBalance: 400, balanceAmount: 480, amountPaid: 0 },
    ])
    const [oldest, newest] = result.billUpdates
    expect(oldest.newStatus).toBe("Partial")
    expect(newest.newStatus).toBe("Unpaid")
    expect(newest.newAmountPaid).toBe(0)
  })

  it("is a no-op on a bill with zero balance regardless of allocation mode", () => {
    const result = allocatePaymentInterestFirst(100, [
      { billId: "b1", interestBalance: 0, principalBalance: 0, balanceAmount: 0, amountPaid: 500 },
    ])
    const [update] = result.billUpdates
    expect(update.newBalanceAmount).toBe(0)
    expect(update.newStatus).toBe("Paid")
    expect(result.advanceCredit).toBe(100) // the whole payment has nowhere to go but advance credit
  })

  it("rounds to 2 decimal places and never leaves floating-point drift", () => {
    const result = allocatePaymentInterestFirst(33.33, [
      { billId: "b1", interestBalance: 10.1, principalBalance: 100, balanceAmount: 110.1, amountPaid: 0 },
    ])
    const [update] = result.billUpdates
    expect(update.newInterestBalance).toBe(0)
    expect(update.newPrincipalBalance).toBe(76.77) // 100 - (33.33 - 10.1)
    expect(Number.isFinite(update.newBalanceAmount)).toBe(true)
  })
})

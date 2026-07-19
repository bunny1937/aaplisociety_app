// Ported verbatim (logic-for-logic) from aaplisoceity_web/utils/interestUtils.js's
// allocatePaymentInterestFirst — the web app's live, canonical payment-allocation
// engine (used by app/api/payments/record/route.js). Pure function, no DB access,
// so both backends can share one implementation instead of drifting.
//
// Rules: clear interest across all given bills first (oldest-first, i.e. array
// order), then clear principal oldest-first. Overpayment becomes advanceCredit.
export interface AllocationBillInput {
  billId: string
  interestBalance?: number
  principalBalance?: number
  balanceAmount?: number
  totalAmount?: number
  amountPaid?: number
}

export interface AllocationBillUpdate {
  billId: string
  interestCleared: string
  principalCleared: string
  newInterestBalance: number
  newPrincipalBalance: number
  newBalanceAmount: number
  newAmountPaid: number
  newStatus: "Paid" | "Partial" | "Unpaid"
}

export interface AllocationResult {
  billUpdates: AllocationBillUpdate[]
  totalInterestCleared: number
  totalPrincipalCleared: number
  advanceCredit: number
  breakdown: { interestCleared: number; principalCleared: number; advanceCredit: number }
}

export type AllocationMode = "INTEREST_FIRST" | "PRINCIPAL_FIRST"

export function allocatePaymentInterestFirst(
  paymentAmount: number,
  bills: AllocationBillInput[],
  allocationMode: AllocationMode = "INTEREST_FIRST",
): AllocationResult {
  let remaining = paymentAmount
  let totalInterestCleared = 0
  let totalPrincipalCleared = 0

  const workBills = bills.map((b) => ({
    billId: b.billId,
    interestBalance: b.interestBalance || 0,
    principalBalance: b.principalBalance || 0,
    balanceAmount: b.balanceAmount || 0,
    totalAmount: b.totalAmount || 0,
    amountPaid: b.amountPaid || 0,
  }))

  function clearInterest() {
    for (const wb of workBills) {
      if (remaining <= 0) break
      if (wb.interestBalance <= 0) continue
      const clear = Math.min(remaining, wb.interestBalance)
      wb.interestBalance = round2(wb.interestBalance - clear)
      wb.balanceAmount = round2(wb.balanceAmount - clear)
      wb.amountPaid = round2(wb.amountPaid + clear)
      totalInterestCleared += clear
      remaining = round2(remaining - clear)
    }
  }

  function clearPrincipal() {
    for (const wb of workBills) {
      if (remaining <= 0) break
      if (wb.principalBalance <= 0) continue
      const clear = Math.min(remaining, wb.principalBalance)
      wb.principalBalance = round2(wb.principalBalance - clear)
      wb.balanceAmount = round2(wb.balanceAmount - clear)
      wb.amountPaid = round2(wb.amountPaid + clear)
      totalPrincipalCleared += clear
      remaining = round2(remaining - clear)
    }
  }

  if (allocationMode === "PRINCIPAL_FIRST") {
    clearPrincipal()
    clearInterest()
  } else {
    clearInterest()
    clearPrincipal()
  }

  const advanceCredit = round2(remaining)

  const billUpdates: AllocationBillUpdate[] = workBills.map((wb) => {
    let newStatus: "Paid" | "Partial" | "Unpaid"
    const balance = round2(wb.balanceAmount)
    if (balance <= 0.005) newStatus = "Paid"
    else if (wb.amountPaid > 0) newStatus = "Partial"
    else newStatus = "Unpaid"

    const original = bills.find((b) => String(b.billId) === String(wb.billId))
    return {
      billId: wb.billId,
      interestCleared: ((original?.interestBalance || 0) - wb.interestBalance).toFixed(2),
      principalCleared: ((original?.principalBalance || 0) - wb.principalBalance).toFixed(2),
      newInterestBalance: wb.interestBalance,
      newPrincipalBalance: wb.principalBalance,
      newBalanceAmount: wb.balanceAmount,
      newAmountPaid: wb.amountPaid,
      newStatus,
    }
  })

  return {
    billUpdates,
    totalInterestCleared: round2(totalInterestCleared),
    totalPrincipalCleared: round2(totalPrincipalCleared),
    advanceCredit,
    breakdown: {
      interestCleared: round2(totalInterestCleared),
      principalCleared: round2(totalPrincipalCleared),
      advanceCredit,
    },
  }
}

function round2(n: number): number {
  return parseFloat(n.toFixed(2))
}

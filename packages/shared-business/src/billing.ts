// Interest + closing-balance math ported from lib/billing-engine.js + bill-status-manager.js
export interface BillingInput {
  openingPrincipal: number
  openingInterest: number
  currentCharges: number
  interestRatePctPerMonth: number // Society.config.interestRate
  interestAfterDays: number       // Society.config.interestAfterDays
  daysOverdue: number
}

export interface BillingResult {
  currentInterest: number
  totalBillDue: number
  closingPrincipal: number
  closingInterest: number
  closingTotal: number
}

export function computeBill(i: BillingInput): BillingResult {
  const principalBase = i.openingPrincipal + i.currentCharges
  const chargeInterest =
    i.daysOverdue > i.interestAfterDays
      ? round2(principalBase * (i.interestRatePctPerMonth / 100))
      : 0
  const currentInterest = round2(i.openingInterest + chargeInterest)
  const totalBillDue = round2(principalBase + currentInterest)
  return {
    currentInterest,
    totalBillDue,
    closingPrincipal: round2(principalBase),
    closingInterest: currentInterest,
    closingTotal: totalBillDue,
  }
}

export function financialYear(date = new Date()): string {
  const y = date.getFullYear()
  const m = date.getMonth() // 0-based; FY starts April (m>=3)
  return m >= 3 ? `${y}-${y + 1}` : `${y - 1}-${y}`
}

function round2(n: number): number { return Math.round(n * 100) / 100 }

import { randomObjectId } from "../utils/randomObjectId.js"

// Plain-object builder matching the TransactionSchema shape in src/models/index.ts.
export function makeTransaction(overrides: Record<string, unknown> = {}) {
  return {
    transactionId: `TXN${Math.floor(Math.random() * 1e10)}`,
    date: new Date("2026-05-14"),
    memberId: randomObjectId(),
    societyId: randomObjectId(),
    type: "Debit",
    category: "Maintenance",
    description: "Bill generated for 2026-05",
    amount: 594.25,
    balanceAfterTransaction: 594.25,
    billPeriodId: "2026-05",
    paymentMode: "System",
    ...overrides,
  }
}

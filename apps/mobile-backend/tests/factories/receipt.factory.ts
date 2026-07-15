import { randomObjectId } from "../utils/randomObjectId.js"

// Plain-object builder matching the ReceiptSchema shape in src/models/index.ts.
export function makeReceipt(overrides: Record<string, unknown> = {}) {
  return {
    receiptNo: `RCP-${Date.now()}`,
    billId: randomObjectId(),
    billPeriodId: "2026-05",
    memberId: randomObjectId(),
    societyId: randomObjectId(),
    amount: 594.25,
    paymentMode: "Cash",
    paidAt: new Date("2026-05-13"),
    transactionId: `TXN${Math.floor(Math.random() * 1e10)}`,
    status: "Generated",
    ...overrides,
  }
}

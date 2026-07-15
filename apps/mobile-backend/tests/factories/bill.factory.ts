import { randomObjectId } from "../utils/randomObjectId.js"

// Plain-object builder matching the BillSchema shape in src/models/index.ts.
export function makeBill(overrides: Record<string, unknown> = {}) {
  return {
    societyId: randomObjectId(),
    memberId: randomObjectId(),
    period: "2026-Q1",
    title: "Maintenance Bill",
    principal: 1000,
    interest: 0,
    amount: 1000,
    amountPaid: 0,
    status: "Unpaid",
    dueDate: new Date("2026-08-01"),
    ...overrides,
  }
}

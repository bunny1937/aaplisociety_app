import { randomObjectId } from "../utils/randomObjectId.js"

// Plain-object builder matching the VisitorSchema shape in src/models/index.ts.
export function makeVisitor(overrides: Record<string, unknown> = {}) {
  return {
    societyId: randomObjectId(),
    memberId: randomObjectId(),
    name: "Test Visitor",
    phone: "9999999999",
    photoKey: undefined,
    vehicleNumber: undefined,
    purpose: "Delivery",
    status: "Pending",
    escalationLevel: 1,
    approvedBy: undefined,
    enteredAt: undefined,
    exitedAt: undefined,
    ...overrides,
  }
}

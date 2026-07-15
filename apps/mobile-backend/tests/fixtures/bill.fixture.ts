// Static fixture matching the BillSchema shape in src/models/index.ts.
export const sampleBill = {
  _id: "64b000000000000000000002",
  societyId: "64b000000000000000000010",
  memberId: "64b000000000000000000020",
  period: "2026-Q1",
  title: "Maintenance Bill",
  principal: 1000,
  interest: 0,
  amount: 1000,
  amountPaid: 0,
  status: "Unpaid",
  dueDate: "2026-08-01T00:00:00.000Z",
}

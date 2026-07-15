export const BILL_STATUS = {
  SCHEDULED: "Scheduled",
  UNPAID: "Unpaid",
  PARTIAL: "Partial",
  PAID: "Paid",
  OVERDUE: "Overdue",
} as const
export type BillStatus = (typeof BILL_STATUS)[keyof typeof BILL_STATUS]

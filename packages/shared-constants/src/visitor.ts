export const VISITOR_STATUS = {
  PENDING: "Pending",
  APPROVED: "Approved",
  ENTERED: "Entered",
  EXITED: "Exited",
  REJECTED: "Rejected",
  EXPIRED: "Expired",
} as const
export type VisitorStatus = (typeof VISITOR_STATUS)[keyof typeof VISITOR_STATUS]

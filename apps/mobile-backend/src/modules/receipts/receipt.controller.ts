import { Router } from "express"
import { BILLING_WRITE_ROLES } from "@aapli/constants"
import { Receipt } from "../../models/index.js"
import { requireAuth } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"
import { periodLabelFrom } from "../../lib/periodLabel.js"

export const receiptRouter = Router()
receiptRouter.use(requireAuth, withTenant)

// Members see their own receipts; admins/secretaries see the whole
// society's. Reads the real `receipts` collection (Task 2 model) instead of
// the member app deriving one fake receipt per paid bill client-side.
receiptRouter.get("/", async (req, res) => {
  const isAdmin = BILLING_WRITE_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { societyId: (req as any).societyId }
  if (!isAdmin) filter.memberId = req.auth!.memberId
  const receipts = await Receipt.find(filter).sort({ paidAt: -1, createdAt: -1 }).limit(200).lean()
  return res.json(receipts.map((r: any) => ({
    _id: String(r._id),
    receiptNo: r.receiptNo ?? `RCPT-${String(r._id).slice(-6).toUpperCase()}`,
    periodLabel: periodLabelFrom(r),
    billPeriodId: r.billPeriodId ?? null,
    amount: r.amount ?? 0,
    paymentMode: r.paymentMode ?? null,
    paidAt: r.paidAt ?? r.createdAt ?? null,
    transactionId: r.transactionId ?? null,
    status: r.status ?? "Generated",
  })))
})

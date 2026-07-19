import { Router } from "express"
import { BILLING_WRITE_ROLES } from "@aapli/constants"
import { Transaction } from "../../models/index.js"
import { requireAuth } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"

export const ledgerRouter: Router = Router()
ledgerRouter.use(requireAuth, withTenant)

// Members see their own transaction history; admins/secretaries see the
// whole society's. Reads the real `transactions` collection (Task 2 model)
// instead of the member app deriving debit/credit rows from /bills client-side.
ledgerRouter.get("/", async (req, res) => {
  const isAdmin = BILLING_WRITE_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { societyId: (req as any).societyId }
  if (!isAdmin) filter.memberId = req.auth!.memberId
  const entries = await Transaction.find(filter).sort({ date: -1, createdAt: -1 }).limit(200).lean()
  return res.json(entries.map((e: any) => ({
    _id: String(e._id),
    date: e.date ?? e.createdAt ?? null,
    description: e.description ?? `${e.category ?? "Transaction"}${e.billPeriodId ? ` — ${e.billPeriodId}` : ""}`,
    type: e.type === "Credit" ? "Credit" : "Debit",
    amount: Math.abs(e.amount ?? 0),
    balanceAfterTransaction: e.balanceAfterTransaction ?? null,
    paymentMode: e.paymentMode ?? null,
    billPeriodId: e.billPeriodId ?? null,
  })))
})

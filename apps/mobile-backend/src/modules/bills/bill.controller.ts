import { Router } from "express"
import { paymentSchema, billCreateSchema } from "@aapli/validation"
import { BILL_STATUS, BILLING_WRITE_ROLES, OCCUPANCY_TYPES } from "@aapli/constants"
import { randomUUID } from "node:crypto"
import { Bill, Payment, Member, Transaction, Receipt } from "../../models/index.js"
import { requireAuth, requireRoles } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"
import { billWritesEnabled } from "../../config/env.js"
import { periodLabelFrom } from "../../lib/periodLabel.js"
import { allocatePaymentInterestFirst } from "@aapli/business"

export const billRouter: Router = Router()
billRouter.use(requireAuth, withTenant)

// Members see their own bills; admins/secretaries see the whole society
billRouter.get("/", async (req, res) => {
  if ((req.auth as any).occupancyType === OCCUPANCY_TYPES.TENANT) return res.json([])
  const isAdmin = BILLING_WRITE_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { societyId: (req as any).societyId }
  if (!isAdmin) filter.memberId = req.auth!.memberId
  const bills = await Bill.find(filter).sort({ createdAt: -1 }).limit(200).lean()

  const memberIds = [...new Set(bills.map((b: any) => String(b.memberId)))]
  const members = await Member.find({ _id: { $in: memberIds } })
    .select("ownerName flatNo wing carpetAreaSqft")
    .lean()
  const memberById = new Map(members.map((m: any) => [String(m._id), m]))

  return res.json(bills.map((b: any) => normalizeBill(b, memberById.get(String(b.memberId)))))
})

// Older imported bill docs use totalAmount/totalBillDue instead of amount; unify here
// so every client reads one consistent shape regardless of import source.
// `member` (optional) is the Bill's linked Member doc, used to enrich the
// response with owner/flat/area info the real Bill documents don't carry
// themselves — see Bill Format sheet (bill_format_sheet.dart) which needs it.
function normalizeBill(b: any, member?: any) {
  const amount = b.amount ?? b.totalAmount ?? b.totalBillDue ?? 0
  const amountPaid = b.amountPaid ?? 0
  const status = b.status ?? (amountPaid >= amount ? "Paid" : amountPaid > 0 ? "Partial" : "Unpaid")
  return {
    ...b,
    amount,
    amountPaid,
    status,
    dueDate: b.dueDate ?? null,
    periodLabel: periodLabelFrom(b),
    ownerName: member?.ownerName ?? b.ownerName ?? null,
    flatNo: member?.flatNo ?? b.flatNo ?? null,
    wing: member?.wing ?? b.wing ?? null,
    areaSqft: member?.carpetAreaSqft ?? b.areaSqft ?? null,
    billHtml: b.billHtml && String(b.billHtml).trim().length > 0 ? b.billHtml : buildFallbackBillHtml(b, amount),
  }
}

// Real imported bills (see mongo_export/bills.json) ship a server-rendered
// `billHtml`; bills created via POST /v1/bills below don't. Rather than let
// "Save PDF" have two different code paths depending on bill origin, always
// guarantee *some* printable HTML here.
function buildFallbackBillHtml(b: any, amount: number): string {
  const label = periodLabelFrom(b)
  const charges = b.charges && typeof b.charges === "object" ? b.charges : { [b.title ?? "Maintenance Charges"]: amount }
  const rows = Object.entries(charges)
    .map(([k, v]) => `<tr><td style="padding:6px 0;">${k}</td><td style="padding:6px 0;text-align:right;">₹${v}</td></tr>`)
    .join("")
  return `
<div style="font-family:Arial,sans-serif;font-size:14px;color:#1f2937;padding:24px;max-width:600px;margin:0 auto;">
  <div style="background:linear-gradient(135deg,#1e40af,#3b82f6);color:white;padding:20px;border-radius:10px;margin-bottom:16px;">
    <div style="font-size:11px;letter-spacing:1px;opacity:.8;">MAINTENANCE BILL</div>
    <div style="font-size:18px;font-weight:700;margin-top:4px;">${label}</div>
  </div>
  <table style="width:100%;border-collapse:collapse;">${rows}</table>
  <div style="display:flex;justify-content:space-between;font-weight:700;border-top:2px solid #1e40af;padding-top:8px;margin-top:8px;">
    <span>Total</span><span>₹${amount}</span>
  </div>
</div>`
}

// Admin / Secretary generates a bill for a member
billRouter.post("/", requireRoles(...BILLING_WRITE_ROLES), async (req, res) => {
  if (!billWritesEnabled()) {
    return res.status(403).json({ error: "Bill creation is temporarily disabled. Contact your society admin." })
  }
  const parsed = billCreateSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const bill = await Bill.create({
    ...parsed.data,
    societyId: (req as any).societyId,
    dueDate: parsed.data.dueDate ? new Date(parsed.data.dueDate) : undefined,
    status: BILL_STATUS.UNPAID,
  })
  return res.status(201).json(bill)
})

// Member pays (full or partial) their own bill; admin/secretary can record payment for any bill in the society
billRouter.post("/:id/pay", async (req, res) => {
  const parsed = paymentSchema.safeParse({ ...req.body, billId: req.params.id })
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const isAdmin = BILLING_WRITE_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { _id: req.params.id, societyId: (req as any).societyId }
  if (!isAdmin) filter.memberId = req.auth!.memberId
  const bill = await Bill.findOne(filter)
  if (!bill) return res.status(404).json({ error: "Not found" })
  if (!billWritesEnabled()) {
    return res.status(403).json({ error: "Online payment is not available. Please contact your society admin." })
  }
  const total = (bill as any).amount ?? (bill as any).totalAmount ?? (bill as any).totalBillDue ?? 0
  const amountPaidSoFar = (bill as any).amountPaid ?? 0

  // Canonical interest-first allocation (ported from the web app's live
  // payments/record engine, see @aapli/business/paymentAllocation) instead of
  // a flat amountPaid += x. Real imported bills already carry
  // interestBalance/principalBalance (mirrored from web); mobile-created
  // ad-hoc bills (POST /v1/bills) don't, so derive an initial split from
  // principal/interest, netted against whatever's already been cleared —
  // tracked here via interestCleared/principalCleared (persisted below) since
  // this simpler schema has no balance-split fields of its own.
  const interestBalance = (bill as any).interestBalance ??
    Math.max(0, ((bill as any).interest ?? 0) - ((bill as any).interestCleared ?? 0))
  const principalBalance = (bill as any).principalBalance ??
    Math.max(0, ((bill as any).principal ?? total) - ((bill as any).principalCleared ?? 0))
  const balanceAmount = (bill as any).balanceAmount ?? Math.max(0, total - amountPaidSoFar)

  const allocation = allocatePaymentInterestFirst(
    parsed.data.amount,
    [{ billId: String(bill._id), interestBalance, principalBalance, balanceAmount, totalAmount: total, amountPaid: amountPaidSoFar }],
  )
  const update = allocation.billUpdates[0]

  ;(bill as any).interestBalance = update.newInterestBalance
  ;(bill as any).principalBalance = update.newPrincipalBalance
  ;(bill as any).interestCleared = ((bill as any).interestCleared ?? 0) + allocation.totalInterestCleared
  ;(bill as any).principalCleared = ((bill as any).principalCleared ?? 0) + allocation.totalPrincipalCleared
  ;(bill as any).balanceAmount = update.newBalanceAmount
  ;(bill as any).amountPaid = update.newAmountPaid
  ;(bill as any).status = update.newStatus === "Paid" ? BILL_STATUS.PAID
    : update.newStatus === "Partial" ? BILL_STATUS.PARTIAL : BILL_STATUS.UNPAID
  await bill.save()

  const paid = update.newAmountPaid
  const payingMemberId = isAdmin ? (bill as any).memberId : req.auth!.memberId
  const balanceAfter = update.newBalanceAmount
  const billPeriodId = (bill as any).billPeriodId ?? (bill as any).period ?? null
  const receiptNo = `RCP-${Date.now()}-${randomUUID().replace(/-/g, "").slice(0, 4).toUpperCase()}`
  const txnId = `TXN${randomUUID().replace(/-/g, "").slice(0, 14).toUpperCase()}`

  if (allocation.advanceCredit > 0) {
    await Member.updateOne({ _id: payingMemberId }, { $inc: { advanceCredit: allocation.advanceCredit } })
  }

  await Promise.all([
    Payment.create({
      societyId: (req as any).societyId, billId: bill._id, memberId: payingMemberId,
      amount: parsed.data.amount, paymentMode: parsed.data.paymentMode,
    }),
    Transaction.create({
      transactionId: txnId,
      date: new Date(),
      memberId: payingMemberId,
      societyId: (req as any).societyId,
      createdBy: req.auth!.userId,
      type: "Credit",
      category: "Payment",
      description: `Payment received for ${periodLabelFrom(bill.toObject())}`,
      amount: parsed.data.amount,
      balanceAfterTransaction: balanceAfter,
      referenceId: bill._id,
      referenceModel: "Bill",
      billPeriodId,
      paymentMode: parsed.data.paymentMode,
      interestCleared: allocation.totalInterestCleared,
      principalCleared: allocation.totalPrincipalCleared,
      paymentBreakdown: allocation.breakdown,
    }),
    Receipt.create({
      receiptNo,
      billId: bill._id,
      billPeriodId,
      memberId: payingMemberId,
      societyId: (req as any).societyId,
      amount: parsed.data.amount,
      paymentMode: parsed.data.paymentMode,
      paidAt: new Date(),
      transactionId: txnId,
      status: "Generated",
    }),
  ])

  return res.json({ ...(bill as any).toObject(), amount: total, periodLabel: periodLabelFrom(bill.toObject()) }) // change stream -> PAYMENT_RECEIVED notification
})

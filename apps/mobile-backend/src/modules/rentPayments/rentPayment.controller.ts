import { Router } from "express"
import { rentPaymentCreateSchema } from "@aapli/validation"
import { ROLES } from "@aapli/constants"
import { RentPayment } from "../../models/index.js"
import { requireAuth, requireRoles } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"

export const rentPaymentRouter: Router = Router()
rentPaymentRouter.use(requireAuth, requireRoles(ROLES.MEMBER), withTenant)

// Either the owner or the tenant of a flat may record a rent payment for it.
rentPaymentRouter.post("/", async (req, res) => {
  const parsed = rentPaymentCreateSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })

  const created = await RentPayment.create({
    societyId: (req as any).societyId,
    memberId: req.auth!.memberId,
    recordedByUserId: req.auth!.userId,
    month: parsed.data.month,
    amount: parsed.data.amount,
    paymentMode: parsed.data.paymentMode,
    paidAt: new Date(parsed.data.paidAt),
    notes: parsed.data.notes,
  })
  return res.status(201).json(created)
})

// Shared monthly history for the caller's flat — owner and tenant see the same records.
rentPaymentRouter.get("/", async (req, res) => {
  const items = await RentPayment.find({
    societyId: (req as any).societyId,
    memberId: req.auth!.memberId,
  }).sort({ paidAt: -1 })
  return res.json(items)
})

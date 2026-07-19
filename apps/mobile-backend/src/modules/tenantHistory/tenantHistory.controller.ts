import { Router } from "express"
import { tenantHistoryCreateSchema } from "@aapli/validation"
import { ROLES } from "@aapli/constants"
import { Member } from "../../models/index.js"
import { requireAuth, requireRoles } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"
import { requireOwnerOccupancy } from "../tenantRequests/tenantRequest.controller.js"

export const tenantHistoryRouter: Router = Router()
tenantHistoryRouter.use(requireAuth, requireRoles(ROLES.MEMBER), withTenant, requireOwnerOccupancy)

// Deliberately no approval workflow — unlike TenantRequest (which onboards a
// live tenant login), this is pure record-keeping for a past tenancy the
// owner is backfilling (e.g. pre-dates this system). Per user decision:
// submit and it's saved immediately, visible to admin on the existing
// "View Members" page (which already renders Member.tenantHistory).
tenantHistoryRouter.post("/", async (req, res) => {
  const parsed = tenantHistoryCreateSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })

  const startDate = new Date(parsed.data.startDate)
  const endDate = new Date(parsed.data.endDate)
  if (endDate <= startDate) {
    return res.status(400).json({ error: { fieldErrors: { endDate: ["Must be after the start date"] } } })
  }
  const duration = Math.max(1, Math.round((endDate.getTime() - startDate.getTime()) / (1000 * 60 * 60 * 24 * 30)))

  const entry = {
    name: parsed.data.tenantName,
    contactNumber: parsed.data.tenantPhone,
    email: parsed.data.tenantEmail,
    startDate,
    endDate,
    duration,
    depositAmount: parsed.data.depositAmount ?? 0,
    rentPerMonth: parsed.data.rentPerMonth,
    isCurrent: false,
    moveOutReason: parsed.data.moveOutReason,
  }

  const memberId = req.auth!.memberId
  const societyId = (req as any).societyId
  const result = await Member.updateOne(
    { _id: memberId, societyId },
    { $push: { tenantHistory: entry } },
  )
  if (result.matchedCount === 0) return res.status(404).json({ error: "Flat not found" })

  return res.status(201).json(entry)
})

// Owner's own flat's past-tenant history, most recent first.
tenantHistoryRouter.get("/", async (req, res) => {
  const member = await Member.findOne({
    _id: req.auth!.memberId,
    societyId: (req as any).societyId,
  }).select("tenantHistory").lean()

  const history = ((member as any)?.tenantHistory ?? []) as any[]
  return res.json([...history].sort((a, b) => new Date(b.startDate).getTime() - new Date(a.startDate).getTime()))
})

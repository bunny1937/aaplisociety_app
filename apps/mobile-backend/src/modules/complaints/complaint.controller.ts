import { Router } from "express"
import { complaintSchema, complaintStatusSchema } from "@aapli/validation"
import { SOCIETY_ADMIN_ROLES } from "@aapli/constants"
import { Complaint } from "../../models/index.js"
import { requireAuth, requireRoles } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"

export const complaintRouter = Router()
complaintRouter.use(requireAuth, withTenant)

// Members see their own; admins/secretaries see all complaints in the society
complaintRouter.get("/", async (req, res) => {
  const isAdmin = SOCIETY_ADMIN_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { societyId: (req as any).societyId }
  if (!isAdmin) filter.memberId = req.auth!.memberId
  const items = await Complaint.find(filter).sort({ createdAt: -1 }).limit(200)
  return res.json(items)
})

// Member raises a complaint
complaintRouter.post("/", async (req, res) => {
  const parsed = complaintSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const c = await Complaint.create({
    ...parsed.data,
    societyId: (req as any).societyId,
    memberId: parsed.data.anonymous ? undefined : req.auth!.memberId,
    status: "Open",
  })
  return res.status(201).json(c)
})

// Admin / Secretary updates complaint status (Open -> In progress -> Resolved/Rejected)
complaintRouter.patch("/:id/status", requireRoles(...SOCIETY_ADMIN_ROLES), async (req, res) => {
  const parsed = complaintStatusSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const c = await Complaint.findOneAndUpdate(
    { _id: req.params.id, societyId: (req as any).societyId },
    { status: parsed.data.status, resolutionNote: parsed.data.resolutionNote },
    { new: true },
  )
  if (!c) return res.status(404).json({ error: "Not found" })
  return res.json(c)
})

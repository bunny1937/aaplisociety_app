import { Router } from "express"
import { complaintSchema, complaintStatusSchema } from "@aapli/validation"
import { SOCIETY_ADMIN_ROLES } from "@aapli/constants"
import { Complaint } from "../../models/index.js"
import { requireAuth, requireRoles } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"
import { generateAnonymousName } from "../../lib/anonymousName.js"
import { complaintStatusWritesEnabled } from "../../config/env.js"

export const complaintRouter: Router = Router()
complaintRouter.use(requireAuth, withTenant)

// Members see their own; admins/secretaries see all complaints in the society
complaintRouter.get("/", async (req, res) => {
  const isAdmin = SOCIETY_ADMIN_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { societyId: (req as any).societyId }
  if (!isAdmin) filter.memberId = req.auth!.memberId
  const items = await Complaint.find(filter).sort({ createdAt: -1 }).limit(200)
  return res.json(items)
})

// Member raises a complaint. memberId and anonymousName are ALWAYS stored,
// regardless of the `anonymous` flag — matching web's own behavior exactly
// (web's complaint routes always generate a pseudonym while still requiring
// memberId; "anonymous" there is a display concept, not an untraceable one).
complaintRouter.post("/", async (req, res) => {
  const parsed = complaintSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const c = await Complaint.create({
    ...parsed.data,
    societyId: (req as any).societyId,
    memberId: req.auth!.memberId,
    anonymousName: generateAnonymousName(),
    status: "PENDING",
  })
  return res.status(201).json(c)
})

// Admin / Secretary updates complaint status. Gated: mobile's status
// vocabulary doesn't map cleanly onto web's canonical enum yet (see
// complaintStatusWritesEnabled's doc comment in config/env.ts) — disabled by
// default until that mapping is decided, matching the bill-writes kill switch.
complaintRouter.patch("/:id/status", requireRoles(...SOCIETY_ADMIN_ROLES), async (req, res) => {
  const parsed = complaintStatusSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const existing = await Complaint.findOne({ _id: req.params.id, societyId: (req as any).societyId })
  if (!existing) return res.status(404).json({ error: "Not found" })
  if (!complaintStatusWritesEnabled()) {
    return res.status(403).json({ error: "Complaint status updates are temporarily disabled." })
  }
  existing.status = parsed.data.status
  existing.resolutionNote = parsed.data.resolutionNote
  await existing.save()
  return res.json(existing)
})

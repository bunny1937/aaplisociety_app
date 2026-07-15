import { Router } from "express"
import { visitorCreateSchema, visitorDecisionSchema } from "@aapli/validation"
import { VISITOR_STATUS, ROLES, VISITOR_ACCESS_ROLES } from "@aapli/constants"
import { Visitor } from "../../models/index.js"
import { requireAuth, requireRoles } from "../../middleware/auth.js"
import { requireVisitorAccess } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"

export const visitorRouter = Router()
visitorRouter.use(requireAuth, withTenant)

// Security/admin see the whole society's visitors (gate log + pending queue); members see only their own
visitorRouter.get("/", async (req, res) => {
  const isGuard = VISITOR_ACCESS_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { societyId: (req as any).societyId }
  if (!isGuard) filter.memberId = req.auth!.memberId
  const status = req.query.status as string | undefined
  if (status) filter.status = status
  const visitors = await Visitor.find(filter).sort({ createdAt: -1 }).limit(200)
  return res.json(visitors)
})

// Member raises an expected visitor
visitorRouter.post("/", requireRoles(ROLES.MEMBER), async (req, res) => {
  const parsed = visitorCreateSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const v = await Visitor.create({
    ...parsed.data,
    societyId: (req as any).societyId,
    memberId: req.auth!.memberId,
    status: VISITOR_STATUS.PENDING,
  })
  return res.status(201).json(v)
})

// Member approves/denies their own pending visitor
visitorRouter.post("/:id/decision", requireRoles(ROLES.MEMBER), async (req, res) => {
  const parsed = visitorDecisionSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const status = parsed.data.decision === "approve" ? VISITOR_STATUS.APPROVED : VISITOR_STATUS.REJECTED
  const v = await Visitor.findOneAndUpdate(
    { _id: req.params.id, societyId: (req as any).societyId, memberId: req.auth!.memberId, status: VISITOR_STATUS.PENDING },
    { status, approvedBy: req.auth!.memberId },
    { new: true },
  )
  if (!v) return res.status(404).json({ error: "Not found or already decided" })
  return res.json(v) // change stream -> notification -> security + member
})

// Security marks entry
visitorRouter.post("/:id/enter", requireVisitorAccess, async (req, res) => {
  const v = await Visitor.findOneAndUpdate(
    { _id: req.params.id, societyId: (req as any).societyId },
    { status: VISITOR_STATUS.ENTERED, enteredAt: new Date() },
    { new: true },
  )
  if (!v) return res.status(404).json({ error: "Not found" })
  return res.json(v) // change stream -> event -> notify member
})

// Security marks exit
visitorRouter.post("/:id/exit", requireVisitorAccess, async (req, res) => {
  const v = await Visitor.findOneAndUpdate(
    { _id: req.params.id, societyId: (req as any).societyId },
    { status: VISITOR_STATUS.EXITED, exitedAt: new Date() },
    { new: true },
  )
  if (!v) return res.status(404).json({ error: "Not found" })
  return res.json(v)
})

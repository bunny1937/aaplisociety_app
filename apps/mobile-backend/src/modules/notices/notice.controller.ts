import { Router } from "express"
import { noticeSchema } from "@aapli/validation"
import { SOCIETY_ADMIN_ROLES } from "@aapli/constants"
import { Notice, User } from "../../models/index.js"
import { requireAuth, requireRoles } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"

export const noticeRouter: Router = Router()
noticeRouter.use(requireAuth, withTenant)

// Everyone in the society can read notices (pinned first, then newest)
noticeRouter.get("/", async (req, res) => {
  const items = await Notice.find({ societyId: (req as any).societyId })
    .sort({ pinned: -1, createdAt: -1 })
    .limit(100)
  return res.json(items)
})

// Admin / Secretary posts a notice -> NOTICE_POSTED notification fan-out
noticeRouter.post("/", requireRoles(...SOCIETY_ADMIN_ROLES), async (req, res) => {
  const parsed = noticeSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  // Web's canonical Notice schema requires createdBy + createdByName.
  // Mobile's User has no display `name` field — fall back to username.
  const author = await User.findById(req.auth!.userId).select("username").lean()
  const n = await Notice.create({
    ...parsed.data,
    societyId: (req as any).societyId,
    createdBy: req.auth!.userId,
    createdByName: (author as any)?.username ?? "Admin",
  })
  return res.status(201).json(n)
})

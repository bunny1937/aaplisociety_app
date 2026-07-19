import { Router } from "express"
import { VISITOR_ACCESS_ROLES } from "@aapli/constants"
import { Notification } from "../../models/index.js"
import { requireAuth } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"

export const notificationRouter: Router = Router()
notificationRouter.use(requireAuth, withTenant)

// Admin/Secretary/Security need society-wide visibility (SOS, security
// alerts, gate activity); a Member/Tenant only sees what was actually
// targeted at them.
function recipientFilter(req: any): Record<string, unknown> {
  const societyId = req.societyId
  if (VISITOR_ACCESS_ROLES.includes(req.auth.role)) {
    return { societyId }
  }
  return {
    societyId,
    $or: [
      { recipientType: "all" },
      { recipientType: "member", recipientIds: String(req.auth.memberId) },
      { recipientType: "user", recipientIds: String(req.auth.userId) },
    ],
  }
}

notificationRouter.get("/", async (req, res) => {
  const filter: Record<string, unknown> = { ...recipientFilter(req), isDeleted: { $ne: true } }
  const notifications = await Notification.find(filter).sort({ createdAt: -1 }).limit(100).lean()
  const userId = String(req.auth!.userId)
  const withReadFlag = notifications.map((n: any) => ({
    ...n,
    read: (n.readBy ?? []).some((r: any) => String(r.userId) === userId),
  }))
  return res.json(withReadFlag)
})

notificationRouter.post("/:id/mark-read", async (req, res) => {
  const userId = req.auth!.userId
  const notif = await Notification.findOneAndUpdate(
    { _id: req.params.id, ...recipientFilter(req), "readBy.userId": { $ne: userId } },
    { $push: { readBy: { userId, readAt: new Date() } } },
    { new: true },
  )
  if (!notif) {
    // Either not found/not visible to this user, or already marked read — return current state either way.
    const existing = await Notification.findOne({ _id: req.params.id, ...recipientFilter(req) })
    if (!existing) return res.status(404).json({ error: "Not found" })
    return res.json(existing)
  }
  return res.json(notif)
})

notificationRouter.post("/mark-all-read", async (req, res) => {
  const userId = req.auth!.userId
  await Notification.updateMany(
    { ...recipientFilter(req), isDeleted: { $ne: true }, "readBy.userId": { $ne: userId } },
    { $push: { readBy: { userId, readAt: new Date() } } },
  )
  return res.status(204).end()
})

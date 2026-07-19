import { Router } from "express"
import { deviceRegisterSchema } from "@aapli/validation"
import { DeviceToken } from "../../models/index.js"
import { requireAuth } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"

export const deviceRouter: Router = Router()
deviceRouter.use(requireAuth, withTenant)

// Upsert by fcmToken: a device re-logging in as a different user must be
// reassigned, never left pointing at the previous account (fcmToken is
// unique per physical device/app-install, not per user).
deviceRouter.post("/", async (req, res) => {
  const parsed = deviceRegisterSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const { fcmToken, platform } = parsed.data
  await DeviceToken.findOneAndUpdate(
    { fcmToken },
    { userId: req.auth!.userId, societyId: (req as any).societyId, platform, lastSeenAt: new Date() },
    { upsert: true },
  )
  return res.status(204).end()
})

// Called on logout so a signed-out session stops receiving pushes.
deviceRouter.delete("/:fcmToken", async (req, res) => {
  await DeviceToken.deleteOne({ fcmToken: req.params.fcmToken })
  return res.status(204).end()
})

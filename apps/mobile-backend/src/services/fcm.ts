import { messaging } from "../config/firebase.js"
import { DeviceToken, User } from "../models/index.js"

export interface PushPayload { title: string; body: string }

async function sendToTokens(tokens: string[], payload: PushPayload, data: Record<string, string>): Promise<void> {
  if (tokens.length === 0) return

  const resp = await messaging().sendEachForMulticast({
    tokens,
    notification: { title: payload.title, body: payload.body },
    data,
    android: { priority: "high" },
    apns: { headers: { "apns-priority": "10" } },
  })

  // Prune tokens FCM reports as unregistered
  const stale: string[] = []
  resp.responses.forEach((r, i) => {
    if (!r.success && r.error?.code === "messaging/registration-token-not-registered") {
      stale.push(tokens[i])
    }
  })
  if (stale.length) await DeviceToken.deleteMany({ fcmToken: { $in: stale } })
}

// Fan-out a push to every device registered against a User account
// (POST /devices stores DeviceToken.userId = req.auth.userId, i.e. the
// User._id, not any Member._id).
export async function sendFcmToUser(
  userId: string,
  payload: PushPayload,
  data: Record<string, string> = {},
): Promise<void> {
  const devices = await DeviceToken.find({ userId }).select("fcmToken")
  const tokens = devices.map((d) => (d as any).fcmToken).filter(Boolean)
  await sendToTokens(tokens, payload, Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])))
}

// Domain events (Bill/Visitor/Complaint/Transaction) carry a Member._id, not
// the User account that's logged in — a User can hold this memberId either
// as its top-level `memberId` (legacy single-profile) or inside `profiles[]`
// (multi-profile). Resolve to the owning User first, then send by userId —
// sending directly by memberId always found zero DeviceToken docs and
// silently no-op'd, since registration is keyed by userId.
export async function sendFcmToMember(
  memberId: string,
  payload: PushPayload,
  data: Record<string, string> = {},
): Promise<void> {
  const user = await User.findOne({
    $or: [{ memberId }, { "profiles.memberId": memberId }],
  }).select("_id")
  if (!user) return
  await sendFcmToUser(String(user._id), payload, data)
}

// Society-wide broadcasts (e.g. Notices) — fan out to every device
// registered for the society rather than resolving one member at a time.
export async function sendFcmToSociety(
  societyId: string,
  payload: PushPayload,
  data: Record<string, string> = {},
): Promise<void> {
  const devices = await DeviceToken.find({ societyId }).select("fcmToken")
  const tokens = devices.map((d) => (d as any).fcmToken).filter(Boolean)
  await sendToTokens(tokens, payload, Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])))
}

import { messaging } from "../config/firebase.js"
import { DeviceToken } from "../models/index.js"

export interface PushPayload { title: string; body: string }

// Fan-out a push to every device a user has registered.
export async function sendFcmToUser(
  userId: string,
  payload: PushPayload,
  data: Record<string, string> = {},
): Promise<void> {
  const devices = await DeviceToken.find({ userId }).select("fcmToken")
  const tokens = devices.map((d) => (d as any).fcmToken).filter(Boolean)
  if (tokens.length === 0) return

  const resp = await messaging().sendEachForMulticast({
    tokens,
    notification: { title: payload.title, body: payload.body },
    data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
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

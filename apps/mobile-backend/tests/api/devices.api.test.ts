import { describe, it, expect } from "vitest"
import request from "supertest"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { DeviceToken } from "../../src/models/index.js"

const app = createApp()

describe("POST /v1/devices", () => {
  it("returns 401 with no token", async () => {
    const res = await request(app).post("/v1/devices").send({ fcmToken: "tok-1", platform: "android" })
    expect(res.status).toBe(401)
  })

  it("returns 400 for missing/invalid fields", async () => {
    const token = bearerToken()
    const res = await request(app).post("/v1/devices").set(authHeader(token)).send({ platform: "android" })
    expect(res.status).toBe(400)
    expect(res.body.error.fieldErrors.fcmToken).toBeTruthy()
  })

  it("registers a device token bound to the authenticated user and society", async () => {
    const userId = randomObjectId()
    const societyId = randomObjectId()
    const token = bearerToken({ userId: String(userId), societyId: String(societyId) })

    const res = await request(app)
      .post("/v1/devices")
      .set(authHeader(token))
      .send({ fcmToken: "tok-abc-123", platform: "android" })

    expect(res.status).toBe(204)
    const stored = await DeviceToken.findOne({ fcmToken: "tok-abc-123" })
    expect(stored).toBeTruthy()
    expect(String(stored!.userId)).toBe(String(userId))
    expect(String(stored!.societyId)).toBe(String(societyId))
    expect(stored!.platform).toBe("android")
  })

  it("re-registering the same fcmToken under a different user reassigns it (device re-login)", async () => {
    const firstUser = randomObjectId()
    const secondUser = randomObjectId()
    const societyId = randomObjectId()

    await request(app)
      .post("/v1/devices")
      .set(authHeader(bearerToken({ userId: String(firstUser), societyId: String(societyId) })))
      .send({ fcmToken: "shared-device-tok", platform: "ios" })

    await request(app)
      .post("/v1/devices")
      .set(authHeader(bearerToken({ userId: String(secondUser), societyId: String(societyId) })))
      .send({ fcmToken: "shared-device-tok", platform: "ios" })

    const docs = await DeviceToken.find({ fcmToken: "shared-device-tok" })
    expect(docs).toHaveLength(1)
    expect(String(docs[0]!.userId)).toBe(String(secondUser))
  })
})

describe("DELETE /v1/devices/:fcmToken", () => {
  it("returns 401 with no token", async () => {
    const res = await request(app).delete("/v1/devices/tok-1")
    expect(res.status).toBe(401)
  })

  it("removes the device token so no further pushes go to it (e.g. on logout)", async () => {
    const token = bearerToken()
    await request(app).post("/v1/devices").set(authHeader(token)).send({ fcmToken: "logout-tok", platform: "android" })
    expect(await DeviceToken.findOne({ fcmToken: "logout-tok" })).toBeTruthy()

    const res = await request(app).delete("/v1/devices/logout-tok").set(authHeader(token))
    expect(res.status).toBe(204)
    expect(await DeviceToken.findOne({ fcmToken: "logout-tok" })).toBeNull()
  })

  it("is idempotent when the token doesn't exist", async () => {
    const token = bearerToken()
    const res = await request(app).delete("/v1/devices/never-registered").set(authHeader(token))
    expect(res.status).toBe(204)
  })
})

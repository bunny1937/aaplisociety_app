import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { RentPayment } from "../../src/models/index.js"

const app = createApp()

describe("POST /v1/rent-payments", () => {
  it("records a payment for the caller's own flat", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).post("/v1/rent-payments").set(authHeader(token)).send({
      month: "2026-08", amount: 18000, paymentMode: "UPI", paidAt: "2026-08-03T10:00:00.000Z",
    })
    expect(res.status).toBe(201)
    expect(res.body.amount).toBe(18000)
    expect(res.body.memberId).toBe(String(memberId))
    expect(res.body.societyId).toBe(String(societyId))
  })

  it("accepts paymentMode Online with no gateway processing (recorded like any other mode)", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const res = await request(app).post("/v1/rent-payments").set(authHeader(token)).send({
      month: "2026-08", amount: 18000, paymentMode: "Online", paidAt: "2026-08-03T10:00:00.000Z",
    })
    expect(res.status).toBe(201)
    expect(res.body.paymentMode).toBe("Online")
  })

  it("rejects an invalid paymentMode with 400", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const res = await request(app).post("/v1/rent-payments").set(authHeader(token)).send({
      month: "2026-08", amount: 18000, paymentMode: "Crypto", paidAt: "2026-08-03T10:00:00.000Z",
    })
    expect(res.status).toBe(400)
  })
})

describe("GET /v1/rent-payments", () => {
  it("returns the shared history for the caller's flat, both owner and tenant can read it", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await RentPayment.create({
      societyId, memberId, recordedByUserId: randomObjectId(),
      month: "2026-07", amount: 17500, paymentMode: "Cash", paidAt: new Date("2026-07-03"),
    })
    await RentPayment.create({
      societyId, memberId, recordedByUserId: randomObjectId(),
      month: "2026-08", amount: 18000, paymentMode: "UPI", paidAt: new Date("2026-08-03"),
    })

    const ownerToken = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const ownerRes = await request(app).get("/v1/rent-payments").set(authHeader(ownerToken))
    expect(ownerRes.status).toBe(200)
    expect(ownerRes.body).toHaveLength(2)

    const tenantToken = bearerToken({
      role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId), occupancyType: "Tenant",
    } as any)
    const tenantRes = await request(app).get("/v1/rent-payments").set(authHeader(tenantToken))
    expect(tenantRes.status).toBe(200)
    expect(tenantRes.body).toHaveLength(2)
    expect(tenantRes.body[0].month).toBe("2026-08") // sorted newest first
  })

  it("does not return another flat's rent payments", async () => {
    const societyId = randomObjectId()
    const memberA = randomObjectId()
    const memberB = randomObjectId()
    await RentPayment.create({
      societyId, memberId: memberB, recordedByUserId: randomObjectId(),
      month: "2026-08", amount: 5000, paymentMode: "Cash", paidAt: new Date(),
    })
    const tokenA = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberA) })
    const res = await request(app).get("/v1/rent-payments").set(authHeader(tokenA))
    expect(res.status).toBe(200)
    expect(res.body).toEqual([])
  })
})

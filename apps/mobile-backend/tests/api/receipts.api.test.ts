import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { makeReceipt } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Receipt } from "../../src/models/index.js"

const app = createApp()

describe("GET /v1/receipts", () => {
  it("returns a member's own receipts with a formatted periodLabel", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Receipt.create(makeReceipt({ societyId, memberId, billPeriodId: "2026-05", receiptNo: "RCP-1778759578625-E6RL", amount: 594.25 }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).get("/v1/receipts").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    expect(res.body[0].receiptNo).toBe("RCP-1778759578625-E6RL")
    expect(res.body[0].periodLabel).toBe("May 2026")
    expect(res.body[0].amount).toBe(594.25)
  })

  it("does not return another member's receipts", async () => {
    const societyId = randomObjectId()
    const mine = randomObjectId()
    const theirs = randomObjectId()
    await Receipt.create(makeReceipt({ societyId, memberId: mine }))
    await Receipt.create(makeReceipt({ societyId, memberId: theirs }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(mine) })
    const res = await request(app).get("/v1/receipts").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
  })

  it("returns receipts from every member in the society for an admin (unfiltered by memberId)", async () => {
    const societyId = randomObjectId()
    const memberA = randomObjectId()
    const memberB = randomObjectId()
    await Receipt.create(makeReceipt({ societyId, memberId: memberA, receiptNo: "RCP-MEMBER-A" }))
    await Receipt.create(makeReceipt({ societyId, memberId: memberB, receiptNo: "RCP-MEMBER-B" }))

    const token = bearerToken({ role: ROLES.ADMIN, societyId: String(societyId) })
    const res = await request(app).get("/v1/receipts").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(2)
    const receiptNos = res.body.map((r: any) => r.receiptNo).sort()
    expect(receiptNos).toEqual(["RCP-MEMBER-A", "RCP-MEMBER-B"])
  })

  it("falls back to a generated receiptNo when the receipt has none", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const created = await Receipt.create(makeReceipt({ societyId, memberId, receiptNo: undefined }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).get("/v1/receipts").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    const expectedSuffix = String(created._id).slice(-6).toUpperCase()
    expect(res.body[0].receiptNo).toBe(`RCPT-${expectedSuffix}`)
  })

  it("falls back to null for billPeriodId, paymentMode, transactionId, and to createdAt for paidAt when absent", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const created = await Receipt.create(makeReceipt({
      societyId,
      memberId,
      billPeriodId: undefined,
      paymentMode: undefined,
      transactionId: undefined,
      paidAt: undefined,
    }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).get("/v1/receipts").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    expect(res.body[0].billPeriodId).toBeNull()
    expect(res.body[0].paymentMode).toBeNull()
    expect(res.body[0].transactionId).toBeNull()
    expect(res.body[0].paidAt).toBe((created as any).createdAt.toISOString())
  })
})

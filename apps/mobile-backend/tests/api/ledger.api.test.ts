import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { makeTransaction } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Transaction } from "../../src/models/index.js"

const app = createApp()

describe("GET /v1/ledger", () => {
  it("returns a member's own transactions, newest first, in the normalized shape", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Transaction.create(makeTransaction({ societyId, memberId, date: new Date("2026-05-01"), type: "Debit", amount: 594.25, description: "Bill generated for 2026-05" }))
    await Transaction.create(makeTransaction({ societyId, memberId, date: new Date("2026-05-13"), type: "Credit", amount: 594.25, description: "Payment received" }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).get("/v1/ledger").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(2)
    expect(res.body[0].description).toBe("Payment received") // newest first
    expect(res.body[0].type).toBe("Credit")
    expect(res.body[1].type).toBe("Debit")
  })

  it("does not return another member's transactions", async () => {
    const societyId = randomObjectId()
    const mine = randomObjectId()
    const theirs = randomObjectId()
    await Transaction.create(makeTransaction({ societyId, memberId: mine }))
    await Transaction.create(makeTransaction({ societyId, memberId: theirs }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(mine) })
    const res = await request(app).get("/v1/ledger").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
  })

  it("returns 401 with no token", async () => {
    const res = await request(app).get("/v1/ledger")
    expect(res.status).toBe(401)
  })

  it("returns transactions from every member in the society for an admin (unfiltered by memberId)", async () => {
    const societyId = randomObjectId()
    const memberA = randomObjectId()
    const memberB = randomObjectId()
    await Transaction.create(makeTransaction({ societyId, memberId: memberA, description: "Member A transaction" }))
    await Transaction.create(makeTransaction({ societyId, memberId: memberB, description: "Member B transaction" }))

    const token = bearerToken({ role: ROLES.ADMIN, societyId: String(societyId) })
    const res = await request(app).get("/v1/ledger").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(2)
    const descriptions = res.body.map((t: any) => t.description).sort()
    expect(descriptions).toEqual(["Member A transaction", "Member B transaction"])
  })

  it("returns type \"Debit\" for a non-Credit transaction (ternary false branch)", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Transaction.create(makeTransaction({ societyId, memberId, type: "Debit" }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).get("/v1/ledger").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    expect(res.body[0].type).toBe("Debit")
  })

  it("falls back to a generated description when the transaction has none", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Transaction.create(makeTransaction({ societyId, memberId, category: "Maintenance", billPeriodId: "2026-06", description: undefined }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).get("/v1/ledger").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    expect(res.body[0].description).toBe("Maintenance — 2026-06")
  })

  it("falls back to createdAt when the transaction has no date", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const created = await Transaction.create(makeTransaction({ societyId, memberId, date: undefined }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).get("/v1/ledger").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    expect(res.body[0].date).toBe((created as any).createdAt.toISOString())
  })

  it("falls back to null/\"Transaction\" for a transaction with no category, billPeriodId, balanceAfterTransaction, or paymentMode", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Transaction.create(makeTransaction({
      societyId,
      memberId,
      description: undefined,
      category: undefined,
      billPeriodId: undefined,
      balanceAfterTransaction: undefined,
      paymentMode: undefined,
    }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).get("/v1/ledger").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    expect(res.body[0].description).toBe("Transaction")
    expect(res.body[0].balanceAfterTransaction).toBeNull()
    expect(res.body[0].paymentMode).toBeNull()
    expect(res.body[0].billPeriodId).toBeNull()
  })
})

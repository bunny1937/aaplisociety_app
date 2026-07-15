import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { makeBill, makeMember } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Bill, Payment, Member, Transaction, Receipt } from "../../src/models/index.js"

const app = createApp()

describe("GET /v1/bills", () => {
  it("a member sees only their own bills, filtered by content not just count", async () => {
    const societyId = randomObjectId()
    const member1 = randomObjectId()
    const member2 = randomObjectId()
    const bill1 = await Bill.create(makeBill({ societyId, memberId: member1, amount: 1000 }))
    await Bill.create(makeBill({ societyId, memberId: member2, amount: 2000 }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(member1) })
    const res = await request(app).get("/v1/bills").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    expect(res.body[0]._id).toBe(String(bill1._id))
    expect(res.body[0].memberId).toBe(String(member1))
  })

  it("an admin sees all bills in their own society but not bills from a different society", async () => {
    const societyA = randomObjectId()
    const memberA1 = randomObjectId()
    const memberA2 = randomObjectId()
    const billA1 = await Bill.create(makeBill({ societyId: societyA, memberId: memberA1 }))
    const billA2 = await Bill.create(makeBill({ societyId: societyA, memberId: memberA2 }))

    const societyB = randomObjectId()
    const billB1 = await Bill.create(makeBill({ societyId: societyB, memberId: randomObjectId() }))

    const token = bearerToken({ role: ROLES.ADMIN, societyId: String(societyA) })
    const res = await request(app).get("/v1/bills").set(authHeader(token))
    expect(res.status).toBe(200)
    const ids = res.body.map((b: any) => b._id)
    expect(ids.sort()).toEqual([String(billA1._id), String(billA2._id)].sort())
    expect(ids).not.toContain(String(billB1._id))
  })
})

describe("POST /v1/bills", () => {
  it("rejects Member role with 403", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const res = await request(app).post("/v1/bills").set(authHeader(token)).send({
      memberId: String(randomObjectId()), period: "2026-Q2", amount: 1500,
    })
    expect(res.status).toBe(403)
    expect(res.body).toEqual({ error: "Forbidden" })
  })

  it("creates a bill as Admin with status Unpaid", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const token = bearerToken({ role: ROLES.ADMIN, societyId: String(societyId) })
    const res = await request(app).post("/v1/bills").set(authHeader(token)).send({
      memberId: String(memberId), period: "2026-Q2", amount: 1500, dueDate: "2026-09-01",
    })
    expect(res.status).toBe(201)
    expect(res.body.status).toBe("Unpaid")
    expect(res.body.amount).toBe(1500)
    expect(res.body.societyId).toBe(String(societyId))
    expect(res.body.amountPaid).toBe(0)
  })
})

describe("POST /v1/bills/:id/pay", () => {
  it("a partial payment moves status to Partial, then a second payment completes it to Paid, creating Payment docs", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const bill = await Bill.create(makeBill({ societyId, memberId, amount: 1000, amountPaid: 0 }))
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const first = await request(app).post(`/v1/bills/${bill._id}/pay`).set(authHeader(token)).send({
      amount: 400, paymentMode: "UPI",
    })
    expect(first.status).toBe(200)
    expect(first.body.amountPaid).toBe(400)
    expect(first.body.status).toBe("Partial")

    const second = await request(app).post(`/v1/bills/${bill._id}/pay`).set(authHeader(token)).send({
      amount: 600, paymentMode: "Cash",
    })
    expect(second.status).toBe(200)
    expect(second.body.amountPaid).toBe(1000)
    expect(second.body.status).toBe("Paid")

    const payments = await Payment.find({ billId: bill._id }).sort({ amount: 1 })
    expect(payments).toHaveLength(2)
    expect(payments[0].amount).toBe(400)
    expect(payments[1].amount).toBe(600)
    for (const p of payments) expect(String(p.memberId)).toBe(String(memberId))
  })

  it("critical: a different member cannot pay someone else's bill (404)", async () => {
    const societyId = randomObjectId()
    const owner = randomObjectId()
    const intruder = randomObjectId()
    const bill = await Bill.create(makeBill({ societyId, memberId: owner, amount: 1000, amountPaid: 0 }))
    const intruderToken = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(intruder) })

    const res = await request(app).post(`/v1/bills/${bill._id}/pay`).set(authHeader(intruderToken)).send({
      amount: 500, paymentMode: "UPI",
    })
    expect(res.status).toBe(404)
    expect(res.body).toEqual({ error: "Not found" })

    const unchanged = await Bill.findById(bill._id)
    expect(unchanged!.amountPaid).toBe(0)
  })

  it("an admin can pay any member's bill in their society", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const bill = await Bill.create(makeBill({ societyId, memberId, amount: 1000, amountPaid: 0 }))
    const adminToken = bearerToken({ role: ROLES.ADMIN, societyId: String(societyId) })

    const res = await request(app).post(`/v1/bills/${bill._id}/pay`).set(authHeader(adminToken)).send({
      amount: 1000, paymentMode: "NetBanking",
    })
    expect(res.status).toBe(200)
    expect(res.body.status).toBe("Paid")
    expect(res.body.amountPaid).toBe(1000)
  })

  it("creates a Transaction (Credit) and a Receipt on successful payment", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const bill = await Bill.create(makeBill({ societyId, memberId, billPeriodId: "2026-06", amount: 1000, amountPaid: 0 }))
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).post(`/v1/bills/${bill._id}/pay`).set(authHeader(token)).send({
      amount: 1000, paymentMode: "UPI",
    })
    expect(res.status).toBe(200)

    const txns = await Transaction.find({ referenceId: bill._id })
    expect(txns).toHaveLength(1)
    expect(txns[0].type).toBe("Credit")
    expect(txns[0].amount).toBe(1000)
    expect(String(txns[0].memberId)).toBe(String(memberId))

    const receipts = await Receipt.find({ billId: bill._id })
    expect(receipts).toHaveLength(1)
    expect(receipts[0].amount).toBe(1000)
    expect(receipts[0].receiptNo).toEqual(expect.any(String))
    expect(receipts[0].receiptNo.length).toBeGreaterThan(0)
  })
})

describe("GET /v1/bills enrichment", () => {
  it("always includes a non-null periodLabel, even for bills with neither title nor period fields", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Bill.create({ societyId, memberId, billPeriodId: "2026-05", amount: 442.63, status: "Paid" })
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).get("/v1/bills").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body[0].periodLabel).toBe("May 2026")
    expect(res.body[0].periodLabel).not.toBe("null")
  })

  it("enriches each bill with the linked Member's ownerName/flatNo/wing/areaSqft", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Member.create({ ...makeMember({ ownerName: "Vishal Gupta", flatNo: "1042", wing: "A", carpetAreaSqft: 1500 }), _id: memberId, societyId })
    await Bill.create(makeBill({ societyId, memberId }))
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).get("/v1/bills").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body[0].ownerName).toBe("Vishal Gupta")
    expect(res.body[0].flatNo).toBe("1042")
    expect(res.body[0].wing).toBe("A")
    expect(res.body[0].areaSqft).toBe(1500)
  })

  it("returns ownerName/flatNo/wing/areaSqft: null (never throws) when no Member is linked", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Bill.create(makeBill({ societyId, memberId }))
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).get("/v1/bills").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body[0].ownerName).toBeNull()
  })

  it("always includes non-empty billHtml, synthesizing one from charges when the imported bill has none", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Bill.create({ societyId, memberId, billPeriodId: "2026-05", amount: 240, charges: { "Maintenance Charges": 240 }, status: "Unpaid" })
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).get("/v1/bills").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(typeof res.body[0].billHtml).toBe("string")
    expect(res.body[0].billHtml.length).toBeGreaterThan(0)
    expect(res.body[0].billHtml).toContain("Maintenance Charges")
  })
})

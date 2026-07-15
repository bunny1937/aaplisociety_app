import { describe, it, expect } from "vitest"
import { Member, Society, Transaction, Receipt } from "../../src/models/index.js"
import { makeMember, makeSociety, makeTransaction, makeReceipt } from "../factories/index.js"

describe("Member/Society/Transaction/Receipt models", () => {
  it("persists and reads back a Member with nested parkingSlots/familyMembers", async () => {
    const doc = await Member.create(makeMember({ ownerName: "Tanvi Bansal", flatType: "4BHK" }))
    const found = await Member.findById(doc._id).lean()
    expect(found!.ownerName).toBe("Tanvi Bansal")
    expect(found!.flatType).toBe("4BHK")
    expect((found as any).parkingSlots).toHaveLength(1)
    expect((found as any).parkingSlots[0].slotNumber).toBe("P-B-112")
    expect((found as any).familyMembers).toHaveLength(1)
    expect((found as any).familyMembers[0].name).toBe("Neha Sharma")
  })

  it("persists and reads back a Society", async () => {
    const doc = await Society.create(makeSociety({ name: "Sunrise Complex" }))
    const found = await Society.findById(doc._id).lean()
    expect(found!.name).toBe("Sunrise Complex")
  })

  it("persists and reads back a Transaction", async () => {
    const doc = await Transaction.create(makeTransaction({ type: "Credit", amount: 594.25 }))
    const found = await Transaction.findById(doc._id).lean()
    expect(found!.type).toBe("Credit")
    expect(found!.amount).toBe(594.25)
  })

  it("persists and reads back a Receipt", async () => {
    const doc = await Receipt.create(makeReceipt({ receiptNo: "RCP-TEST-0001" }))
    const found = await Receipt.findById(doc._id).lean()
    expect(found!.receiptNo).toBe("RCP-TEST-0001")
  })
})

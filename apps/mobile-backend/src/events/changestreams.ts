import { Visitor, Bill, Notice } from "../models/index.js"
import { notificationsQueue } from "../queues/index.js"
import { logger } from "../lib/logger.js"

// Mongo change streams (require replica set) -> domain events -> queue
export function watchVisitors() {
  const stream = Visitor.watch([], { fullDocument: "updateLookup" })
  stream.on("change", async (change: any) => {
    if (change.operationType !== "update" && change.operationType !== "insert") return
    const doc = change.fullDocument
    if (!doc) return
    await notificationsQueue.add("visitor-change", {
      visitorId: String(doc._id),
      societyId: String(doc.societyId),
      memberId: doc.memberId ? String(doc.memberId) : null,
      status: doc.status,
      isNew: change.operationType === "insert",
    })
  })
  stream.on("error", (err) => logger.error({ err }, "[changestream] visitors stream error"))
  logger.info("[changestream] watching visitors")
}

export function watchBills() {
  const stream = Bill.watch([], { fullDocument: "updateLookup" })
  stream.on("change", async (change: any) => {
    if (change.operationType !== "update" && change.operationType !== "insert") return
    const doc = change.fullDocument
    if (!doc) return
    await notificationsQueue.add("bill-change", {
      billId: String(doc._id),
      societyId: String(doc.societyId),
      memberId: doc.memberId ? String(doc.memberId) : null,
      status: doc.status,
      amount: doc.amount,
      isNew: change.operationType === "insert",
    })
  })
  stream.on("error", (err) => logger.error({ err }, "[changestream] bills stream error"))
  logger.info("[changestream] watching bills")
}

export function watchNotices() {
  const stream = Notice.watch([], { fullDocument: "updateLookup" })
  stream.on("change", async (change: any) => {
    if (change.operationType !== "insert") return
    const doc = change.fullDocument
    if (!doc) return
    await notificationsQueue.add("notice-change", {
      noticeId: String(doc._id),
      societyId: String(doc.societyId),
      title: doc.title,
    })
  })
  stream.on("error", (err) => logger.error({ err }, "[changestream] notices stream error"))
  logger.info("[changestream] watching notices")
}

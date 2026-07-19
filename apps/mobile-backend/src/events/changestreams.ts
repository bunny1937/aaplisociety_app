import type { Model } from "mongoose"
import { Visitor, Bill, Notice, Complaint, Transaction } from "../models/index.js"
import { notificationsQueue } from "../queues/index.js"
import { logger } from "../lib/logger.js"

const MAX_BACKOFF_MS = 30_000

// Previously a change stream that hit a non-resumable error just logged one
// line and stayed dead for the rest of the process's life — every
// notification for that collection silently stopped firing until a manual
// restart. This wraps every watcher so a closed stream restarts itself with
// capped exponential backoff instead. Resumable errors are already retried
// internally by the MongoDB driver and don't emit 'close', so this only
// kicks in for genuinely dead streams.
function watchWithAutoRestart(name: string, model: Model<any>, onChange: (change: any) => Promise<void> | void, attempt = 1) {
  const stream = model.watch([], { fullDocument: "updateLookup" })
  stream.on("change", (change: any) => { void onChange(change) })
  stream.on("error", (err) => logger.error({ err }, `[changestream] ${name} stream error`))
  stream.on("close", () => {
    const delay = Math.min(1000 * 2 ** (attempt - 1), MAX_BACKOFF_MS)
    logger.warn({ attempt, delayMs: delay }, `[changestream] ${name} stream closed — restarting`)
    setTimeout(() => watchWithAutoRestart(name, model, onChange, attempt + 1), delay)
  })
  if (attempt === 1) logger.info(`[changestream] watching ${name}`)
  else logger.info({ attempt }, `[changestream] ${name} watcher restarted after being closed`)
}

// Mongo change streams (require replica set) -> domain events -> queue
export function watchVisitors() {
  watchWithAutoRestart("visitors", Visitor, async (change) => {
    if (change.operationType !== "update" && change.operationType !== "insert") return
    const doc = change.fullDocument
    if (!doc) return
    await notificationsQueue.add("visitor-change", {
      visitorId: String(doc._id),
      societyId: String(doc.societyId),
      memberId: doc.memberId ? String(doc.memberId) : null,
      status: doc.status,
      entryMethod: doc.entryMethod,
      isBlacklisted: doc.isBlacklisted === true,
      isNew: change.operationType === "insert",
    })
  })
}

export function watchBills() {
  watchWithAutoRestart("bills", Bill, async (change) => {
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
}

export function watchNotices() {
  watchWithAutoRestart("notices", Notice, async (change) => {
    if (change.operationType !== "insert") return
    const doc = change.fullDocument
    if (!doc) return
    await notificationsQueue.add("notice-change", {
      noticeId: String(doc._id),
      societyId: String(doc.societyId),
      title: doc.title,
    })
  })
}

// Notifies the member when their complaint's status changes to APPROVED or
// REJECTED (web's canonical enum — see complaint.controller.ts). Previously
// unwatched: complaint decisions made a real database write but no realtime
// event or push ever fired.
export function watchComplaints() {
  watchWithAutoRestart("complaints", Complaint, async (change) => {
    if (change.operationType !== "update") return
    const doc = change.fullDocument
    if (!doc) return
    await notificationsQueue.add("complaint-change", {
      complaintId: String(doc._id),
      societyId: String(doc.societyId),
      memberId: doc.memberId ? String(doc.memberId) : null,
      status: doc.status,
    })
  })
}

// Watches the ledger directly for "a payment was recorded" rather than
// inferring it from a Bill status change — covers payments written by either
// backend (mobile's pay route, or web's admin record/Excel-import flows)
// with one unambiguous trigger.
export function watchTransactions() {
  watchWithAutoRestart("transactions", Transaction, async (change) => {
    if (change.operationType !== "insert") return
    const doc = change.fullDocument
    if (!doc || doc.type !== "Credit" || doc.category !== "Payment") return
    await notificationsQueue.add("payment-change", {
      transactionId: String(doc._id),
      societyId: String(doc.societyId),
      memberId: doc.memberId ? String(doc.memberId) : null,
      amount: doc.amount,
    })
  })
}

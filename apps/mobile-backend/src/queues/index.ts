import { Queue, Worker } from "bullmq"
import { redis } from "../config/redis.js"
import { Notification, Visitor } from "../models/index.js"
import { VISITOR_STATUS, NOTIFICATION_TYPES, room } from "@aapli/constants"
import { nextEscalation } from "@aapli/business"
import { io } from "../realtime/socket.js"
import { sendFcmToUser } from "../services/fcm.js"
import { logger } from "../lib/logger.js"

const connection = redis as any

export const notificationsQueue = new Queue("notifications", { connection })
export const escalationQueue = new Queue("escalation", { connection })

// Processes domain events -> persists Notification -> emits socket + FCM
export const notificationsWorker = new Worker("notifications", async (job) => {
  if (job.name === "bill-change") return handleBillChange(job.data)
  if (job.name === "notice-change") return handleNoticeChange(job.data)
  return handleVisitorChange(job.data)
}, { connection })
notificationsWorker.on("failed", (job, err) =>
  logger.error({ err, jobId: job?.id, jobName: job?.name, data: job?.data }, "[queue] notifications job failed"))
notificationsWorker.on("error", (err) => logger.error({ err }, "[queue] notifications worker error"))

async function handleVisitorChange(data: any) {
  const { visitorId, societyId, memberId, status, isNew } = data
  let type: string = NOTIFICATION_TYPES.VISITOR_APPROVAL
  if (status === VISITOR_STATUS.ENTERED) type = NOTIFICATION_TYPES.VISITOR_ENTERED
  if (status === VISITOR_STATUS.EXITED) type = NOTIFICATION_TYPES.VISITOR_EXITED

  const notif = await Notification.create({
    societyId, type,
    title: "Visitor update",
    body: `Visitor is now ${status}`,
    recipientType: "member",
    recipientIds: memberId ? [memberId] : [],
    metadata: { visitorId },
  })

  if (memberId) {
    io.to(room.member(memberId)).emit(type, notif)
    await sendFcmToUser(memberId, { title: notif.title!, body: notif.body! }, { type, visitorId })
  }
  // Guard-facing gate log/pending queue needs the same live updates (new request, member's approve/deny, entry/exit)
  io.to(room.security(societyId)).emit(type, notif)

  // Pending approval starts the escalation ladder — only on the visitor's initial
  // creation. The escalation worker's own level-bump writes also flow through this
  // change stream; without the isNew guard, each of its updates re-armed a brand
  // new level-1 chain, causing an exponential storm of escalation jobs/notifications.
  if (isNew && status === VISITOR_STATUS.PENDING) {
    await escalationQueue.add("escalate", { visitorId, level: 1 }, { delay: 60_000 })
  }
}

async function handleBillChange(data: any) {
  const { billId, societyId, memberId, status, amount, isNew } = data
  const type = isNew ? NOTIFICATION_TYPES.BILL_GENERATED : NOTIFICATION_TYPES.PAYMENT_RECEIVED
  const notif = await Notification.create({
    societyId, type,
    title: isNew ? "New bill generated" : "Payment received",
    body: isNew ? `A new bill of Rs ${amount} is due` : `Payment recorded - status: ${status}`,
    recipientType: "member",
    recipientIds: memberId ? [memberId] : [],
    metadata: { billId },
  })
  if (memberId) {
    io.to(room.member(memberId)).emit(type, notif)
    await sendFcmToUser(memberId, { title: notif.title!, body: notif.body! }, { type, billId })
  }
}

async function handleNoticeChange(data: any) {
  const { noticeId, societyId, title } = data
  const notif = await Notification.create({
    societyId, type: NOTIFICATION_TYPES.NOTICE_POSTED,
    title: "New notice", body: title,
    recipientType: "all",
    metadata: { noticeId },
  })
  io.to(room.society(societyId)).emit(NOTIFICATION_TYPES.NOTICE_POSTED, notif)
}

// Escalation worker walks the approved ladder until approved/expired
export const escalationWorker = new Worker("escalation", async (job) => {
  const { visitorId, level } = job.data as any
  const v = await Visitor.findById(visitorId)
  if (!v || v.status !== VISITOR_STATUS.PENDING) return // resolved
  const step = nextEscalation(level - 1)
  if (!step) return
  await Visitor.updateOne({ _id: visitorId }, { escalationLevel: step.level })
  if (v.memberId) {
    await sendFcmToUser(String(v.memberId),
      { title: "Visitor waiting", body: `Escalation level ${step.level}` },
      { type: NOTIFICATION_TYPES.VISITOR_ESCALATION, visitorId })
  }
  const next = nextEscalation(step.level)
  if (next) {
    await escalationQueue.add("escalate", { visitorId, level: step.level + 1 },
      { delay: (next.afterSeconds - step.afterSeconds) * 1000 })
  }
}, { connection })
escalationWorker.on("failed", (job, err) =>
  logger.error({ err, jobId: job?.id, data: job?.data }, "[queue] escalation job failed"))
escalationWorker.on("error", (err) => logger.error({ err }, "[queue] escalation worker error"))

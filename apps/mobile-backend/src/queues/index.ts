import { Queue, Worker } from "bullmq"
import { redis } from "../config/redis.js"
import { Notification, Visitor, TenantRequest, User } from "../models/index.js"
import { VISITOR_STATUS, NOTIFICATION_TYPES, room } from "@aapli/constants"
import { nextEscalation } from "@aapli/business"
import { io } from "../realtime/socket.js"
import { sendFcmToMember, sendFcmToSociety } from "../services/fcm.js"
import { logger } from "../lib/logger.js"

const connection = redis as any

// attempts/backoff apply to every job added to these queues (including calls
// from src/events/changestreams.ts), so a transient Mongo/Redis blip during
// notification persistence or FCM send gets retried instead of silently
// dropping the event — previously these queues used BullMQ's default of a
// single attempt with no retry.
const defaultJobOptions = {
  attempts: 5,
  backoff: { type: "exponential" as const, delay: 5_000 },
}

export const notificationsQueue = new Queue("notifications", { connection, defaultJobOptions })
export const escalationQueue = new Queue("escalation", { connection, defaultJobOptions })
export const tenancyQueue = new Queue("tenancy", { connection, defaultJobOptions: { attempts: 3, backoff: { type: "exponential" as const, delay: 5_000 } } })

// Processes domain events -> persists Notification -> emits socket + FCM
export const notificationsWorker = new Worker("notifications", async (job) => {
  logger.info({ jobName: job.name, data: job.data }, "[queue] processing notification job")
  if (job.name === "bill-change") return handleBillChange(job.data)
  if (job.name === "notice-change") return handleNoticeChange(job.data)
  if (job.name === "complaint-change") return handleComplaintChange(job.data)
  if (job.name === "payment-change") return handlePaymentChange(job.data)
  return handleVisitorChange(job.data)
}, { connection })
notificationsWorker.on("failed", (job, err) =>
  logger.error({ err, jobId: job?.id, jobName: job?.name, data: job?.data, attemptsMade: job?.attemptsMade }, "[queue] notifications job failed"))
notificationsWorker.on("error", (err) => logger.error({ err }, "[queue] notifications worker error"))

async function handleVisitorChange(data: any) {
  const { visitorId, societyId, memberId, status, isNew, entryMethod, isBlacklisted } = data
  let type: string = NOTIFICATION_TYPES.VISITOR_APPROVAL
  if (entryMethod === "SOS") type = NOTIFICATION_TYPES.VISITOR_SOS
  else if (isBlacklisted) type = NOTIFICATION_TYPES.SECURITY_ALERT
  else if (status === VISITOR_STATUS.ENTERED && entryMethod === "Pass") type = NOTIFICATION_TYPES.VISITOR_PASS
  else if (status === VISITOR_STATUS.ENTERED) type = NOTIFICATION_TYPES.VISITOR_ENTERED
  else if (status === VISITOR_STATUS.EXITED) type = NOTIFICATION_TYPES.VISITOR_EXITED

  const notif = await Notification.create({
    societyId, type,
    title: type === NOTIFICATION_TYPES.VISITOR_SOS ? "SOS raised" : "Visitor update",
    message: type === NOTIFICATION_TYPES.VISITOR_SOS ? "A resident has raised an emergency SOS alert." : `Visitor is now ${status}`,
    recipientType: "member",
    recipientIds: memberId ? [memberId] : [],
    metadata: { visitorId },
  })

  if (memberId) {
    io.to(room.member(memberId)).emit(type, notif)
    await sendFcmToMember(memberId, { title: notif.title!, body: notif.message! }, { type, visitorId })
  }
  // Guard-facing gate log/pending queue needs the same live updates (new request, member's approve/deny, entry/exit)
  io.to(room.security(societyId)).emit(type, notif)
  // SOS and watchlist hits are society-wide emergencies — admins/security see them regardless of room membership above.
  if (type === NOTIFICATION_TYPES.VISITOR_SOS || type === NOTIFICATION_TYPES.SECURITY_ALERT) {
    io.to(room.society(societyId)).emit(type, notif)
  }

  // Pending approval starts the escalation ladder — only on the visitor's initial
  // creation. The escalation worker's own level-bump writes also flow through this
  // change stream; without the isNew guard, each of its updates re-armed a brand
  // new level-1 chain, causing an exponential storm of escalation jobs/notifications.
  if (isNew && status === VISITOR_STATUS.PENDING && entryMethod !== "SOS") {
    await escalationQueue.add("escalate", { visitorId, level: 1 }, { delay: 60_000 })
  }
}

async function handleBillChange(data: any) {
  const { billId, societyId, memberId, isNew } = data
  // Payment-driven bill updates are notified via the Transaction watcher
  // (handlePaymentChange below) instead — a Bill can also change status for
  // reasons unrelated to a payment (Overdue sweep, admin edit, scheduled
  // push), so "any Bill update" is not itself a reliable payment signal.
  if (!isNew) return
  const notif = await Notification.create({
    societyId, type: NOTIFICATION_TYPES.BILL_GENERATED,
    title: "New bill generated",
    message: `A new bill of Rs ${data.amount} is due`,
    recipientType: "member",
    recipientIds: memberId ? [memberId] : [],
    metadata: { billId },
  })
  if (memberId) {
    io.to(room.member(memberId)).emit(NOTIFICATION_TYPES.BILL_GENERATED, notif)
    await sendFcmToMember(memberId, { title: notif.title!, body: notif.message! }, { type: NOTIFICATION_TYPES.BILL_GENERATED, billId })
  }
}

// Watches the `transactions` collection directly (see watchTransactions in
// events/changestreams.ts) rather than inferring "a payment happened" from a
// Bill status change — covers payments recorded by either backend (mobile's
// own pay route, or the web app's admin payments/record + Excel-import
// reconciliation flows) with one unambiguous trigger.
async function handlePaymentChange(data: any) {
  const { transactionId, societyId, memberId, amount } = data
  const notif = await Notification.create({
    societyId, type: NOTIFICATION_TYPES.PAYMENT_RECEIVED,
    title: "Payment received",
    message: `A payment of Rs ${amount} was recorded on your account`,
    recipientType: "member",
    recipientIds: memberId ? [memberId] : [],
    metadata: { transactionId },
  })
  if (memberId) {
    io.to(room.member(memberId)).emit(NOTIFICATION_TYPES.PAYMENT_RECEIVED, notif)
    await sendFcmToMember(memberId, { title: notif.title!, body: notif.message! }, { type: NOTIFICATION_TYPES.PAYMENT_RECEIVED, transactionId })
  }
}

async function handleComplaintChange(data: any) {
  const { complaintId, societyId, memberId, status } = data
  if (status !== "APPROVED" && status !== "REJECTED") return
  const type = status === "APPROVED" ? NOTIFICATION_TYPES.COMPLAINT_APPROVED : NOTIFICATION_TYPES.COMPLAINT_REJECTED
  const notif = await Notification.create({
    societyId, type,
    title: status === "APPROVED" ? "Complaint approved" : "Complaint rejected",
    message: status === "APPROVED" ? "Your complaint has been approved and is being addressed." : "Your complaint has been reviewed and rejected.",
    recipientType: "member",
    recipientIds: memberId ? [memberId] : [],
    metadata: { complaintId },
  })
  if (memberId) {
    io.to(room.member(memberId)).emit(type, notif)
    await sendFcmToMember(memberId, { title: notif.title!, body: notif.message! }, { type, complaintId })
  }
}

async function handleNoticeChange(data: any) {
  const { noticeId, societyId, title } = data
  const notif = await Notification.create({
    societyId, type: NOTIFICATION_TYPES.NOTICE_POSTED,
    title: "New notice", message: title,
    recipientType: "all",
    metadata: { noticeId },
  })
  io.to(room.society(societyId)).emit(NOTIFICATION_TYPES.NOTICE_POSTED, notif)
  await sendFcmToSociety(societyId, { title: notif.title!, body: notif.message! }, { type: NOTIFICATION_TYPES.NOTICE_POSTED, noticeId })
}

// Escalation worker walks the approved ladder until approved/expired
export const escalationWorker = new Worker("escalation", async (job) => {
  const { visitorId, level } = job.data as any
  const v = await Visitor.findById(visitorId)
  if (!v || v.status !== VISITOR_STATUS.PENDING) return // resolved
  const step = nextEscalation(level - 1)
  if (!step) return
  await Visitor.updateOne({ _id: visitorId }, {
    "escalation.level": step.level,
    "escalation.lastNotifiedAt": new Date(),
    $push: { "escalation.history": { level: step.level, channel: step.channels[0] ?? "push", at: new Date(), ok: true } },
  })
  if (v.memberId) {
    await sendFcmToMember(String(v.memberId),
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
  logger.error({ err, jobId: job?.id, data: job?.data, attemptsMade: job?.attemptsMade }, "[queue] escalation job failed"))
escalationWorker.on("error", (err) => logger.error({ err }, "[queue] escalation worker error"))

// Daily check: any Approved TenantRequest whose leaseEndDate has passed gets its
// tenant's login temporarily suspended (isActive: false) — not deleted. Exported
// directly (not only reachable via the BullMQ repeatable job below) so tests can
// invoke the actual query/mutation logic without needing a running Redis/worker.
export async function checkLeaseExpiry(): Promise<void> {
  const expired = await TenantRequest.find({
    status: "Approved",
    leaseEndDate: { $lte: new Date() },
    leaseExpiredAt: { $exists: false },
  })

  for (const request of expired) {
    // $elemMatch: both conditions must hold on the SAME profile — a user who
    // owns this flat and separately rents another one must not have their
    // whole login suspended just because some other profile is a Tenant.
    const tenantUser = await User.findOne({
      profiles: { $elemMatch: { memberId: request.memberId, occupancyType: "Tenant" } },
    })
    if (tenantUser) {
      tenantUser.isActive = false
      await tenantUser.save()
    }

    request.leaseExpiredAt = new Date()
    await request.save()

    const notif = await Notification.create({
      societyId: request.societyId,
      type: NOTIFICATION_TYPES.TENANT_LEASE_EXPIRED,
      title: "Tenant lease has ended",
      message: `${request.tenantName}'s tenancy has ended and is pending renewal or move-out confirmation.`,
      recipientType: "member",
      recipientIds: [request.memberId],
      metadata: { tenantRequestId: request._id },
    })
    // Guarded: unlike the notifications/escalation workers (never invoked
    // outside a running server, per docs/testing/README.md's documented
    // testing boundary), checkLeaseExpiry is exported for direct unit-test
    // invocation without initSocket() having run — `io` stays undefined
    // in that context. In production, server.ts always calls initSocket()
    // before scheduleLeaseExpiryCheck(), so this is always live there.
    if (io) {
      io.to(room.member(String(request.memberId))).emit(NOTIFICATION_TYPES.TENANT_LEASE_EXPIRED, notif)
    }
  }
}

const tenancyWorker = new Worker("tenancy", async (job) => {
  if (job.name === "check-lease-expiry") return checkLeaseExpiry()
}, { connection })
tenancyWorker.on("failed", (job, err) =>
  logger.error({ err, jobId: job?.id, jobName: job?.name }, "[queue] tenancy job failed"))
tenancyWorker.on("error", (err) => logger.error({ err }, "[queue] tenancy worker error"))

// Registered once at server startup (see src/server.ts, Step 5 below) — runs daily.
export async function scheduleLeaseExpiryCheck(): Promise<void> {
  await tenancyQueue.add("check-lease-expiry", {}, {
    repeat: { pattern: "0 3 * * *" }, // 03:00 daily
    jobId: "check-lease-expiry", // stable id prevents duplicate repeatable schedules on restart
  })
}

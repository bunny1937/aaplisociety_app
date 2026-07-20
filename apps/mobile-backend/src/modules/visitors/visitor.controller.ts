import { Router } from "express"
import type { Request, Response, NextFunction } from "express"
import multer from "multer"
import crypto from "node:crypto"
import {
  visitorCreateSchema, visitorDecisionSchema, passCreateSchema, passVerifySchema,
  sosSchema, offlineEntrySchema, guardRequestSchema,
} from "@aapli/validation"
import { VISITOR_STATUS, ROLES, VISITOR_ACCESS_ROLES } from "@aapli/constants"
import { Visitor, VisitorPass, Blacklist, Member } from "../../models/index.js"
import { requireAuth, requireRoles } from "../../middleware/auth.js"
import { requireVisitorAccess } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"
import { buildKey, uploadBuffer, presignDownload } from "../../services/storage.js"
import { sosLimiter, passVerifyLimiter } from "../../middleware/rateLimit.js"

export const visitorRouter: Router = Router()
visitorRouter.use(requireAuth, withTenant)

function sha256(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex")
}

// Ported verbatim from web's VisitorPassSchema.methods.isUsableNow
// (models/VisitorPass.js) — window + recurrence (day/time-of-day) + use-count.
// A prior version of this check only tested validFrom/expiresAt/maxUses and
// ignored the recurrence window entirely, which would have let a
// "Recurring" pass (e.g. "weekday mornings only") be used at any time within
// its overall validity window.
function isPassUsableNow(pass: any, now: Date): boolean {
  if (pass.status !== "Active") return false
  if (now < pass.validFrom || now > pass.expiresAt) return false
  if (pass.maxUses > 0 && pass.usedAt.length >= pass.maxUses) return false

  if (pass.passType === "Recurring" && pass.recurrence) {
    const day = now.getDay()
    if (pass.recurrence.days?.length && !pass.recurrence.days.includes(day)) return false
    const hhmm = `${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`
    if (pass.recurrence.startTime && pass.recurrence.endTime
      && (hhmm < pass.recurrence.startTime || hhmm > pass.recurrence.endTime)) return false
  }
  return true
}

function normalizePhone(phone: string): string {
  const digits = String(phone || "").replace(/\D/g, "")
  return digits.length > 10 ? digits.slice(-10) : digits
}

// Watchlist snapshot at the time a visitor row is created — mirrors web's
// Blacklist matching (models/Blacklist.js: normalized-phone lookup).
async function checkBlacklist(societyId: string, phone: string): Promise<{ isBlacklisted: boolean; blacklistReason: string; severity: "flag" | "block" | null }> {
  const normalized = normalizePhone(phone)
  if (!normalized) return { isBlacklisted: false, blacklistReason: "", severity: null }
  const hit = await Blacklist.findOne({ societyId, phone: normalized, active: true })
  if (!hit) return { isBlacklisted: false, blacklistReason: "", severity: null }
  return { isBlacklisted: true, blacklistReason: (hit as any).reason ?? "", severity: (hit as any).severity ?? "flag" }
}

// Security/admin see the whole society's visitors (gate log + pending queue); members see only their own
visitorRouter.get("/", async (req, res) => {
  const isGuard = VISITOR_ACCESS_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { societyId: (req as any).societyId }
  if (!isGuard) filter.memberId = req.auth!.memberId
  const status = req.query.status as string | undefined
  if (status) filter.status = status
  const visitors = await Visitor.find(filter).sort({ createdAt: -1 }).limit(200).lean()
  const enriched = await Promise.all(visitors.map(async (v: any) => ({
    ...v,
    photoUrl: v.photoKey ? await presignDownload(v.photoKey) : v.photo || null,
  })))
  return res.json(enriched)
})

// Member raises an expected visitor
visitorRouter.post("/", requireRoles(ROLES.MEMBER), async (req, res) => {
  const parsed = visitorCreateSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const watchlist = await checkBlacklist((req as any).societyId, parsed.data.phone)
  const v = await Visitor.create({
    ...parsed.data,
    societyId: (req as any).societyId,
    memberId: req.auth!.memberId,
    status: VISITOR_STATUS.PENDING,
    entryMethod: "Manual",
    isBlacklisted: watchlist.isBlacklisted,
    blacklistReason: watchlist.blacklistReason,
  })
  return res.status(201).json(v)
})

// Member approves/denies their own pending visitor
visitorRouter.post("/:id/decision", requireRoles(ROLES.MEMBER), async (req, res) => {
  const parsed = visitorDecisionSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const status = parsed.data.decision === "approve" ? VISITOR_STATUS.APPROVED : VISITOR_STATUS.REJECTED
  const v = await Visitor.findOneAndUpdate(
    { _id: req.params.id, societyId: (req as any).societyId, memberId: req.auth!.memberId, status: VISITOR_STATUS.PENDING },
    { status, approvedBy: req.auth!.userId, approvedAt: new Date(), approverRole: req.auth!.role },
    { new: true },
  )
  if (!v) return res.status(404).json({ error: "Not found or already decided" })
  return res.json(v) // change stream -> notification -> security + member
})

// Security marks entry
visitorRouter.post("/:id/enter", requireVisitorAccess, async (req, res) => {
  const existing = await Visitor.findOne({ _id: req.params.id, societyId: (req as any).societyId })
  if (!existing) return res.status(404).json({ error: "Not found" })
  if ((existing as any).phone) {
    const watchlist = await checkBlacklist((req as any).societyId, (existing as any).phone)
    if (watchlist.severity === "block") return res.status(403).json({ error: `Entry blocked: ${watchlist.blacklistReason}` })
  }
  const v = await Visitor.findOneAndUpdate(
    { _id: req.params.id, societyId: (req as any).societyId },
    { status: VISITOR_STATUS.ENTERED, entryTime: new Date(), enteredBy: req.auth!.userId },
    { new: true },
  )
  return res.json(v) // change stream -> event -> notify member
})

// Security marks exit
visitorRouter.post("/:id/exit", requireVisitorAccess, async (req, res) => {
  const v = await Visitor.findOneAndUpdate(
    { _id: req.params.id, societyId: (req as any).societyId },
    { status: VISITOR_STATUS.EXITED, exitTime: new Date() },
    { new: true },
  )
  if (!v) return res.status(404).json({ error: "Not found" })
  return res.json(v)
})

// Guard denies a visitor that's still awaiting (or already has) resident
// approval — the resident-only path is POST /:id/decision; this is the
// guard's own override for when they're physically at the gate and the
// resident hasn't responded. Restricted to Pending/Approved (mirrors
// /:id/decision's own status filter) so an already Entered/Exited record
// can't be retroactively marked denied.
visitorRouter.post("/:id/deny", requireVisitorAccess, async (req, res) => {
  const v = await Visitor.findOneAndUpdate(
    { _id: req.params.id, societyId: (req as any).societyId, status: { $in: [VISITOR_STATUS.PENDING, VISITOR_STATUS.APPROVED] } },
    { status: VISITOR_STATUS.REJECTED, approvedBy: req.auth!.userId, approvedAt: new Date(), approverRole: req.auth!.role },
    { new: true },
  )
  if (!v) return res.status(404).json({ error: "Not found or already decided" })
  return res.json(v) // change stream -> notification -> member
})

// Guard searches the society's flats/residents to attach a new visitor
// request to a specific member — backs the New Entry screen's "Select
// flat" field. Read-only, no PII beyond what a guard already sees on
// every visitor record (name/flat/phone).
visitorRouter.get("/flats/search", requireVisitorAccess, async (req, res) => {
  const q = String(req.query.q ?? "").trim()
  if (q.length < 1) return res.json([])
  const pattern = q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  const regex = new RegExp(pattern, "i")
  const members = await Member.find({
    societyId: (req as any).societyId,
    isActive: true,
    $or: [{ flatNo: regex }, { wing: regex }, { ownerName: regex }],
  }).select("flatNo wing ownerName contactNumber").limit(20).lean()
  return res.json(members.map((m: any) => ({
    memberId: String(m._id),
    flatNo: m.flatNo ?? "",
    wing: m.wing ?? "",
    ownerName: m.ownerName ?? "",
    contactNumber: m.contactNumber ?? "",
  })))
})

// Guard pings the resident again about a still-pending request. Deliberately
// just touches the document rather than duplicating notification logic: the
// change stream in events/changestreams.ts picks up this update the same
// way it does for every other visitor change, and handleVisitorChange
// (queues/index.ts) creates a fresh Notification + push from it — same
// tested pipeline, no separate code path to keep in sync. Matches web's
// PATCH /api/visitor/remind semantics (push the resident again) minus the
// SMS/WhatsApp channels, which aren't wired on web either right now (no
// MSG91/WhatsApp webhook configured there) — nothing here is faking a send
// that doesn't actually happen.
visitorRouter.patch("/:id/remind", requireVisitorAccess, async (req, res) => {
  const v = await Visitor.findOne({ _id: req.params.id, societyId: (req as any).societyId })
  if (!v) return res.status(404).json({ error: "Not found" })
  if ((v as any).status !== VISITOR_STATUS.PENDING) {
    return res.status(409).json({ error: `Already ${(v as any).status} — nothing to remind` })
  }
  ;(v as any).escalation = (v as any).escalation ?? {}
  ;(v as any).escalation.lastNotifiedAt = new Date()
  await v.save()
  return res.json({ success: true })
})

// Guard raises a gate-side emergency alert — distinct from the member's own
// panic button (POST /sos above): same entryMethod:"SOS" marker so it flows
// through the identical notification path (handleVisitorChange already maps
// entryMethod==="SOS" to NOTIFICATION_TYPES.VISITOR_SOS, broadcast society-wide
// to admins/security), just raised by whoever's at the gate instead of a resident.
visitorRouter.post("/guard-sos", requireVisitorAccess, sosLimiter, async (req, res) => {
  const parsed = sosSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const v = await Visitor.create({
    societyId: (req as any).societyId,
    name: "Guard SOS",
    // VisitorSchema requires `phone` as a non-empty String - an SOS alert has
    // no real visitor phone number, so this is an explicit sentinel, not a
    // fabricated real-looking number (matches "Guard SOS" as the name).
    phone: "0000000000",
    purpose: "Other",
    purposeNote: parsed.data.note ?? "",
    status: VISITOR_STATUS.PENDING,
    entryMethod: "SOS",
    enteredBy: req.auth!.userId,
  })
  return res.status(201).json(v) // change stream -> VISITOR_SOS to security + admin
})

// Member raises a panic/SOS event — highest-priority notification to
// security + admin (see queues/index.ts's handleVisitorChange, which maps
// entryMethod === "SOS" to NOTIFICATION_TYPES.VISITOR_SOS).
visitorRouter.post("/sos", requireRoles(ROLES.MEMBER), sosLimiter, async (req, res) => {
  const parsed = sosSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const v = await Visitor.create({
    societyId: (req as any).societyId,
    memberId: req.auth!.memberId,
    name: "SOS",
    // VisitorSchema requires `phone` as a non-empty String, and Mongoose's
    // required validator rejects "" for String paths - this route was
    // creating a doc that would fail validation on every real call (never
    // caught: no test exercised it). Sentinel value, not a real number.
    phone: "0000000000",
    purpose: "Other",
    purposeNote: parsed.data.note ?? "",
    status: VISITOR_STATUS.PENDING,
    entryMethod: "SOS",
  })
  return res.status(201).json(v) // change stream -> VISITOR_SOS to security + admin
})

// --- Visitor passes (OTP/QR pre-approval) ---

// Member issues a pre-approval pass for an expected visitor
visitorRouter.post("/pass", requireRoles(ROLES.MEMBER), async (req, res) => {
  const parsed = passCreateSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })

  const otp = String(crypto.randomInt(100000, 1000000))
  const qrToken = crypto.randomBytes(24).toString("base64url")

  const pass = await VisitorPass.create({
    societyId: (req as any).societyId,
    memberId: req.auth!.memberId,
    createdBy: req.auth!.userId,
    visitorName: parsed.data.visitorName,
    visitorPhone: parsed.data.visitorPhone,
    purpose: parsed.data.purpose,
    note: parsed.data.note,
    passType: parsed.data.passType,
    recurrence: parsed.data.recurrence,
    validFrom: new Date(parsed.data.validFrom),
    expiresAt: new Date(parsed.data.expiresAt),
    maxUses: parsed.data.maxUses ?? 1,
    otp,
    otpHash: sha256(otp),
    qrTokenHash: sha256(qrToken),
    status: "Active",
  })

  // qrToken alone stays one-time-only (never persisted in plain form); the
  // OTP is kept in plain form on `pass` so the member can pull it up again
  // later from GET /visitors/passes.
  return res.status(201).json({ pass, otp, qrToken })
})

// Member views their own gate passes — kept visible until they expire (and
// for a few days after, until the TTL index on VisitorPass.expiresAt sweeps
// them). Includes the plain `otp` so the member can re-share it any time.
visitorRouter.get("/passes", requireRoles(ROLES.MEMBER), async (req, res) => {
  const passes = await VisitorPass.find({ societyId: (req as any).societyId, memberId: req.auth!.memberId })
    .sort({ createdAt: -1 })
    .limit(100)
    .lean()

  const now = new Date()
  const withStatus = passes.map((p: any) => ({
    ...p,
    qrTokenHash: undefined,
    otpHash: undefined,
    effectiveStatus: p.status !== "Active" ? p.status : now > p.expiresAt ? "Expired" : "Active",
  }))

  return res.json(withStatus)
})

// Guard verifies an OTP or QR token at the gate; on success, auto-enters the visitor.
visitorRouter.post("/pass/verify", requireVisitorAccess, passVerifyLimiter, async (req, res) => {
  const parsed = passVerifySchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })

  const codeHash = sha256(parsed.data.code)
  const pass = await VisitorPass.findOne({
    societyId: (req as any).societyId,
    status: "Active",
    $or: [{ otpHash: codeHash }, { qrTokenHash: codeHash }],
  })
  if (!pass) return res.status(404).json({ error: "Invalid or expired pass" })

  const now = new Date()
  if (!isPassUsableNow(pass, now)) return res.status(410).json({ error: "Pass is no longer usable" })

  const watchlist = await checkBlacklist((req as any).societyId, (pass as any).visitorPhone ?? "")
  if (watchlist.severity === "block") return res.status(403).json({ error: `Entry blocked: ${watchlist.blacklistReason}` })

  const visitor = await Visitor.create({
    societyId: (req as any).societyId,
    memberId: (pass as any).memberId,
    name: (pass as any).visitorName,
    phone: (pass as any).visitorPhone ?? "",
    vehicleNumber: (pass as any).vehicleNumber,
    purpose: (pass as any).purpose,
    status: VISITOR_STATUS.ENTERED,
    entryMethod: "Pass",
    passId: pass._id,
    entryTime: now,
    enteredBy: req.auth!.userId,
    isBlacklisted: watchlist.isBlacklisted,
    blacklistReason: watchlist.blacklistReason,
  })

  ;(pass as any).usedAt.push(now)
  if ((pass as any).maxUses !== 0 && (pass as any).usedAt.length >= (pass as any).maxUses) {
    (pass as any).status = "Used"
  }
  await pass.save()

  return res.json({ visitor, pass }) // change stream -> VISITOR_PASS to member
})

// --- Offline entry (guard captured this while the device had no connectivity) ---

// Idempotent on offlineMeta.clientRef (unique partial index on Visitor, see
// models/index.ts) so a retried sync from the guard app's outbox never
// double-logs the same physical entry.
visitorRouter.post("/offline-entry", requireVisitorAccess, async (req, res) => {
  const parsed = offlineEntrySchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })

  const existing = await Visitor.findOne({ societyId: (req as any).societyId, "offlineMeta.clientRef": parsed.data.clientRef })
  if (existing) return res.status(200).json(existing) // already synced — idempotent replay

  const watchlist = await checkBlacklist((req as any).societyId, parsed.data.phone ?? "")
  if (watchlist.severity === "block") return res.status(403).json({ error: `Entry blocked: ${watchlist.blacklistReason}` })

  const now = new Date()
  const visitor = await Visitor.create({
    societyId: (req as any).societyId,
    name: parsed.data.name,
    phone: parsed.data.phone,
    purpose: parsed.data.purpose,
    vehicleNumber: parsed.data.vehicleNumber,
    status: VISITOR_STATUS.ENTERED,
    entryMethod: "OfflineEntry",
    entryTime: new Date(parsed.data.queuedAt),
    enteredBy: req.auth!.userId,
    isBlacklisted: watchlist.isBlacklisted,
    blacklistReason: watchlist.blacklistReason,
    offlineMeta: {
      wasOffline: true,
      queuedAt: new Date(parsed.data.queuedAt),
      syncedAt: now,
      note: parsed.data.note ?? "",
      clientRef: parsed.data.clientRef,
      confirmation: { status: "Pending" },
    },
  })
  return res.status(201).json(visitor)
})

// --- Guard-initiated visitor request (guard picked a flat, awaits resident approval) ---

// Same idempotent-on-clientRef shape as /offline-entry, but creates a
// Pending visitor tied to a chosen memberId instead of an already-Entered
// one — this is what powers New Entry's "notify the resident" behavior.
// Deliberately status: PENDING + isNew (via Visitor.create, an insert) so
// events/changestreams.ts's watchVisitors -> handleVisitorChange
// (queues/index.ts) picks it up exactly like a member's own POST / does:
// push notification to the resident, socket emit to security, and the
// escalation ladder arms itself automatically. No separate notify code here.
visitorRouter.post("/guard-request", requireVisitorAccess, async (req, res) => {
  const parsed = guardRequestSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })

  const existing = await Visitor.findOne({ societyId: (req as any).societyId, "offlineMeta.clientRef": parsed.data.clientRef })
  if (existing) return res.status(200).json(existing) // already synced — idempotent replay

  const member = await Member.findOne({ _id: parsed.data.memberId, societyId: (req as any).societyId }).lean()
  if (!member) return res.status(404).json({ error: "Flat/resident not found" })

  const watchlist = await checkBlacklist((req as any).societyId, parsed.data.phone ?? "")
  if (watchlist.severity === "block") return res.status(403).json({ error: `Entry blocked: ${watchlist.blacklistReason}` })

  const visitor = await Visitor.create({
    societyId: (req as any).societyId,
    memberId: parsed.data.memberId,
    name: parsed.data.name,
    phone: parsed.data.phone,
    purpose: parsed.data.purpose,
    vehicleNumber: parsed.data.vehicleNumber,
    status: VISITOR_STATUS.PENDING,
    entryMethod: "GuardRequest",
    isBlacklisted: watchlist.isBlacklisted,
    blacklistReason: watchlist.blacklistReason,
    offlineMeta: {
      wasOffline: false,
      queuedAt: new Date(parsed.data.queuedAt),
      syncedAt: new Date(),
      note: parsed.data.note ?? "",
      clientRef: parsed.data.clientRef,
      confirmation: { status: "Pending" },
    },
  })
  return res.status(201).json(visitor) // change stream -> notification + escalation -> member, security
})

// --- Visitor photo upload (guard captures a photo at the gate) ---

const uploadPhoto = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2_097_152 }, // 2MB
  fileFilter: (_req, file, cb) => {
    if (!["image/jpeg", "image/png"].includes(file.mimetype)) return cb(new Error("Unsupported file type"))
    cb(null, true)
  },
}).single("file")

visitorRouter.post("/:id/upload-photo", requireVisitorAccess, (req: Request, res: Response, next: NextFunction) => {
  uploadPhoto(req, res, async (err: unknown) => {
    if (err) return res.status(400).json({ error: err instanceof Error ? err.message : "Upload failed" })
    const file = (req as any).file
    if (!file) return res.status(400).json({ error: "No file provided" })

    const ext = (file.mimetype as string).split("/")[1]
    const key = buildKey((req as any).societyId, "visitors/photo", ext)
    await uploadBuffer(key, file.buffer, file.mimetype)

    const v = await Visitor.findOneAndUpdate(
      { _id: req.params.id, societyId: (req as any).societyId },
      { photoKey: key },
      { new: true },
    )
    if (!v) return res.status(404).json({ error: "Not found" })
    return res.json({ ...(v as any).toObject(), photoUrl: await presignDownload(key) })
  })
})

import { Router } from "express"
import type { Request, Response, NextFunction } from "express"
import multer from "multer"
import { tenantRequestCreateSchema } from "@aapli/validation"
import { OCCUPANCY_TYPES, ROLES } from "@aapli/constants"
import { TenantRequest, Member } from "../../models/index.js"
import { requireAuth, requireRoles } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"
import { buildKey, uploadBuffer } from "../../services/storage.js"
import { detectFileType } from "../../lib/fileSignature.js"

export const tenantRequestRouter: Router = Router()
tenantRequestRouter.use(requireAuth, requireRoles(ROLES.MEMBER), withTenant)

// Only the flat's owner (not a Tenant-occupancy profile) may submit/manage a request.
// Exported for reuse by other owner-only routers (e.g. profileEditRequest.controller.ts).
export function requireOwnerOccupancy(req: Request, res: Response, next: NextFunction) {
  if ((req.auth as any)?.occupancyType === OCCUPANCY_TYPES.TENANT) {
    return res.status(403).json({ error: "Forbidden" })
  }
  next()
}

const FIELD_CONFIG: Record<string, { maxBytes: number; mimeTypes: string[] }> = {
  contract: { maxBytes: 1_048_576, mimeTypes: ["application/pdf"] },
  signature: { maxBytes: 524_288, mimeTypes: ["image/jpeg", "image/png"] },
  aadhaar: { maxBytes: 524_288, mimeTypes: ["image/jpeg", "image/png"] },
  policeVerification: { maxBytes: 524_288, mimeTypes: ["image/jpeg", "image/png"] },
}

function uploadMiddlewareFor(field: string) {
  const config = FIELD_CONFIG[field]
  return multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: config.maxBytes },
    fileFilter: (_req, file, cb) => {
      if (!config.mimeTypes.includes(file.mimetype)) return cb(new Error("Unsupported file type"))
      cb(null, true)
    },
  }).single("file")
}

// One document per call: field is one of contract|signature|aadhaar|policeVerification.
tenantRequestRouter.post("/upload/:field", requireOwnerOccupancy, (req, res) => {
  const field = req.params.field
  const config = FIELD_CONFIG[field]
  if (!config) return res.status(400).json({ error: "Unknown document field" })

  uploadMiddlewareFor(field)(req, res, async (err: unknown) => {
    if (err) return res.status(400).json({ error: err instanceof Error ? err.message : "Upload failed" })
    const file = (req as any).file
    if (!file) return res.status(400).json({ error: "No file provided" })

    // Never trust the client-declared multipart Content-Type for the
    // accept/reject decision, or for what gets stored — it's fully
    // attacker-controlled (e.g. a renamed executable submitted as
    // "aadhaar.jpg" with a spoofed Content-Type would otherwise sail
    // through `fileFilter` above, which only checked this same header).
    // Verify the actual file signature instead, and store the detected
    // type, not the client's claim.
    const detectedType = detectFileType(file.buffer)
    if (!detectedType || !config.mimeTypes.includes(detectedType)) {
      return res.status(400).json({ error: "File content does not match an accepted file type" })
    }

    const ext = detectedType === "application/pdf" ? "pdf" : detectedType.split("/")[1]
    const key = buildKey((req as any).societyId, `tenant-requests/${field}`, ext)
    await uploadBuffer(key, file.buffer, detectedType)
    return res.status(201).json({ key })
  })
})

// Owner submits the intake form, referencing document keys from the upload calls above.
tenantRequestRouter.post("/", requireOwnerOccupancy, async (req, res) => {
  const parsed = tenantRequestCreateSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })

  // Defense in depth: a tampered client could skip /upload/:field entirely
  // and submit an arbitrary string as a document key. This doesn't prove
  // the key came from this caller's own upload, but it does confirm the key
  // is shaped like one this society/field's upload route would have minted
  // — rejecting anything else closes off pointing at unrelated object keys.
  const societyId = (req as any).societyId as string
  for (const [payloadField, key] of Object.entries(parsed.data.documents)) {
    const uploadField = payloadField.replace(/Key$/, "")
    if (!key.startsWith(`${societyId}/tenant-requests/${uploadField}/`)) {
      return res.status(400).json({ error: `Invalid document reference for ${payloadField}` })
    }
  }

  const created = await TenantRequest.create({
    societyId: (req as any).societyId,
    memberId: req.auth!.memberId,
    requestedByUserId: req.auth!.userId,
    tenantName: parsed.data.tenantName,
    tenantPhone: parsed.data.tenantPhone,
    tenantEmail: parsed.data.tenantEmail,
    leaseStartDate: new Date(parsed.data.leaseStartDate),
    leaseEndDate: new Date(parsed.data.leaseEndDate),
    rentPerMonth: parsed.data.rentPerMonth,
    depositAmount: parsed.data.depositAmount ?? 0,
    documents: parsed.data.documents,
    status: "Pending",
  })
  return res.status(201).json(created)
})

// Owner sees every status for their flat; a Tenant-occupancy profile sees only Approved.
tenantRequestRouter.get("/", async (req, res) => {
  const filter: Record<string, unknown> = {
    societyId: (req as any).societyId,
    memberId: req.auth!.memberId,
  }
  if ((req.auth as any).occupancyType === OCCUPANCY_TYPES.TENANT) {
    filter.status = "Approved"
  }
  const items = await TenantRequest.find(filter).sort({ createdAt: -1 })
  return res.json(items)
})

// Owner's half of the two-party permanent close-out (see design spec section 4).
tenantRequestRouter.post("/:id/confirm-move-out", requireOwnerOccupancy, async (req, res) => {
  const found = await TenantRequest.findOne({
    _id: req.params.id,
    societyId: (req as any).societyId,
    memberId: req.auth!.memberId,
  })
  if (!found) return res.status(404).json({ error: "Not found" })

  found.ownerConfirmedMoveOutAt = new Date()

  if (found.adminConfirmedMoveOutAt) {
    await finalizeTenantMoveOut(found)
  } else {
    await found.save()
  }

  return res.json(found)
})

// Mobile-backend's own Member model is a separate strict:false Mongoose model
// pointed at the same collection the web app owns — it cannot call the web
// app's Member.moveCurrentTenantToHistory() method directly (different repo,
// different model definition). This replicates the same three field
// mutations against the shared collection instead, matching the pattern
// already used elsewhere in this codebase (see bill.controller.ts's
// normalizeBill(), which duplicates knowledge of web's Bill shape rather
// than importing web's code).
async function finalizeTenantMoveOut(request: InstanceType<typeof TenantRequest>): Promise<void> {
  const member = await Member.findById(request.memberId)
  if (member && (member as any).currentTenant) {
    const current = (member as any).currentTenant
    await Member.updateOne(
      { _id: request.memberId },
      {
        $push: { tenantHistory: { ...current, isCurrent: false, endDate: new Date() } },
        $unset: { currentTenant: "" },
        $set: { ownershipType: "Owner-Occupied" },
      },
    )
  }
  request.status = "Closed"
  await request.save()
}

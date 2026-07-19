import { z } from "zod"

export const loginSchema = z.object({
  identifier: z.string().min(3),
  password: z.string().min(6),
})

export const profileSelectSchema = z.object({
  profileId: z.string().min(1),
})

// Category/title/description bounds match web's canonical Complaint schema
// exactly (models/Complaint.js in aaplisoceity_web) — this collection is
// shared, so a mismatch here writes documents the web admin UI can't render.
export const complaintSchema = z.object({
  category: z.enum(["noise", "parking", "water", "security", "cleanliness", "maintenance", "billing", "staff", "pets", "other"]),
  title: z.string().min(10).max(120),
  description: z.string().min(30).max(1000),
  anonymous: z.boolean().optional(),
})

// purpose enum matches web's canonical Visitor.purpose exactly (models/Visitor.js)
export const VISITOR_PURPOSES = ["Guest", "Delivery", "Domestic Help", "Vendor", "Cab", "Other"] as const

export const visitorCreateSchema = z.object({
  name: z.string().min(2),
  phone: z.string().regex(/^[0-9]{10}$/),
  purpose: z.enum(VISITOR_PURPOSES),
  purposeNote: z.string().max(300).optional(),
  vehicleNumber: z.string().optional(),
  expectedAt: z.string().datetime().optional(),
})

export const passVerifySchema = z.object({
  code: z.string().min(4),
})

export const sosSchema = z.object({
  note: z.string().max(300).optional(),
})

export const passCreateSchema = z.object({
  visitorName: z.string().min(2),
  visitorPhone: z.string().regex(/^[0-9]{10}$/).optional(),
  purpose: z.enum(VISITOR_PURPOSES).default("Guest"),
  note: z.string().max(300).optional(),
  passType: z.enum(["OneTime", "Recurring", "Frequent"]).default("OneTime"),
  recurrence: z.object({
    days: z.array(z.number().min(0).max(6)).optional(),
    startTime: z.string().optional(),
    endTime: z.string().optional(),
  }).optional(),
  validFrom: z.string().datetime(),
  expiresAt: z.string().datetime(),
  maxUses: z.number().int().min(0).optional(),
})

export const offlineEntrySchema = z.object({
  name: z.string().min(2),
  phone: z.string().regex(/^[0-9]{10}$/),
  purpose: z.enum(VISITOR_PURPOSES),
  vehicleNumber: z.string().optional(),
  queuedAt: z.string().datetime(),
  clientRef: z.string().min(1),
  note: z.string().max(500).optional(),
})

export const visitorDecisionSchema = z.object({
  decision: z.enum(["approve", "deny"]),
})

export const paymentSchema = z.object({
  billId: z.string().min(1),
  amount: z.number().positive(),
  paymentMode: z.enum(["UPI", "NetBanking", "Card", "Cash", "Cheque"]),
})

export const complaintStatusSchema = z.object({
  status: z.enum(["Open", "In progress", "Resolved", "Rejected"]),
  resolutionNote: z.string().max(2000).optional(),
})

// Matches web's canonical Notice schema exactly (models/Notice.js) — this
// collection is shared, so a mismatch here writes documents the web admin
// UI can't render (missing required type/priority/createdBy/createdByName).
export const noticeSchema = z.object({
  type: z.enum(["maintenance", "meeting", "water", "electricity", "parking", "security", "event", "billing", "custom"]),
  priority: z.enum(["low", "medium", "high", "urgent"]).default("medium"),
  title: z.string().min(10).max(150),
  description: z.string().min(30).max(2000),
  pinned: z.boolean().optional(),
})

export const billCreateSchema = z.object({
  memberId: z.string().min(1),
  period: z.string().min(4),
  title: z.string().max(140).optional(),
  amount: z.number().positive(),
  dueDate: z.string().optional(),
})

export const changePasswordSchema = z.object({
  currentPassword: z.string().min(6),
  newPassword: z.string().min(6),
})

export const forgotPasswordSchema = z.object({
  identifier: z.string().min(3),
})

export const resetPasswordSchema = z.object({
  identifier: z.string().min(3),
  code: z.string().regex(/^\d{6}$/),
  newPassword: z.string().min(6),
})

export const deviceRegisterSchema = z.object({
  fcmToken: z.string().min(10),
  platform: z.enum(["android", "ios"]),
})

export const tenantRequestCreateSchema = z.object({
  tenantName: z.string().min(2),
  tenantPhone: z.string().regex(/^[0-9]{10}$/),
  tenantEmail: z.string().email(),
  leaseStartDate: z.string().datetime(),
  leaseEndDate: z.string().datetime(),
  rentPerMonth: z.number().positive(),
  depositAmount: z.number().min(0).optional(),
  documents: z.object({
    contractKey: z.string().min(1),
    signatureKey: z.string().min(1),
    aadhaarKey: z.string().min(1),
    policeVerificationKey: z.string().min(1),
  }),
})

export const rentPaymentCreateSchema = z.object({
  month: z.string().regex(/^\d{4}-\d{2}$/),
  amount: z.number().positive(),
  paymentMode: z.enum(["Cash", "UPI", "BankTransfer", "Cheque", "Online"]),
  paidAt: z.string().datetime(),
  notes: z.string().max(500).optional(),
})

// Owner-submitted, direct-write record of a past (pre-system or otherwise
// unrecorded) tenant — no approval workflow, unlike tenantRequestCreateSchema
// above. Field names match the web app's canonical Member.tenantHistory
// entry shape exactly (models/Member.js's TenantHistorySchema in
// aaplisoceity_web) so a direct $push from mobile-backend renders correctly
// on the existing admin "View Members" page without any web-side changes.
export const tenantHistoryCreateSchema = z.object({
  tenantName: z.string().min(2),
  tenantPhone: z.string().regex(/^[0-9]{10}$/),
  tenantEmail: z.string().email().optional(),
  startDate: z.string().datetime(),
  endDate: z.string().datetime(),
  rentPerMonth: z.number().positive(),
  depositAmount: z.number().min(0).optional(),
  moveOutReason: z.string().max(300).optional(),
})

const phoneField = z.string().regex(/^[0-9]{10}$/)

const contactEditPayloadSchema = z
  .object({
    contactNumber: phoneField.optional(),
    whatsappNumber: phoneField.optional(),
    alternateContact: phoneField.optional(),
  })
  .refine((v) => Object.keys(v).length > 0, { message: "At least one field is required" })

// Field names match the web app's canonical Member.emergencyContact exactly
// (models/Member.js in aaplisoceity_web) — that field already existed there
// before this feature; matching its shape keeps both repos' writes to the
// shared collection compatible.
const emergencyContactEditPayloadSchema = z.object({
  name: z.string().min(2),
  phoneNumber: phoneField,
  relation: z.string().min(1),
  address: z.string().max(200).optional(),
})

const familyMemberPayloadSchema = z.object({
  name: z.string().min(2),
  relation: z.string().min(1),
  age: z.number().int().positive().optional(),
  contactNumber: phoneField.optional(),
  occupation: z.string().optional(),
})

// Owner-submitted, admin-pending edit requests for the shared Member document
// — see docs/superpowers/specs/2026-07-19-profile-restructure-design.md.
// `section` has 3 distinct values but FamilyMember needs 3 sub-variants (one
// per `action`), so `section` alone can't be a discriminatedUnion key — three
// branches would share the value "FamilyMember". Plain z.union instead; the
// literal fields still let TS narrow `parsed.data` on `section`/`action`.
export const profileEditRequestCreateSchema = z.union([
  z.object({ section: z.literal("Contact"), action: z.literal("Edit"), payload: contactEditPayloadSchema }),
  z.object({ section: z.literal("EmergencyContact"), action: z.literal("Edit"), payload: emergencyContactEditPayloadSchema }),
  z.object({ section: z.literal("FamilyMember"), action: z.literal("Add"), payload: familyMemberPayloadSchema }),
  z.object({ section: z.literal("FamilyMember"), action: z.literal("Edit"), familyMemberId: z.string().min(1), payload: familyMemberPayloadSchema }),
  z.object({ section: z.literal("FamilyMember"), action: z.literal("Remove"), familyMemberId: z.string().min(1), payload: z.object({}).strict().optional() }),
])

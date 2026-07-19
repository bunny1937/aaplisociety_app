import { Schema, model, Types } from "mongoose"

const { ObjectId } = Schema.Types

const ProfileSchema = new Schema({
  memberId: { type: ObjectId, ref: "Member" },
  societyId: { type: ObjectId, ref: "Society", index: true },
  role: { type: String, required: true },
  flatNo: String,
  wing: String,
  societyName: String,
  // Web's Member.ProfileSchema.status enum is ["Active","Inactive"] (capital)
  // — match it exactly since both backends write/read this shared collection.
  status: { type: String, default: "Active" },
  // Distinguishes the flat's owner from a tenant sharing the same memberId —
  // see docs/superpowers/specs/2026-07-17-add-tenant-design.md.
  occupancyType: { type: String, enum: ["Owner", "Tenant"], default: "Owner" },
}, { _id: true })

const UserSchema = new Schema({
  username: { type: String, required: true, index: true },
  email: { type: String, index: true },
  passwordHash: { type: String },
  password: { type: String }, // legacy field name used by pre-migration user docs
  role: { type: String, required: true },
  societyId: { type: ObjectId, ref: "Society", index: true },
  memberId: { type: ObjectId, ref: "Member" },
  profiles: [ProfileSchema],
  activeProfileId: ObjectId,
  isActive: { type: Boolean, default: true },
  mustChangePassword: { type: Boolean, default: false },
  resetCodeHash: { type: String },
  resetCodeExpiresAt: { type: Date },
  resetCodeAttempts: { type: Number, default: 0 },
}, { timestamps: true })

const EscalationStepSchema = new Schema({
  level: { type: Number, required: true },
  channel: { type: String, enum: ["in_app", "push", "sms", "whatsapp", "email", "guard_call", "admin_alert"], required: true },
  target: { type: String, default: "" },
  recipientRole: { type: String, default: "" },
  ok: { type: Boolean, default: false },
  error: { type: String, default: "" },
  at: { type: Date, default: Date.now },
}, { _id: false })

// Mirrors the real `visitors` collection — see web's models/Visitor.js.
// strict:false so real web-authored fields survive reads instead of being
// silently dropped (this schema previously had no strict option at all,
// meaning it inherited the strict:true default — the one schema in this file
// that wasn't following the established mirror pattern).
const VisitorSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  memberId: { type: ObjectId, ref: "Member", index: true },
  name: { type: String, required: true },
  phone: { type: String, required: true },
  photo: String,
  // R2 object key for a photo captured/uploaded through the mobile app before
  // a presigned URL is minted — not a web field, kept alongside `photo`.
  photoKey: String,
  vehicleNumber: String,
  purpose: {
    type: String,
    enum: ["Guest", "Delivery", "Domestic Help", "Vendor", "Cab", "Other"],
  },
  purposeNote: String,
  status: { type: String, default: "Pending", index: true },
  entryMethod: { type: String, enum: ["Manual", "Pass", "SOS", "OfflineEntry"], default: "Manual" },
  offlineMeta: {
    wasOffline: { type: Boolean, default: false },
    queuedAt: Date,
    syncedAt: Date,
    note: String,
    clientRef: String,
    confirmation: {
      status: { type: String, enum: ["Pending", "Acknowledged", "Flagged"], default: "Pending" },
      at: Date,
      by: ObjectId,
    },
  },
  passId: { type: ObjectId, ref: "VisitorPass" },
  linkedComplaintId: { type: ObjectId, ref: "Complaint" },
  isBlacklisted: { type: Boolean, default: false },
  blacklistReason: String,
  entryTime: { type: Date, default: Date.now, index: true },
  exitTime: Date,
  expiresAt: Date,
  approvedBy: ObjectId,
  approvedAt: Date,
  approverRole: String,
  enteredBy: ObjectId,
  gateLabel: { type: String, default: "Main Gate" },
  escalation: {
    level: { type: Number, default: 0 },
    stopped: { type: Boolean, default: false },
    lastNotifiedAt: Date,
    history: { type: [EscalationStepSchema], default: [] },
  },
}, { timestamps: true, strict: false })

VisitorSchema.index(
  { societyId: 1, "offlineMeta.clientRef": 1 },
  { unique: true, partialFilterExpression: { "offlineMeta.clientRef": { $type: "string", $gt: "" } } },
)

// Mirrors the real `notifications` collection — see web's models/Notification.js.
const NotificationSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  createdBy: ObjectId,
  createdByName: { type: String, default: "System" },
  type: { type: String, required: true },
  title: String,
  message: String,
  priority: { type: String, enum: ["normal", "high", "critical"], default: "normal" },
  recipientType: { type: String, default: "user" },
  recipientIds: [{ type: String }],
  metadata: Schema.Types.Mixed,
  actionUrl: String,
  readBy: [{
    userId: { type: ObjectId, ref: "User" },
    readAt: { type: Date, default: Date.now },
  }],
  expiresAt: Date,
  isDeleted: { type: Boolean, default: false },
}, { timestamps: true, strict: false })

const DeviceTokenSchema = new Schema({
  userId: { type: ObjectId, ref: "User", required: true, index: true },
  societyId: { type: ObjectId, ref: "Society", index: true },
  fcmToken: { type: String, required: true, unique: true },
  platform: { type: String, enum: ["android", "ios"], required: true },
  lastSeenAt: { type: Date, default: Date.now },
})

const RefreshTokenSchema = new Schema({
  userId: { type: ObjectId, ref: "User", required: true, index: true },
  jti: { type: String, required: true, unique: true },
  revoked: { type: Boolean, default: false },
  expiresAt: { type: Date, index: { expires: 0 } },
}, { timestamps: true })

const BillSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  memberId: { type: ObjectId, ref: "Member", required: true, index: true },
  period: String,
  title: String,
  principal: { type: Number, default: 0 },
  interest: { type: Number, default: 0 },
  amount: { type: Number, required: true },
  amountPaid: { type: Number, default: 0 },
  status: { type: String, default: "Unpaid", index: true },
  dueDate: Date,
}, { timestamps: true, strict: false })

const PaymentSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  billId: { type: ObjectId, ref: "Bill", required: true, index: true },
  memberId: { type: ObjectId, ref: "Member", index: true },
  amount: { type: Number, required: true },
  paymentMode: String,
  reference: String,
}, { timestamps: true })

// Mirrors the real `complaints` collection — see web's models/Complaint.js.
// `anonymousName` is required there and always generated regardless of the
// `anonymous` flag (web's own complaint routes always store a pseudonym —
// "anonymous" is a display concept, not an untraceable one: memberId is
// always required/stored too). strict:false so real web-authored fields
// (adminRejectionReason, reviewedBy, reviewedAt, replyCount, lastReplyAt,
// expiresAt) survive reads instead of being silently dropped.
const ComplaintSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  memberId: { type: ObjectId, ref: "Member", required: true, index: true },
  anonymousName: { type: String, required: true },
  category: { type: String, required: true },
  title: { type: String, required: true },
  description: String,
  status: { type: String, default: "PENDING", index: true },
  anonymous: { type: Boolean, default: false },
  resolutionNote: String,
}, { timestamps: true, strict: false })

// Mirrors the real `notices` collection — see web's models/Notice.js.
// strict:false so real web-authored fields (viewedBy, acknowledgedBy,
// expiresAt, isDeleted) survive reads instead of being silently dropped.
const NoticeSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  createdBy: { type: ObjectId, ref: "User", required: true },
  createdByName: { type: String, required: true },
  type: { type: String, required: true },
  priority: { type: String, default: "medium" },
  title: { type: String, required: true },
  description: String,
  pinned: { type: Boolean, default: false },
}, { timestamps: true, strict: false })

const TenantRequestDocumentsSchema = new Schema({
  contractKey: String,
  signatureKey: String,
  aadhaarKey: String,
  policeVerificationKey: String,
}, { _id: false })

// Owner-submitted, admin-pending tenant onboarding data. Deliberately its own
// collection (not written onto Member.currentTenant) so unapproved/unvalidated
// tenant data never touches the shared `members` collection until the web
// app's admin approval flow accepts it — see the design spec's rationale.
const TenantRequestSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  memberId: { type: ObjectId, ref: "Member", required: true, index: true },
  requestedByUserId: { type: ObjectId, ref: "User", required: true },
  tenantName: { type: String, required: true },
  tenantPhone: { type: String, required: true },
  tenantEmail: { type: String, required: true },
  leaseStartDate: { type: Date, required: true },
  leaseEndDate: { type: Date, required: true },
  rentPerMonth: { type: Number, required: true },
  depositAmount: { type: Number, default: 0 },
  documents: TenantRequestDocumentsSchema,
  status: { type: String, enum: ["Pending", "Approved", "Rejected", "Closed"], default: "Pending", index: true },
  rejectionReason: String,
  approvedBy: { type: ObjectId, ref: "User" },
  approvedAt: Date,
  leaseExpiredAt: Date,
  ownerConfirmedMoveOutAt: Date,
  adminConfirmedMoveOutAt: Date,
}, { timestamps: true })

// Owner-submitted, admin-pending edit request against the shared Member
// document (Contact / FamilyMember / EmergencyContact) — deliberately its
// own collection, same rationale as TenantRequest: proposed values never
// touch the shared `members` collection until the web app's admin approval
// flow accepts them. See profile-restructure design spec.
const ProfileEditRequestSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  memberId: { type: ObjectId, ref: "Member", required: true, index: true },
  requestedByUserId: { type: ObjectId, ref: "User", required: true },
  section: { type: String, enum: ["Contact", "FamilyMember", "EmergencyContact"], required: true },
  action: { type: String, enum: ["Edit", "Add", "Remove"], required: true },
  familyMemberId: ObjectId,
  payload: { type: Schema.Types.Mixed, default: {} },
  status: { type: String, enum: ["Pending", "Approved", "Rejected"], default: "Pending", index: true },
  rejectionReason: String,
  approvedBy: { type: ObjectId, ref: "User" },
  approvedAt: Date,
}, { timestamps: true })

// Shared monthly rent record for a flat's owner and tenant. Record-keeping
// only — "Online" is accepted as a paymentMode value with no gateway behind
// it yet (see design spec's explicitly-deferred scope).
const RentPaymentSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  memberId: { type: ObjectId, ref: "Member", required: true, index: true },
  recordedByUserId: { type: ObjectId, ref: "User", required: true },
  month: { type: String, required: true },
  amount: { type: Number, required: true },
  paymentMode: { type: String, enum: ["Cash", "UPI", "BankTransfer", "Cheque", "Online"], required: true },
  paidAt: { type: Date, required: true },
  notes: String,
}, { timestamps: true })

// Mirrors the real `visitorpasses` collection — see web's models/VisitorPass.js.
// Credentials are hashed at rest; raw OTP/QR token is only ever returned once,
// at creation, to the caller.
const VisitorPassSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  memberId: { type: ObjectId, ref: "Member", required: true, index: true },
  createdBy: { type: ObjectId, ref: "User", required: true },
  visitorName: { type: String, required: true },
  visitorPhone: String,
  visitorPhoto: String,
  vehicleNumber: String,
  purpose: { type: String, enum: ["Guest", "Delivery", "Domestic Help", "Vendor", "Cab", "Other"], default: "Guest" },
  note: String,
  passType: { type: String, enum: ["OneTime", "Recurring", "Frequent"], default: "OneTime" },
  recurrence: {
    days: { type: [Number], default: [] },
    startTime: { type: String, default: "00:00" },
    endTime: { type: String, default: "23:59" },
  },
  validFrom: { type: Date, required: true },
  expiresAt: { type: Date, required: true, index: true },
  maxUses: { type: Number, default: 1 },
  usedAt: [{ type: Date }],
  otpHash: { type: String, required: true, index: true },
  qrTokenHash: { type: String, index: true },
  status: { type: String, enum: ["Active", "Used", "Expired", "Revoked"], default: "Active", index: true },
  revokedBy: { type: ObjectId, ref: "User" },
  revokedAt: Date,
}, { timestamps: true, strict: false })

// Mirrors the real `blacklists` collection — see web's models/Blacklist.js.
const BlacklistSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  name: String,
  phone: { type: String, index: true },
  reason: { type: String, required: true },
  photo: String,
  severity: { type: String, enum: ["flag", "block"], default: "flag" },
  addedBy: { type: ObjectId, ref: "User", required: true },
  active: { type: Boolean, default: true },
}, { timestamps: true, strict: false })

const ParkingSlotSchema = new Schema({
  slotNumber: String,
  type: String,
  vehicleType: String,
  monthlyBilling: Boolean,
}, { _id: false })

// _id enabled (Mongoose default) so each family member has a stable
// reference for edit/remove requests — see profile-restructure design spec.
// Pre-existing subdocuments written before this change are backfilled by
// scripts/backfill-family-member-ids.ts.
const FamilyMemberSchema = new Schema({
  name: String,
  relation: String,
  age: Number,
  contactNumber: String,
  occupation: String,
})

// Mirrors the real `members` collection (see
// apps/mobile-backend/mongo_export/members.json) — richer than the app has
// ever surfaced. `strict: false` + always-`.lean()` reads (see
// modules/auth, modules/bills) so fields present in the real DB but not
// declared here (panCard, aadhaar, securityDeposit, ...) don't get silently
// dropped, while DTOs still explicitly project only the safe subset below.
const MemberSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", index: true },
  userId: { type: ObjectId, ref: "User", index: true },
  flatNo: String,
  wing: String,
  floor: Number,
  carpetAreaSqft: Number,
  builtUpAreaSqft: Number,
  flatType: String,
  parkingSlots: [ParkingSlotSchema],
  isActive: { type: Boolean, default: true },
  ownershipType: String,
  possessionDate: Date,
  ownerName: String,
  contactNumber: String,
  alternateContact: String,
  whatsappNumber: String,
  emailPrimary: String,
  emailSecondary: String,
  familyMembers: [FamilyMemberSchema],
  // Shape matches the web app's canonical Member.emergencyContact exactly
  // (models/Member.js in aaplisoceity_web) — that field already existed
  // there (unpopulated in this app's own data export) before this feature;
  // matching its shape, not inventing a new one, keeps both repos' writes
  // compatible on the shared collection.
  emergencyContact: {
    name: String,
    relation: String,
    phoneNumber: String,
    address: String,
  },
  membershipStatus: String,
  membershipNumber: String,
  hasVotingRights: Boolean,
  // Loosely typed (web owns the real TenantHistorySchema) — written to
  // directly via $push from tenantHistory.controller.ts, which is why
  // `strict: false` below matters: it lets that raw update pass through
  // undeclared. Declared here only so this field shows up in reads/docs.
  currentTenant: Schema.Types.Mixed,
  tenantHistory: [Schema.Types.Mixed],
}, { timestamps: true, strict: false })

// Mirrors the real `societies` collection.
const SocietySchema = new Schema({
  name: String,
  address: String,
  gstNo: String,
  fyStartMonth: Number,
}, { timestamps: true, strict: false })

// Mirrors the real `transactions` collection — the actual member ledger.
const TransactionSchema = new Schema({
  transactionId: String,
  date: Date,
  memberId: { type: ObjectId, ref: "Member", index: true },
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  type: { type: String, required: true }, // "Debit" | "Credit"
  category: String,
  description: String,
  amount: { type: Number, required: true },
  balanceAfterTransaction: Number,
  referenceId: ObjectId,
  referenceModel: String,
  billPeriodId: String,
  paymentMode: String,
}, { timestamps: true, strict: false })

// Mirrors the real `receipts` collection.
const ReceiptSchema = new Schema({
  receiptNo: String,
  filename: String,
  billId: { type: ObjectId, ref: "Bill" },
  billPeriodId: String,
  memberId: { type: ObjectId, ref: "Member", index: true },
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  amount: { type: Number, required: true },
  paymentMode: String,
  paidAt: Date,
  transactionId: String,
  notes: String,
  status: { type: String, default: "Generated" },
}, { timestamps: true, strict: false })

export const User = model("User", UserSchema)
export const Member = model("Member", MemberSchema)
export const Society = model("Society", SocietySchema)
export const Transaction = model("Transaction", TransactionSchema)
export const Receipt = model("Receipt", ReceiptSchema)
export const Visitor = model("Visitor", VisitorSchema)
export const Notification = model("Notification", NotificationSchema)
export const DeviceToken = model("DeviceToken", DeviceTokenSchema)
export const RefreshToken = model("RefreshToken", RefreshTokenSchema)
export const Bill = model("Bill", BillSchema)
export const Payment = model("Payment", PaymentSchema)
export const Complaint = model("Complaint", ComplaintSchema)
export const Notice = model("Notice", NoticeSchema)
export const TenantRequest = model("TenantRequest", TenantRequestSchema)
export const RentPayment = model("RentPayment", RentPaymentSchema)
export const ProfileEditRequest = model("ProfileEditRequest", ProfileEditRequestSchema)
export const VisitorPass = model("VisitorPass", VisitorPassSchema)
export const Blacklist = model("Blacklist", BlacklistSchema)
export { Types }

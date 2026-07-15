import { Schema, model, Types } from "mongoose"

const { ObjectId } = Schema.Types

const ProfileSchema = new Schema({
  memberId: { type: ObjectId, ref: "Member" },
  societyId: { type: ObjectId, ref: "Society", index: true },
  role: { type: String, required: true },
  flatNo: String,
  wing: String,
  societyName: String,
  status: { type: String, default: "active" },
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
}, { timestamps: true })

const VisitorSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  memberId: { type: ObjectId, ref: "Member", index: true },
  name: { type: String, required: true },
  phone: { type: String, required: true },
  photoKey: String,
  vehicleNumber: String,
  purpose: String,
  status: { type: String, default: "Pending", index: true },
  escalationLevel: { type: Number, default: 1 },
  approvedBy: ObjectId,
  enteredAt: Date,
  exitedAt: Date,
}, { timestamps: true })

const NotificationSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  type: { type: String, required: true },
  title: String,
  body: String,
  priority: { type: String, default: "normal" },
  recipientType: { type: String, default: "user" },
  recipientIds: [{ type: ObjectId }],
  metadata: Schema.Types.Mixed,
  actionUrl: String,
  readBy: [{ type: ObjectId }],
  expiresAt: Date,
}, { timestamps: true })

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

const ComplaintSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  memberId: { type: ObjectId, ref: "Member", index: true },
  category: { type: String, required: true },
  title: { type: String, required: true },
  description: String,
  status: { type: String, default: "Open", index: true },
  anonymous: { type: Boolean, default: false },
  resolutionNote: String,
}, { timestamps: true })

const NoticeSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  title: { type: String, required: true },
  body: String,
  tag: { type: String, default: "General" },
  postedBy: { type: ObjectId, ref: "User" },
  pinned: { type: Boolean, default: false },
}, { timestamps: true })

const ParkingSlotSchema = new Schema({
  slotNumber: String,
  type: String,
  vehicleType: String,
  monthlyBilling: Boolean,
}, { _id: false })

const FamilyMemberSchema = new Schema({
  name: String,
  relation: String,
  age: Number,
  contactNumber: String,
  occupation: String,
}, { _id: false })

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
  membershipStatus: String,
  membershipNumber: String,
  hasVotingRights: Boolean,
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
export { Types }

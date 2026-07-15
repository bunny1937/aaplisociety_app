import { z } from "zod"

export const loginSchema = z.object({
  identifier: z.string().min(3),
  password: z.string().min(6),
})

export const profileSelectSchema = z.object({
  profileId: z.string().min(1),
})

export const complaintSchema = z.object({
  category: z.enum(["noise", "parking", "water", "security", "maintenance", "other"]),
  title: z.string().min(3).max(120),
  description: z.string().min(5).max(2000),
  anonymous: z.boolean().optional(),
})

export const visitorCreateSchema = z.object({
  name: z.string().min(2),
  phone: z.string().regex(/^[0-9]{10}$/),
  purpose: z.string().min(2),
  vehicleNumber: z.string().optional(),
  expectedAt: z.string().datetime().optional(),
})

export const passVerifySchema = z.object({
  code: z.string().min(4),
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

export const noticeSchema = z.object({
  title: z.string().min(3).max(140),
  body: z.string().min(3).max(4000),
  tag: z.enum(["General", "Urgent", "Event", "Community", "Maintenance"]).optional(),
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

export const deviceRegisterSchema = z.object({
  fcmToken: z.string().min(10),
  platform: z.enum(["android", "ios"]),
})

export const addMemberSchema = z.object({
  username: z.string().min(3),
  email: z.string().email().optional(),
  flatNo: z.string().min(1),
  wing: z.string().optional(),
  role: z.enum(["Member", "Secretary", "Accountant", "Security"]).optional(),
})

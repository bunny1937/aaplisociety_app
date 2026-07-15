import type { Role } from "@aapli/constants"
import type { VisitorStatus } from "@aapli/constants"
import type { BillStatus } from "@aapli/constants"

export interface Profile {
  profileId: string
  memberId: string
  societyId: string
  role: Role
  flatNo: string
  wing: string
  societyName: string
  status: "active" | "inactive"
}

export interface User {
  _id: string
  username: string
  email?: string
  role: Role
  societyId?: string
  memberId?: string
  profiles: Profile[]
  activeProfileId?: string
  isActive: boolean
}

export interface Bill {
  _id: string
  societyId: string
  memberId: string
  billPeriodId: string
  billMonth: number
  billYear: number
  openingPrincipal: number
  openingInterest: number
  currentCharges: number
  currentInterest: number
  totalBillDue: number
  closingTotal: number
  charges: Record<string, number>
  status: BillStatus
  scheduledPushDate?: string
}

export interface Visitor {
  _id: string
  societyId: string
  memberId: string
  name: string
  phone: string
  photoKey?: string // R2 object key (replaces inline URL)
  vehicleNumber?: string
  purpose: string
  status: VisitorStatus
  createdAt: string
}

export interface Notification {
  _id: string
  societyId: string
  type: string
  title: string
  body: string
  priority: "low" | "normal" | "high" | "urgent"
  recipientType: string
  recipientIds: string[]
  metadata?: Record<string, unknown>
  actionUrl?: string
  readBy: string[]
  expiresAt?: string
  createdAt: string
}

export interface DeviceToken {
  _id: string
  userId: string
  societyId: string
  fcmToken: string
  platform: "android" | "ios"
  lastSeenAt: string
}

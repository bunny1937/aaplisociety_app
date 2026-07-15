export const ROLES = {
  SUPER_ADMIN: "SuperAdmin",
  ADMIN: "Admin",
  SECRETARY: "Secretary",
  ACCOUNTANT: "Accountant",
  SECURITY: "Security",
  MEMBER: "Member",
} as const

export type Role = (typeof ROLES)[keyof typeof ROLES]

// Lifted verbatim from lib/authz.js
export const SOCIETY_ADMIN_ROLES: Role[] = [ROLES.ADMIN, ROLES.SECRETARY]
export const BILLING_WRITE_ROLES: Role[] = [ROLES.ADMIN, ROLES.SECRETARY]
export const VISITOR_ACCESS_ROLES: Role[] = [ROLES.ADMIN, ROLES.SECRETARY, ROLES.SECURITY]

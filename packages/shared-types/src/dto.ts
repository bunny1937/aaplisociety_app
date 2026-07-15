import type { Role } from "@aapli/constants"

export interface LoginRequest { identifier: string; password: string }
export interface AuthTokens { accessToken: string; refreshToken: string }
export interface LoginResponse {
  tokens?: AuthTokens
  role?: Role
  needsProfileSelect?: boolean
  profiles?: { profileId: string; societyName: string; flatNo: string }[]
  selectToken?: string
  mustChangePassword?: boolean
}
export interface JwtClaims {
  userId: string
  role: Role
  societyId?: string
  memberId?: string
  activeProfileId?: string
  societyCode?: string
  pending?: boolean
  mustChangePassword?: boolean
}

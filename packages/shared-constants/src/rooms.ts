// Approved socket room naming convention
export const room = {
  society: (societyId: string) => `society_${societyId}`,
  member: (memberId: string) => `member_${memberId}`,
  security: (societyId: string) => `security_${societyId}`,
  user: (userId: string) => `user_${userId}`,
  wing: (societyId: string, wing: string) => `wing_${societyId}_${wing}`,
}

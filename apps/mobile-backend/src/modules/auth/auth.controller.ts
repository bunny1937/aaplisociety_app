import { Router } from "express"
import bcrypt from "bcryptjs"
import { randomUUID } from "node:crypto"
import { loginSchema, profileSelectSchema, changePasswordSchema, addMemberSchema } from "@aapli/validation"
import { SOCIETY_ADMIN_ROLES } from "@aapli/constants"
import { signAccess, signRefresh, verifyRefresh, refreshExpiresAt } from "../../lib/jwt.js"
import { User, RefreshToken, Member, Society, Types } from "../../models/index.js"
import { requireAuth, requireAuthAllowPending, requireRoles } from "../../middleware/auth.js"
import { loginLimiter } from "../../middleware/rateLimit.js"

export const authRouter = Router()

// Unified role-aware login for Member + Security + Admin staff
authRouter.post("/login", loginLimiter, async (req, res) => {
  const parsed = loginSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const { identifier, password } = parsed.data

  const user = await User.findOne({
    $or: [{ username: identifier }, { email: identifier }],
  })
  if (!user || (user as any).isActive === false) return res.status(401).json({ error: "Invalid credentials" })
  const storedHash = (user as any).passwordHash ?? (user as any).password
  const ok = storedHash && (await bcrypt.compare(password, storedHash))
  if (!ok) return res.status(401).json({ error: "Invalid credentials" })

  const profiles = (user.profiles as any[]) ?? []

  // Multiple society profiles -> ask client to pick one
  if (profiles.length > 1 && !user.activeProfileId) {
    const selectToken = signAccess({ userId: String(user._id), role: user.role, pending: true } as any)
    return res.json({
      needsProfileSelect: true,
      selectToken,
      profiles: profiles.map((p: any) => ({
        profileId: String(p._id), societyName: p.societyName, flatNo: p.flatNo,
      })),
    })
  }

  const profile = profiles.find((p: any) => String(p._id) === String(user.activeProfileId))
    ?? profiles[0]
    ?? { societyId: (user as any).societyId, memberId: (user as any).memberId, role: user.role, status: "active" }
  return res.json(await issueTokens(user, profile))
})

authRouter.post("/switch-profile", requireAuthAllowPending, async (req, res) => {
  const parsed = profileSelectSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const user = await User.findById(req.auth!.userId)
  if (!user) return res.status(404).json({ error: "User not found" })
  const profile = user.profiles.find((p: any) => String(p._id) === parsed.data.profileId)
  if (!profile) return res.status(404).json({ error: "Profile not found" })
  user.activeProfileId = (profile as any)._id
  await user.save()
  return res.json(await issueTokens(user, profile))
})

authRouter.post("/refresh", async (req, res) => {
  const token = req.body?.refreshToken as string | undefined
  if (!token) return res.status(400).json({ error: "No refreshToken" })
  try {
    const { userId, jti } = verifyRefresh(token)
    const stored = await RefreshToken.findOne({ jti, revoked: false })
    if (!stored) return res.status(401).json({ error: "Refresh revoked" })
    stored.revoked = true; await stored.save() // rotate
    const user = await User.findById(userId)
    if (!user) return res.status(401).json({ error: "User gone" })
    const profile = user.profiles.find((p: any) => String(p._id) === String(user.activeProfileId)) ?? user.profiles[0]
    return res.json(await issueTokens(user, profile))
  } catch {
    return res.status(401).json({ error: "Invalid refresh" })
  }
})

authRouter.get("/me", requireAuth, async (req, res) => {
  const user = await User.findById(req.auth!.userId).select("-passwordHash").lean()
  if (!user) return res.status(404).json({ error: "User not found" })

  const [memberDoc, societyDoc] = await Promise.all([
    req.auth!.memberId ? Member.findById(req.auth!.memberId).lean() : null,
    req.auth!.societyId ? Society.findById(req.auth!.societyId).lean() : null,
  ])

  return res.json({
    user: { ...user, member: toMemberDto(memberDoc), society: toSocietyDto(societyDoc) },
    claims: req.auth,
  })
})

// Never spread a raw Member doc into an API response — it carries PAN,
// Aadhaar, banking, and history fields (see mongo_export/members.json)
// that have no business leaving the server. Only these fields are safe.
function toMemberDto(m: any) {
  if (!m) return null
  return {
    _id: String(m._id),
    ownerName: m.ownerName ?? null,
    flatNo: m.flatNo ?? null,
    wing: m.wing ?? null,
    flatType: m.flatType ?? null,
    ownershipType: m.ownershipType ?? null,
    carpetAreaSqft: m.carpetAreaSqft ?? null,
    builtUpAreaSqft: m.builtUpAreaSqft ?? null,
    hasVotingRights: m.hasVotingRights ?? null,
    contactNumber: m.contactNumber ?? null,
    whatsappNumber: m.whatsappNumber ?? null,
    parkingSlots: Array.isArray(m.parkingSlots)
      ? m.parkingSlots.map((p: any) => ({ slotNumber: p.slotNumber ?? null, type: p.type ?? null, vehicleType: p.vehicleType ?? null }))
      : [],
    familyMembers: Array.isArray(m.familyMembers)
      ? m.familyMembers.map((f: any) => ({ name: f.name ?? null, relation: f.relation ?? null, age: f.age ?? null }))
      : [],
  }
}

function toSocietyDto(s: any) {
  if (!s) return null
  return { _id: String(s._id), name: s.name ?? null, address: s.address ?? null }
}

authRouter.post("/change-password", requireAuth, async (req, res) => {
  const parsed = changePasswordSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const user = await User.findById(req.auth!.userId)
  if (!user) return res.status(404).json({ error: "User not found" })
  const storedHash = (user as any).passwordHash ?? (user as any).password
  const ok = storedHash && (await bcrypt.compare(parsed.data.currentPassword, storedHash))
  if (!ok) return res.status(401).json({ error: "Current password is incorrect" })
  ;(user as any).passwordHash = await bcrypt.hash(parsed.data.newPassword, 10)
  ;(user as any).mustChangePassword = false
  await user.save()
  return res.json({ ok: true })
})

// Admin/Secretary onboards a new resident or staff login for their own society
authRouter.post("/add-member", requireAuth, requireRoles(...SOCIETY_ADMIN_ROLES), async (req, res) => {
  const parsed = addMemberSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const taken = await User.findOne({ username: parsed.data.username })
  if (taken) return res.status(409).json({ error: "Username already taken" })

  const admin = await User.findById(req.auth!.userId)
  const adminProfile = admin?.profiles.find((p: any) => String(p._id) === String(req.auth!.activeProfileId))
  const tempPassword = randomUUID().replace(/-/g, "").slice(0, 10)
  const passwordHash = await bcrypt.hash(tempPassword, 10)

  const user = await User.create({
    username: parsed.data.username,
    email: parsed.data.email,
    passwordHash,
    role: parsed.data.role ?? "Member",
    societyId: req.auth!.societyId,
    profiles: [{
      societyId: req.auth!.societyId,
      memberId: new Types.ObjectId(),
      role: parsed.data.role ?? "Member",
      flatNo: parsed.data.flatNo,
      wing: parsed.data.wing ?? "",
      societyName: adminProfile?.societyName ?? "",
      status: "active",
    }],
    isActive: true,
    mustChangePassword: true,
  })

  return res.status(201).json({ username: user.username, tempPassword })
})

// Admin/Secretary looks up members in their society (e.g. to raise a bill by flat number)
authRouter.get("/members", requireAuth, requireRoles(...SOCIETY_ADMIN_ROLES), async (req, res) => {
  const users = await User.find({ societyId: req.auth!.societyId, role: "Member" }).select("username profiles")
  const list = users.flatMap((u: any) =>
    u.profiles
      .filter((p: any) => String(p.societyId) === String(req.auth!.societyId))
      .map((p: any) => ({ memberId: String(p.memberId), username: u.username, flatNo: p.flatNo, wing: p.wing })),
  )
  return res.json(list)
})

async function issueTokens(user: any, profile: any) {
  const jti = randomUUID()
  const refreshToken = signRefresh({ userId: String(user._id), jti })
  await RefreshToken.create({ userId: user._id, jti, expiresAt: refreshExpiresAt(refreshToken) })
  const claims = {
    userId: String(user._id),
    role: profile?.role ?? user.role,
    societyId: profile ? String(profile.societyId) : undefined,
    memberId: profile ? String(profile.memberId) : undefined,
    activeProfileId: profile ? String(profile._id) : undefined,
    mustChangePassword: (user as any).mustChangePassword === true || undefined,
  }
  return {
    role: claims.role,
    mustChangePassword: claims.mustChangePassword,
    tokens: { accessToken: signAccess(claims as any), refreshToken },
  }
}

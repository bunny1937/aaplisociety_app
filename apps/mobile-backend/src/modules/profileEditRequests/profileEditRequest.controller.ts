import { Router } from "express"
import { profileEditRequestCreateSchema } from "@aapli/validation"
import { ROLES } from "@aapli/constants"
import { Member, ProfileEditRequest } from "../../models/index.js"
import { requireAuth, requireRoles } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"
import { requireOwnerOccupancy } from "../tenantRequests/tenantRequest.controller.js"

export const profileEditRequestRouter: Router = Router()
profileEditRequestRouter.use(requireAuth, requireRoles(ROLES.MEMBER), withTenant, requireOwnerOccupancy)

// Owner submits a change to Contact / FamilyMember / EmergencyContact on their own
// Member document. The web app's admin approval flow applies the payload — this
// route only records the request. See profile-restructure design spec.
profileEditRequestRouter.post("/", async (req, res) => {
  const parsed = profileEditRequestCreateSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })

  const memberId = req.auth!.memberId
  const societyId = (req as any).societyId
  const { section, action } = parsed.data
  const familyMemberId = "familyMemberId" in parsed.data ? parsed.data.familyMemberId : undefined

  if (section === "FamilyMember" && action !== "Add") {
    const member = await Member.findOne({ _id: memberId, societyId }).select("familyMembers").lean()
    const exists = (member?.familyMembers as any[] | undefined)?.some((m) => String(m._id) === familyMemberId)
    if (!exists) return res.status(404).json({ error: "Family member not found" })
  }

  const duplicateFilter: Record<string, unknown> = { memberId, societyId, section, status: "Pending" }
  if (section === "FamilyMember") {
    if (action === "Add") {
      // Multiple pending Adds are allowed — each is a distinct new person with no prior target.
    } else {
      duplicateFilter.familyMemberId = familyMemberId
    }
  }
  if (section !== "FamilyMember" || action !== "Add") {
    const duplicate = await ProfileEditRequest.findOne(duplicateFilter).lean()
    if (duplicate) return res.status(409).json({ error: "A request for this change is already pending" })
  }

  const created = await ProfileEditRequest.create({
    societyId,
    memberId,
    requestedByUserId: req.auth!.userId,
    section,
    action,
    familyMemberId,
    payload: parsed.data.payload ?? {},
  })
  return res.status(201).json(created)
})

// Owner's own request history (any status) for their flat.
profileEditRequestRouter.get("/", async (req, res) => {
  const items = await ProfileEditRequest.find({
    societyId: (req as any).societyId,
    memberId: req.auth!.memberId,
  }).sort({ createdAt: -1 })
  return res.json(items)
})

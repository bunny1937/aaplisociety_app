import { randomObjectId } from "../utils/randomObjectId.js"

// Plain-object builder matching the MemberSchema shape in src/models/index.ts
// (and the real shape in mongo_export/members.json).
export function makeMember(overrides: Record<string, unknown> = {}) {
  return {
    societyId: randomObjectId(),
    userId: randomObjectId(),
    flatNo: "1001",
    wing: "B",
    floor: 18,
    carpetAreaSqft: 2112,
    builtUpAreaSqft: 2321,
    flatType: "4BHK",
    parkingSlots: [{ slotNumber: "P-B-112", type: "Open", vehicleType: "Two-Wheeler", monthlyBilling: true }],
    isActive: true,
    ownershipType: "Rented",
    possessionDate: new Date("2020-04-07"),
    ownerName: "Tanvi Bansal",
    contactNumber: "9484122592",
    whatsappNumber: "9676248289",
    emailPrimary: "tanvi.bansal770@example.com",
    familyMembers: [{ name: "Neha Sharma", relation: "Spouse", age: 34, occupation: "Housewife" }],
    membershipStatus: "Active",
    membershipNumber: "MEM-0001",
    hasVotingRights: true,
    ...overrides,
  }
}

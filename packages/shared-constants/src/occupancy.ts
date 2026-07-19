export const OCCUPANCY_TYPES = {
  OWNER: "Owner",
  TENANT: "Tenant",
} as const
export type OccupancyType = (typeof OCCUPANCY_TYPES)[keyof typeof OCCUPANCY_TYPES]

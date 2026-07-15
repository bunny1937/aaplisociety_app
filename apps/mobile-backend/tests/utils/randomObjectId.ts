import { Types } from "../../src/models/index.js"

// Thin wrapper so tests don't need to reach into mongoose/models directly
// just to mint a fresh ObjectId for fixtures/factories.
export function randomObjectId(): InstanceType<typeof Types.ObjectId> {
  return new Types.ObjectId()
}

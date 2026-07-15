// Static fixture matching the UserSchema shape in src/models/index.ts.
// Fixed ids/values on purpose (unlike tests/factories, which randomize) so
// tests can assert against known constants.
export const sampleUser = {
  _id: "64b000000000000000000001",
  username: "sample.member",
  email: "sample.member@example.com",
  passwordHash: "$2a$10$fixturefixturefixturefixturefixturefixturefixture..",
  role: "Member",
  societyId: "64b000000000000000000010",
  memberId: "64b000000000000000000020",
  profiles: [],
  activeProfileId: undefined,
  isActive: true,
}

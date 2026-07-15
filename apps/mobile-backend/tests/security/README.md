# Security tests

Scope: boundary tests for authorization and multi-tenancy, not general
feature correctness. Examples of what belongs here once written:

- Role-gating: a request with a token for role X is rejected (401/403) by
  routes/middleware that require role Y (see `requireRoles`,
  `requireVisitorAccess`, `requireSecurity` in `src/middleware/auth.ts`).
- Tenant isolation: a token scoped to `societyId` A cannot read/write/see
  data belonging to `societyId` B.
- Token handling edge cases: missing token, malformed token, expired token,
  `pending` profile-selection tokens hitting endpoints that require a
  resolved profile.

Use `tests/helpers/auth.ts` (`bearerToken`) to mint tokens for different
roles/societies, and `tests/helpers/app.ts` for the app under test.

Run with `pnpm test:security`.

No test files exist here yet — this README exists to record the intended
scope before feature tests are written.

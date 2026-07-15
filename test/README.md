# Root-level tests

Monorepo-wide contract tests: things that check the shared packages
(`packages/shared-types`, `packages/shared-constants`, `packages/shared-validation`,
`packages/shared-business`) are internally consistent with each other and with
what `apps/mobile-backend` and `apps/mobile-app` actually expect from them —
e.g. "every `Role` in `shared-constants` has a matching case in `JwtClaims`
consumers" or "a `visitorCreateSchema`-shaped payload round-trips into a
`Visitor` document shape".

This directory is a placeholder. No tests exist yet — see
`docs/testing/README.md` for the overall testing architecture and the
priority checklist of what to write first. Per-package/app tests live next to
their own code (`apps/mobile-backend/tests/`, `apps/mobile-app/test/`), not here.

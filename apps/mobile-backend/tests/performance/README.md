# Performance tests

Scope: load/latency testing of hot endpoints (e.g. visitor approval,
bill listing) once the API surface is stable enough to be worth benchmarking.

Status: **no load-testing tool is installed yet.** When this suite is
actually written, add a tool such as [`autocannon`](https://github.com/mcollina/autocannon)
as a devDependency at that time — it is intentionally not installed now,
since this pass is infrastructure-only.

Run with `pnpm test:performance` once tests exist (currently a no-op —
there is nothing under this directory for vitest to pick up).

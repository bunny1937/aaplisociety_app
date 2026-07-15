# Golden tests

Golden (screenshot-diff) tests for widgets/pages whose visual output is
worth pinning down (e.g. themed components, empty states).

Convention:
- Golden image files live in `test/golden/goldens/` (created on first use —
  does not exist yet).
- Reference a golden from a test with `matchesGoldenFile('goldens/<name>.png')`.
- To generate/update the reference images, run:

  ```
  flutter test --update-goldens test/golden
  ```

- To verify without updating (normal CI/local run), just run the test as
  usual:

  ```
  flutter test test/golden
  ```

- Commit the generated `.png` files under `goldens/` alongside the test that
  produced them.
- Golden images are platform/font-rendering sensitive — regenerate them on
  the same platform used in CI to avoid false diffs.

This directory is currently empty (foundation only) — no golden tests or
reference images have been added yet.

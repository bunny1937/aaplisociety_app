# Execution steps

The repo has TWO independent stacks. Set them up separately.

---

## A) Backend + shared packages (Node 20+, pnpm 9+)

Run everything from the **repo root** (the folder containing `pnpm-workspace.yaml`), never inside `apps/mobile-app`.

```bash
# from repo root
pnpm install
pnpm -r build          # turbo builds shared packages + backend
```

### Run the API locally
The backend needs MongoDB (as a replica set, for Change Streams) and Redis. Easiest is Docker:

```bash
cd infrastructure
docker compose up -d        # mongo (rs0) + redis + backend on :5001
curl http://localhost:5001/health   # -> { "ok": true }
```

Or run the API directly against your own Mongo/Redis:
```bash
cp .env.example .env        # fill MONGODB_URI (?replicaSet=rs0), JWT_SECRET, REFRESH_SECRET, REDIS_URL, FIREBASE_SA_JSON, R2_*
pnpm --filter @aapli/mobile-backend dev
```

### Required env (apps/mobile-backend)
```
MONGODB_URI=mongodb://localhost:27017/aapli?replicaSet=rs0
JWT_SECRET=...
REFRESH_SECRET=...
ACCESS_TTL=15m
REFRESH_TTL=30d
REDIS_URL=redis://localhost:6379
FIREBASE_SA_JSON=...      # service account JSON (for FCM push)
R2_ENDPOINT=... R2_BUCKET=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=...
```

---

## B) Flutter mobile app (needs the Flutter SDK - NOT npm/pnpm)

If `flutter`/`dart` are "not recognized", the SDK isn't installed yet.

1. Install Flutter: https://docs.flutter.dev/get-started/install
   - Unzip to a path without spaces (e.g. `C:\src\flutter`).
   - Add `C:\src\flutter\bin` to your PATH, then open a NEW terminal.
2. Verify:
```bash
flutter --version
flutter doctor      # install whatever it flags (Android Studio, an emulator/device)
```
3. Run the app:
```bash
cd apps/mobile-app
flutter pub get
flutter run
```
4. Firebase (for push + Remote Config):
```bash
dart pub global activate flutterfire_cli
flutterfire configure       # generates lib/firebase_options.dart
```

### API base URL
`apps/mobile-app/lib/core/config/flavors.dart`
- Android emulator: `http://10.0.2.2:5001/v1`
- iOS simulator / desktop: `http://localhost:5001/v1`
- Physical device: `http://<your-LAN-IP>:5001/v1`

> Note: the Flutter screens ship with realistic mock data so the UI runs immediately. Each screen maps 1:1 to a backend endpoint (see README) - swap the mock calls for `DioClient` requests to go fully live. Auth + token refresh + the Remote Config launch gate are already wired end-to-end.

---

## Cleanup if you ran npm inside the Flutter folder earlier
Delete these stray files from `apps/mobile-app` (a Flutter folder should not have them):
`node_modules/`, `package.json`, `package-lock.json`.

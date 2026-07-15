# Integration tests

Full end-to-end tests that run the real app on a connected device or
emulator (unlike `test/`, these exercise real platform channels — secure
storage, sockets, Firebase, etc.).

Run with a device/emulator connected:

```
flutter test integration_test
```

Or targeting a specific device:

```
flutter test integration_test -d <device-id>
```

`app_test.dart` is a minimal skeleton showing the pattern works (binding
initialization + pumping a small widget tree + a trivial assertion). It is
intentionally not a real feature test — expand this directory with one file
per user journey as real E2E coverage is needed (e.g. `login_flow_test.dart`,
`bill_payment_flow_test.dart`).

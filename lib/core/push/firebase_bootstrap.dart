/// Set once in main() after Firebase.initializeApp() succeeds/fails. Lets
/// PushService and the permission onboarding skip cleanly with a clear log
/// instead of relying on try/catch around every FirebaseMessaging call to
/// discover Firebase never came up.
class FirebaseBootstrap {
  FirebaseBootstrap._();
  static bool available = false;
}

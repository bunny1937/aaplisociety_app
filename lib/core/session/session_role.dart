import 'package:flutter/foundation.dart';

/// Whether the signed-in resident is a TENANT (not the flat owner).
///
/// Push notification taps are routed by [PushService], which has no
/// BuildContext and therefore no access to `AuthBloc`. Before this existed a
/// "rent reminder" tap sent a TENANT to `/receipts` — the OWNER's maintenance
/// receipt list — because the route table was written from the owner's point of
/// view only. The shell publishes the role here on every build so the push
/// router can pick the right destination for the person actually holding the
/// phone.
final isTenantNotifier = ValueNotifier<bool>(false);

/// Called by `MemberShell` once the role is known.
void publishIsTenant(bool value) {
  if (isTenantNotifier.value != value) isTenantNotifier.value = value;
}

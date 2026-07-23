import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../storage/offline_outbox.dart';
import '../push/push_service.dart';

/// A user who denied notifications during onboarding can still flip it on
/// later from OS Settings without logging out/in. registerForUser() only
/// fires on the AuthAuthed transition (see main.dart), which a background ->
/// foreground resume never triggers - so re-check on every resume while
/// authed. Re-registering an already-known token is a harmless no-op
/// upsert on the backend (see /v1/devices POST).
class PushResumeGate extends StatefulWidget {
  final Dio dio;
  final bool Function() isAuthed;
  final Widget child;
  const PushResumeGate(
      {super.key,
      required this.dio,
      required this.isAuthed,
      required this.child});
  @override
  State<PushResumeGate> createState() => _PushResumeGateState();
}

class _PushResumeGateState extends State<PushResumeGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isAuthed()) {
      PushService.instance.registerForUser(widget.dio);
      // Guard app: entries logged while offline (New Entry -> Offline Entry)
      // sit in OfflineOutbox until connectivity returns. Resume is the
      // cheapest signal that connectivity may have changed.
      OfflineOutbox.syncAndNotify(widget.dio);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

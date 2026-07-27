import 'package:dio/dio.dart';

/// Acknowledges an SOS: "seen, we are responding."
///
/// This is the only thing that silences the alarm on the OTHER devices in the
/// flat. The STOP button on a ringing phone is local -- it kills that phone's
/// audio and vibration and nothing else, so before this endpoint existed an SOS
/// raised at home kept every other household phone screaming until each one was
/// picked up and tapped.
///
/// The backend fans a `VISITOR_SOS_ACK` push out to every user on the flat; the
/// client kills its local alarm the moment it sees that type arrive (see
/// `main.dart` and `PushService`). Callable by a guard, or by anyone in the
/// affected flat marking themselves safe.
Future<Map<String, dynamic>> acknowledgeSos(
  Dio dio,
  String visitorId, {
  String? note,
  String? byName,
}) async {
  final res = await dio.post(
    '/visitors/$visitorId/sos-ack',
    data: {
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (byName != null && byName.trim().isNotEmpty) 'byName': byName.trim(),
    },
  );
  return Map<String, dynamic>.from(res.data as Map);
}

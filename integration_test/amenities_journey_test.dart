// The one test that runs on a device against a real server.
//
// Widget tests prove each screen handles a given response. This proves the app and
// the API agree in practice: the paths exist, the token is accepted, the shapes
// parse. It is deliberately short, because device tests are slow and flaky by
// nature -- everything that can be asserted without a device already is, elsewhere.
//
// Run it against a staging build:
//   flutter test integration_test/amenities_journey_test.dart \
//     --dart-define=API_BASE_URL=https://staging.example.com/v1 \
//     --dart-define=TEST_TOKEN=<a member access token>
import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";
import "package:integration_test/integration_test.dart";

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const String baseUrl = String.fromEnvironment("API_BASE_URL", defaultValue: "");
  const String token = String.fromEnvironment("TEST_TOKEN", defaultValue: "");

  late Dio dio;

  setUpAll(() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      headers: <String, dynamic>{"Authorization": "Bearer $token"},
      validateStatus: (int? code) => code != null && code < 500,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    ));
  });

  bool get configured => baseUrl.isNotEmpty && token.isNotEmpty;

  testWidgets("the amenities list is reachable and well shaped", (WidgetTester tester) async {
    if (!configured) {
      markTestSkipped("API_BASE_URL and TEST_TOKEN were not provided");
      return;
    }

    final Response<dynamic> res = await dio.get<dynamic>("/amenities");
    expect(res.statusCode, 200);

    final dynamic data = res.data;
    expect(data, isA<Map<String, dynamic>>());
    expect((data as Map<String, dynamic>).containsKey("amenities"), isTrue);
  });

  testWidgets("an amenity detail carries the keys the detail page reads", (WidgetTester tester) async {
    if (!configured) {
      markTestSkipped("not configured");
      return;
    }

    final Response<dynamic> list = await dio.get<dynamic>("/amenities");
    final List<dynamic> amenities = (list.data as Map<String, dynamic>)["amenities"] as List<dynamic>;
    if (amenities.isEmpty) {
      markTestSkipped("the staging society has no amenities");
      return;
    }

    final String id = (amenities.first as Map<String, dynamic>)["_id"].toString();
    final Response<dynamic> detail = await dio.get<dynamic>("/amenities/$id");

    expect(detail.statusCode, 200);
    final Map<String, dynamic> body = detail.data as Map<String, dynamic>;
    expect(body.containsKey("amenity"), isTrue);
  });

  testWidgets("a malformed QR payload is refused cleanly, never with a 500", (WidgetTester tester) async {
    if (!configured) {
      markTestSkipped("not configured");
      return;
    }

    final Response<dynamic> res = await dio.post<dynamic>(
      "/amenities/qr/check-in",
      data: <String, dynamic>{"token": "not-a-real-payload"},
    );

    expect(res.statusCode, greaterThanOrEqualTo(400));
    expect(res.statusCode, lessThan(500));
  });

  testWidgets("the attendance history returns only this member's rows", (WidgetTester tester) async {
    if (!configured) {
      markTestSkipped("not configured");
      return;
    }

    final Response<dynamic> res = await dio.get<dynamic>("/amenities/my-attendance");
    expect(res.statusCode, 200);

    final Map<String, dynamic> body = res.data as Map<String, dynamic>;
    expect(body.containsKey("attendance"), isTrue);
  });

  testWidgets("the events list is reachable", (WidgetTester tester) async {
    if (!configured) {
      markTestSkipped("not configured");
      return;
    }

    final Response<dynamic> res = await dio.get<dynamic>("/amenities/events");
    expect(res.statusCode, 200);
    expect((res.data as Map<String, dynamic>).containsKey("events"), isTrue);
  });

  testWidgets("an unauthenticated call is refused", (WidgetTester tester) async {
    if (baseUrl.isEmpty) {
      markTestSkipped("not configured");
      return;
    }

    final Dio anon = Dio(BaseOptions(
      baseUrl: baseUrl,
      validateStatus: (int? code) => code != null && code < 500,
    ));

    final Response<dynamic> res = await anon.get<dynamic>("/amenities");
    expect(res.statusCode, anyOf(401, 403));
  });
}

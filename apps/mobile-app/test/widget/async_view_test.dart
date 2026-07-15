import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/core/widgets/async_view.dart';

void main() {
  testWidgets('shows a CircularProgressIndicator while the future is pending', (tester) async {
    final completer = Completer<String>();

    await tester.pumpWidget(MaterialApp(
      home: AsyncView<String>(
        fetch: () => completer.future,
        builder: (context, data) => Text('loaded: $data'),
      ),
    ));

    // Don't let the future settle yet — assert on the loading state.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('loaded: nope'), findsNothing);

    // Clean up so the pending future doesn't leak into the next test.
    completer.complete('unused');
    await tester.pumpAndSettle();
  });

  testWidgets('renders the builder content once the future resolves with data', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AsyncView<String>(
        fetch: () async => 'Hello from fetch',
        builder: (context, data) => Text('Data: $data'),
      ),
    ));

    await tester.pump(); // let the microtask/future resolve
    await tester.pump();

    expect(find.text('Data: Hello from fetch'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders the error state with apiErrorMessage text and retry re-invokes fetch', (tester) async {
    int callCount = 0;

    await tester.pumpWidget(MaterialApp(
      home: AsyncView<String>(
        fetch: () {
          callCount++;
          if (callCount == 1) {
            final req = RequestOptions(path: '/whatever');
            return Future<String>.error(
              DioException(requestOptions: req, type: DioExceptionType.connectionError),
            );
          }
          return Future<String>.value('recovered');
        },
        builder: (context, data) => Text('Data: $data'),
      ),
    ));

    await tester.pump();
    await tester.pump();

    expect(callCount, 1);
    expect(find.text('Could not reach the server. Check your connection.'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Real tap through Flutter's normal gesture pipeline. (This used to trip
    // a genuine bug: AsyncViewState.reload() did `setState(() => _future =
    // next)` — an assignment *expression*, whose value is the assigned
    // Future, so the closure implicitly returned a Future and tripped
    // Flutter's "setState() callback argument returned a Future" assertion
    // on every reload(). Fixed in async_view.dart to a block body
    // `setState(() { _future = next; })` so the closure returns void.)
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();

    expect(callCount, 2);
    expect(find.text('Data: recovered'), findsOneWidget);
  });

  testWidgets('renders the empty-state widget instead of builder content when isEmpty is true', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AsyncView<List<String>>(
        fetch: () async => <String>[],
        isEmpty: (data) => data.isEmpty,
        builder: (context, data) => Text('Count: ${data.length}'),
      ),
    ));

    await tester.pump();
    await tester.pump();

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.textContaining('Count:'), findsNothing);
  });

  testWidgets('uses the custom emptyBuilder when provided instead of the default empty state', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AsyncView<List<String>>(
        fetch: () async => <String>[],
        isEmpty: (data) => data.isEmpty,
        emptyBuilder: (context) => const Text('Custom empty message'),
        builder: (context, data) => Text('Count: ${data.length}'),
      ),
    ));

    await tester.pump();
    await tester.pump();

    expect(find.text('Custom empty message'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
  });
}

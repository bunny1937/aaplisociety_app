import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/core/theme/app_theme.dart';
import 'package:aapli_society/core/widgets/visitor_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));

  testWidgets('renders name, subtitle and status text', (tester) async {
    await tester.pumpWidget(wrap(const LedgerVisitorCard(
      name: 'Rajesh Kumar',
      subtitle: 'Delivery · 7m ago',
      status: 'Pending',
    )));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Rajesh Kumar'), findsOneWidget);
    expect(find.text('Delivery · 7m ago'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('applies the tint color to the card background when provided', (tester) async {
    const tint = Color(0xFFFDF1DE);
    await tester.pumpWidget(wrap(const LedgerVisitorCard(
      name: 'Amit Traders',
      subtitle: 'Vendor · 22m ago',
      tint: tint,
    )));
    await tester.pump(const Duration(milliseconds: 350));

    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, tint);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:removetrack/main.dart';

void main() {
  testWidgets('App launches without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const PixelytApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

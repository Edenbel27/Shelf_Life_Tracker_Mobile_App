// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shelf_life_tracker/login_page.dart';

void main() {
  testWidgets('Login page smoke test', (WidgetTester tester) async {
    // Build the LoginPage inside a MaterialApp and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    // Verify key texts are present.
    expect(find.text('Shelf Life Tracker'), findsOneWidget);
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);

    // Verify the dropdown shows the default role.
    expect(find.text('Store Owner'), findsOneWidget);
  });
}

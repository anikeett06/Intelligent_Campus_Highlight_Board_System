// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/main.dart';
import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/services/api_service.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState(ApiService())),
        ],
        child: const CampusBoardApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Login'), findsOneWidget);
  });
}

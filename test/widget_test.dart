import 'package:flutter_test/flutter_test.dart';
import 'package:waslapos_app/main.dart';

void main() {
  testWidgets('shows the sign-in screen when there is no saved session', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('مرحباً بعودتك'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
    expect(find.text('البريد الإلكتروني'), findsOneWidget);
  });
}

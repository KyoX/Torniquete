import 'package:flutter_test/flutter_test.dart';

import 'package:torniquete/main.dart';

void main() {
  testWidgets('Muestra la pantalla de bienvenida cuando no hay usuario configurado',
      (WidgetTester tester) async {
    await tester.pumpWidget(const TorniqueteApp());
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido a Torniquete'), findsOneWidget);
  });
}

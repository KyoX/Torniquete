import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:torniquete/main.dart';

void main() {
  testWidgets('Muestra la pantalla de bienvenida cuando no hay usuario configurado',
      (WidgetTester tester) async {
    // Sin este mock, SharedPreferences no responde en el entorno de test y la
    // pantalla se queda cargando para siempre.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TorniqueteApp());
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido a Torniquete'), findsOneWidget);
  });
}

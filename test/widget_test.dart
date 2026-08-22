import 'package:flutter/material.dart';
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

  testWidgets('Los diálogos de Material hablan español', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TorniqueteApp());
    await tester.pumpAndSettle();

    final contexto = tester.element(find.byType(Scaffold).first);
    final material = MaterialLocalizations.of(contexto);
    // Los textos del calendario y del reloj los pone Flutter, no la app:
    // si estos salen en español, el resto de esos diálogos también.
    expect(material.cancelButtonLabel, 'Cancelar');
    expect(Localizations.localeOf(contexto), const Locale('es'));
  });
}

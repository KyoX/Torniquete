import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:torniquete/main.dart';
import 'package:torniquete/providers/app_provider.dart';
import 'package:torniquete/services/prefs_service.dart';
import 'package:torniquete/services/widget_service.dart';
import 'package:torniquete/theme/app_theme.dart';

void main() {
  test('el tema se guarda por clave y lo desconocido cae en automático', () {
    expect(ModoTema.desdeClave('oscuro'), ModoTema.oscuro);
    expect(ModoTema.desdeClave('claro'), ModoTema.claro);
    // Sin nada guardado manda el teléfono, que es la opción por defecto.
    expect(ModoTema.desdeClave(null), ModoTema.sistema);
    expect(ModoTema.desdeClave('violeta'), ModoTema.sistema);
    expect(ModoTema.sistema.themeMode, ThemeMode.system);
    expect(ModoTema.claro.themeMode, ThemeMode.light);
    expect(ModoTema.oscuro.themeMode, ThemeMode.dark);
  });

  testWidgets('la app arranca con el tema que el usuario dejó elegido',
      (tester) async {
    SharedPreferences.setMockInitialValues({'modo_tema': 'oscuro'});

    final modo = await PrefsService().getModoTema();
    await tester.pumpWidget(TorniqueteApp(modoTema: modo));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    final contexto = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(contexto).brightness, Brightness.dark);
  });

  testWidgets('cambiar la apariencia repinta la app y queda guardada',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const TorniqueteApp());
    await tester.pumpAndSettle();

    MaterialApp app() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app().themeMode, ThemeMode.system);

    final provider = Provider.of<AppProvider>(
      tester.element(find.byType(MaterialApp)),
      listen: false,
    );
    await provider.setModoTema(ModoTema.claro);
    await tester.pumpAndSettle();

    expect(app().themeMode, ThemeMode.light);
    // Y sigue elegido la próxima vez que se abra la app.
    expect(await PrefsService().getModoTema(), ModoTema.claro);
  });

  test('el fondo del widget se guarda por clave y arranca sólido', () {
    expect(FondoWidget.desdeClave('transparente'), FondoWidget.transparente);
    expect(FondoWidget.desdeClave('translucido'), FondoWidget.translucido);
    // Es lo mismo que hace el proveedor de Kotlin ante una clave que no
    // conoce: el fondo sólido, que se ve bien sobre cualquier fondo de
    // pantalla.
    expect(FondoWidget.desdeClave(null), FondoWidget.solido);
    expect(FondoWidget.desdeClave('cristal'), FondoWidget.solido);
  });

  testWidgets('elegir el fondo del widget queda guardado', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final provider = AppProvider();
    expect(provider.fondoWidget, FondoWidget.solido);

    // runAsync porque el cambio pasa por el canal nativo del widget, y esa
    // respuesta no llega dentro del reloj simulado de testWidgets.
    await tester.runAsync(() async {
      await provider.setFondoWidget(FondoWidget.transparente);
      expect(await PrefsService().getFondoWidget(), FondoWidget.transparente);
    });

    expect(provider.fondoWidget, FondoWidget.transparente);
  });

  testWidgets('los estados usan tonos propios en cada tema', (tester) async {
    final vistos = <Brightness, List<Color>>{};

    Widget muestra(ThemeData tema) => Theme(
          data: tema,
          child: Builder(
            builder: (context) {
              vistos[tema.brightness] = [
                AppColors.cumplidoDe(context),
                AppColors.pendienteDe(context),
                AppColors.neutroDe(context),
                AppColors.rojoDe(context),
              ];
              return const SizedBox.shrink();
            },
          ),
        );

    await tester.pumpWidget(MaterialApp(
      home: Column(children: [muestra(AppTheme.claro), muestra(AppTheme.oscuro)]),
    ));

    final claro = vistos[Brightness.light]!;
    final oscuro = vistos[Brightness.dark]!;
    // Ninguno de los cuatro puede quedarse con el tono del tema claro: sobre
    // el azul oscuro de las tarjetas no se leería.
    for (var i = 0; i < claro.length; i++) {
      expect(oscuro[i], isNot(claro[i]));
    }
    // Y en el tema oscuro los cuatro siguen siendo distintos entre sí, que es
    // lo que permite leer el estado de un vistazo.
    expect(oscuro.toSet(), hasLength(4));
    expect(claro.toSet(), hasLength(4));
  });
}

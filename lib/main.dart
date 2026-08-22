import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'providers/app_provider.dart';
import 'providers/registro_provider.dart';
import 'screens/root_screen.dart';
import 'services/notification_service.dart';
import 'services/prefs_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await NotificationService.instance.init();
  // El tema se lee antes de pintar el primer cuadro: si se leyera después,
  // quien tenga elegido el oscuro vería un destello blanco al abrir.
  final modoTema = await PrefsService().getModoTema();
  runApp(TorniqueteApp(modoTema: modoTema));
}

class TorniqueteApp extends StatelessWidget {
  const TorniqueteApp({super.key, this.modoTema = ModoTema.sistema});

  /// Tema con el que arranca la app, ya leído de preferencias.
  final ModoTema modoTema;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider(modoTema: modoTema)),
        ChangeNotifierProvider(create: (_) => RegistroProvider()),
      ],
      // Con Selector la app se repinta solo cuando cambia el tema, y no cada
      // vez que se toca un ajuste cualquiera.
      child: Selector<AppProvider, ThemeMode>(
        selector: (_, app) => app.modoTema.themeMode,
        builder: (context, modo, _) => MaterialApp(
          title: 'Torniquete',
          debugShowCheckedModeBanner: false,
          // El usuario elige la apariencia en Ajustes; por defecto sigue al
          // teléfono.
          themeMode: modo,
          theme: AppTheme.claro,
          darkTheme: AppTheme.oscuro,
          // Toda la app está escrita en español: se fija el idioma para que
          // el calendario, el reloj y demás diálogos de Material también lo
          // estén, sin depender del idioma del teléfono.
          locale: const Locale('es'),
          supportedLocales: const [Locale('es'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const RootScreen(),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'providers/app_provider.dart';
import 'providers/registro_provider.dart';
import 'screens/root_screen.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await NotificationService.instance.init();
  runApp(const TorniqueteApp());
}

class TorniqueteApp extends StatelessWidget {
  const TorniqueteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider(create: (_) => RegistroProvider()),
      ],
      child: MaterialApp(
        title: 'Torniquete',
        debugShowCheckedModeBanner: false,
        // Se fija el tema claro para respetar la identidad de la marca
        // (azul sobre blanco). Cambiar a ThemeMode.system deja que el
        // teléfono elija entre la versión clara y la oscura.
        themeMode: ThemeMode.light,
        theme: AppTheme.claro,
        darkTheme: AppTheme.oscuro,
        home: const RootScreen(),
      ),
    );
  }
}

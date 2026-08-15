import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import 'dashboard_screen.dart';
import 'onboarding_screen.dart';

/// Decide si mostrar el Onboarding o el Dashboard según si ya existe
/// un nombre de usuario guardado en SharedPreferences.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  late final Future<bool> _tieneUsuarioFuture;

  @override
  void initState() {
    super.initState();
    final appProvider = context.read<AppProvider>();
    _tieneUsuarioFuture = appProvider.tieneUsuarioConfigurado().then((tiene) async {
      if (tiene) await appProvider.cargar();
      return tiene;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _tieneUsuarioFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final tieneUsuario = snapshot.data ?? false;
        return tieneUsuario ? const DashboardScreen() : const OnboardingScreen();
      },
    );
  }
}

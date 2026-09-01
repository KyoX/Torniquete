import 'package:flutter/material.dart';

import '../services/lock_service.dart';
import '../services/prefs_service.dart';
import 'root_screen.dart';

/// Envuelve toda la app y exige huella o PIN antes de dejar pasar, cuando el
/// bloqueo está activo en Ajustes. Se re-arma al volver de segundo plano, así
/// que también protege la entrada directa desde una notificación de marca.
class LockGate extends StatefulWidget {
  const LockGate({super.key});

  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  final PrefsService _prefs = PrefsService();
  bool _bloqueoActivo = false;
  bool _desbloqueado = false;
  bool _cargando = true;
  bool _autenticando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inicializar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _inicializar() async {
    final activo = await _prefs.getBloqueoActivo();
    if (!mounted) return;
    setState(() {
      _bloqueoActivo = activo;
      _cargando = false;
    });
    if (activo) _autenticar();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_bloqueoActivo) return;
    // Solo "paused" cuenta como fondo de verdad: "inactive" también salta al
    // mostrar el propio diálogo biométrico o al bajar la barra de
    // notificaciones un instante, y re-bloquear ahí encerraría al usuario en
    // un ciclo.
    if (state == AppLifecycleState.paused) {
      setState(() => _desbloqueado = false);
    } else if (state == AppLifecycleState.resumed && !_desbloqueado) {
      _autenticar();
    }
  }

  Future<void> _autenticar() async {
    if (_autenticando) return;
    _autenticando = true;
    final ok = await LockService.instance.autenticar();
    _autenticando = false;
    if (!mounted) return;
    setState(() => _desbloqueado = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(body: SizedBox.shrink());
    }
    if (!_bloqueoActivo || _desbloqueado) {
      return const RootScreen();
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline,
                    size: 56, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                const Text(
                  'Torniquete está bloqueada',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Confirma tu huella o el PIN del teléfono para continuar.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _autenticar,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Desbloquear'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

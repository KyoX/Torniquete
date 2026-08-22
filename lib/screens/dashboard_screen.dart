import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/tipo_dia.dart';
import '../providers/app_provider.dart';
import '../providers/registro_provider.dart';
import '../utils/time_utils.dart';
import '../widgets/exit_banner.dart';
import '../widgets/mark_row.dart';
import '../widgets/progress_card.dart';
import '../widgets/quick_action_buttons.dart';
import 'history_screen.dart';
import 'reports/reports_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  /// Redibuja periódicamente mientras la app está en primer plano.
  Timer? _reloj;

  /// Se guarda la referencia para poder soltar el listener en [dispose],
  /// donde ya no es seguro leer el contexto.
  RegistroProvider? _registroProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _registroProvider = context.read<RegistroProvider>()
        ..addListener(_revisarAvisoGeocerca);
      _cargarDatos();
    });
    _iniciarReloj();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _registroProvider?.removeListener(_revisarAvisoGeocerca);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Muestra el aviso de que una marca quedó fuera de la sede. Solo informa:
  /// la marca ya se guardó y no se deshace.
  void _revisarAvisoGeocerca() {
    final provider = _registroProvider;
    final aviso = provider?.avisoGeocerca;
    if (!mounted || provider == null || aviso == null) return;
    provider.limpiarAvisoGeocerca();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(aviso),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Ajustes',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
      ),
    );
  }

  void _iniciarReloj() {
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(seconds: 30), (_) => _refrescar());
  }

  /// El tiempo trabajado y la hora estimada de salida se calculan contra la
  /// hora actual del teléfono, así que hay que redibujar aunque el usuario
  /// no toque nada.
  void _refrescar() {
    if (!mounted) return;
    if (_cambioDeDia()) {
      _cargarDatos();
    } else {
      setState(() {});
    }
  }

  /// True si el registro en memoria ya no corresponde a hoy (la app quedó
  /// abierta o en segundo plano pasada la medianoche).
  bool _cambioDeDia() {
    final registro = context.read<RegistroProvider>().registroHoy;
    return registro != null && registro.fecha != RegistroProvider.fechaHoy();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // En segundo plano no hay nada que redibujar.
      _reloj?.cancel();
      return;
    }
    _iniciarReloj();
    _refrescar();
  }

  Future<void> _cargarDatos() async {
    final appProvider = context.read<AppProvider>();
    if (!appProvider.cargado) {
      await appProvider.cargar();
    }
    final metaMinutos =
        appProvider.metaMinutosParaDia(DateTime.now().weekday);
    if (!mounted) return;
    await context.read<RegistroProvider>().cargarRegistroDeHoy(
          metaMinutos,
          nombreUsuario: appProvider.nombre,
        );
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final registroProvider = context.watch<RegistroProvider>();
    final nombre = appProvider.nombre ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo_mark.png', height: 32),
            const SizedBox(width: 10),
            const Text('Torniquete'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reportes',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ReportsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Historial',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              await _cargarDatos();
            },
          ),
        ],
      ),
      body: registroProvider.cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '¡Hola, $nombre!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    DateFormat('EEEE d \'de\' MMMM', 'es')
                        .format(DateTime.now()),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  _ChipTipoDia(
                    tipo: registroProvider.tipoDiaHoy,
                    onCambiar: (tipo) => registroProvider.cambiarTipoDia(
                      tipo,
                      nombreUsuario: nombre,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ExitBanner(
                    horaSalida: registroProvider.horaEstimadaSalida,
                    metaCumplida: registroProvider.metaCumplida,
                    tipoDia: registroProvider.tipoDiaHoy,
                  ),
                  const SizedBox(height: 16),
                  ProgressCard(
                    progreso: registroProvider.progreso,
                    minutosTrabajados:
                        registroProvider.minutosTrabajadosHastaAhora,
                    metaMinutos:
                        registroProvider.registroHoy?.metaEfectivaMinutos ?? 0,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Column(
                      children: [
                        MarkRow(
                          icon: Icons.login,
                          label: 'Entrada mañana',
                          horaTexto:
                              TimeUtils.formatHHmm(registroProvider.registroHoy?.entrada1),
                          valorActual: registroProvider.entrada1,
                          onEditar: (t) => registroProvider.editarManualmente(
                            MarcaTipo.entrada1,
                            t,
                            nombreUsuario: nombre,
                          ),
                          ubicacion:
                              registroProvider.ubicacionDe(MarcaTipo.entrada1),
                          capturandoUbicacion: registroProvider
                              .capturandoUbicacion(MarcaTipo.entrada1),
                          geocerca:
                              registroProvider.geocercaDe(MarcaTipo.entrada1),
                        ),
                        const Divider(height: 1),
                        MarkRow(
                          icon: Icons.lunch_dining,
                          label: 'Salida almuerzo',
                          horaTexto:
                              TimeUtils.formatHHmm(registroProvider.registroHoy?.salida1),
                          valorActual: registroProvider.salida1,
                          onEditar: (t) => registroProvider.editarManualmente(
                            MarcaTipo.salida1,
                            t,
                            nombreUsuario: nombre,
                          ),
                          ubicacion:
                              registroProvider.ubicacionDe(MarcaTipo.salida1),
                          capturandoUbicacion: registroProvider
                              .capturandoUbicacion(MarcaTipo.salida1),
                          geocerca:
                              registroProvider.geocercaDe(MarcaTipo.salida1),
                        ),
                        const Divider(height: 1),
                        MarkRow(
                          icon: Icons.keyboard_return,
                          label: 'Entrada tarde',
                          horaTexto:
                              TimeUtils.formatHHmm(registroProvider.registroHoy?.entrada2),
                          valorActual: registroProvider.entrada2,
                          onEditar: (t) => registroProvider.editarManualmente(
                            MarcaTipo.entrada2,
                            t,
                            nombreUsuario: nombre,
                          ),
                          ubicacion:
                              registroProvider.ubicacionDe(MarcaTipo.entrada2),
                          capturandoUbicacion: registroProvider
                              .capturandoUbicacion(MarcaTipo.entrada2),
                          geocerca:
                              registroProvider.geocercaDe(MarcaTipo.entrada2),
                        ),
                        const Divider(height: 1),
                        MarkRow(
                          icon: Icons.logout,
                          label: 'Salida real',
                          horaTexto:
                              TimeUtils.formatHHmm(registroProvider.registroHoy?.salidaReal),
                          valorActual: registroProvider.salidaReal,
                          onEditar: (t) => registroProvider.editarManualmente(
                            MarcaTipo.salidaReal,
                            t,
                            nombreUsuario: nombre,
                          ),
                          ubicacion:
                              registroProvider.ubicacionDe(MarcaTipo.salidaReal),
                          capturandoUbicacion: registroProvider
                              .capturandoUbicacion(MarcaTipo.salidaReal),
                          geocerca:
                              registroProvider.geocercaDe(MarcaTipo.salidaReal),
                        ),
                      ],
                    ),
                  ),
                  if (registroProvider.entrada2 != null) ...[
                    const SizedBox(height: 16),
                    if (registroProvider.salidaReal == null)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: () => registroProvider.confirmarSalida(
                            nombreUsuario: nombre,
                          ),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Confirmar salida'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Salida confirmada a las '
                                '${TimeUtils.formatHHmm(registroProvider.registroHoy?.salidaReal)}',
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSecondaryContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 20),
                  QuickActionButtons(
                    entrada1Habilitada: registroProvider.entrada1 == null,
                    salida1Habilitada: registroProvider.entrada1 != null &&
                        registroProvider.salida1 == null,
                    entrada2Habilitada: registroProvider.salida1 != null &&
                        registroProvider.entrada2 == null,
                    onEntrada: () => registroProvider.marcar(
                      MarcaTipo.entrada1,
                      nombreUsuario: nombre,
                    ),
                    onSalidaComer: () => registroProvider.marcar(
                      MarcaTipo.salida1,
                      nombreUsuario: nombre,
                    ),
                    onRegresoComer: () => registroProvider.marcar(
                      MarcaTipo.entrada2,
                      nombreUsuario: nombre,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

/// Chip con el tipo del día de hoy. Tocarlo abre la lista para marcar el día
/// como festivo, vacaciones, incapacidad o permiso sin pasar por el
/// historial: son cambios que uno quiere hacer justo cuando se da cuenta.
class _ChipTipoDia extends StatelessWidget {
  final TipoDia tipo;
  final ValueChanged<TipoDia> onCambiar;

  const _ChipTipoDia({required this.tipo, required this.onCambiar});

  Future<void> _elegir(BuildContext context) async {
    final elegido = await showModalBottomSheet<TipoDia>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                '¿Qué día es hoy?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Los días que no son normales no exigen meta de horas: no '
                'generan déficit y lo que trabajes en ellos cuenta completo '
                'como tiempo extra.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            for (final opcion in TipoDia.values)
              ListTile(
                leading: Icon(
                  opcion.exigeMeta
                      ? Icons.work_outline
                      : Icons.event_available_outlined,
                ),
                title: Text(opcion.etiqueta),
                trailing: opcion == tipo ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(opcion),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (elegido != null && elegido != tipo) onCambiar(elegido);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final destacado = tipo.esJustificado;
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        avatar: Icon(
          destacado ? Icons.event_available : Icons.work_outline,
          size: 18,
          color: destacado ? scheme.onTertiaryContainer : scheme.onSurfaceVariant,
        ),
        label: Text(tipo.etiqueta),
        backgroundColor:
            destacado ? scheme.tertiaryContainer : scheme.surfaceContainerHigh,
        labelStyle: TextStyle(
          color: destacado ? scheme.onTertiaryContainer : scheme.onSurface,
          fontWeight: destacado ? FontWeight.w600 : FontWeight.normal,
        ),
        side: BorderSide.none,
        onPressed: () => _elegir(context),
      ),
    );
  }
}

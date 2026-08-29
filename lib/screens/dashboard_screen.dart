import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/tipo_dia.dart';
import '../models/ubicacion_marca.dart';
import '../providers/app_provider.dart';
import '../providers/registro_provider.dart';
import '../utils/festivos_sv.dart';
import '../utils/time_utils.dart';
import '../widgets/exit_banner.dart';
import '../widgets/mark_row.dart';
import '../widgets/pausa_row.dart';
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

  /// Asueto que el usuario decidió ignorar porque hoy sí va a trabajar.
  /// Vive solo mientras la pantalla está abierta: no es una decisión que
  /// valga la pena persistir.
  String? _asuetoDescartado;

  /// El asueto de hoy, si toca sugerirlo.
  ///
  /// No se sugiere si el día ya está marcado como justificado —ya está
  /// resuelto— ni si el usuario descartó el aviso.
  Asueto? _asuetoDeHoy(AppProvider app, RegistroProvider registro) {
    if (registro.tipoDiaHoy.esJustificado) return null;
    final asueto = app.asuetoEn(DateTime.now());
    if (asueto == null || asueto.fecha == _asuetoDescartado) return null;
    return asueto;
  }

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
    // La marca del aviso se revisa contra el día correcto: si la app estuvo
    // en segundo plano pasada la medianoche, primero hay que recargar el día,
    // y esa recarga ya la revisa al terminar.
    if (_cambioDeDia()) {
      _cargarDatos();
    } else {
      setState(() {});
      _revisarMarcaDeLlegada();
    }
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
    await _revisarMarcaDeLlegada();
  }

  /// Registra la marca que el usuario aceptó desde el aviso de llegada.
  ///
  /// Se revisa al cargar y cada vez que la app vuelve a primer plano porque
  /// el aviso llega con la app cerrada: tocarlo la despierta, y es aquí donde
  /// esa decisión se convierte en una marca guardada.
  Future<void> _revisarMarcaDeLlegada() async {
    if (!mounted) return;
    final nombre = context.read<AppProvider>().nombre ?? '';
    final marca = await context
        .read<RegistroProvider>()
        .registrarMarcaAceptada(nombreUsuario: nombre);
    if (!mounted || marca == null) return;
    final aviso = marca.tipo == MarcaTipo.entrada1
        ? 'Entrada registrada a las ${marca.hora}.'
        : 'Jornada reanudada a las ${marca.hora}.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso)));
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
                  if (_asuetoDeHoy(appProvider, registroProvider)
                      case final asueto?) ...[
                    const SizedBox(height: 12),
                    _AvisoAsueto(
                      asueto: asueto,
                      onMarcar: () => registroProvider.cambiarTipoDia(
                        TipoDia.festivo,
                        nota: asueto.nombre,
                        nombreUsuario: nombre,
                      ),
                      onDescartar: () =>
                          setState(() => _asuetoDescartado = asueto.fecha),
                    ),
                  ],
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
                          label: 'Entrada',
                          horaTexto: TimeUtils.formatHHmm(
                              registroProvider.registroHoy?.entrada1),
                          valorActual: registroProvider.entrada1,
                          onEditar: (t) => registroProvider.editarManualmente(
                            MarcaTipo.entrada1,
                            t,
                            nombreUsuario: nombre,
                          ),
                          evidencia: registroProvider
                              .evidenciaDe(ClaveUbicacion.entrada),
                        ),
                        for (final (indice, pausa)
                            in registroProvider.pausas.indexed) ...[
                          const Divider(height: 1),
                          PausaRow(
                            numero: indice + 1,
                            pausa: pausa,
                            esAlmuerzo: pausa == registroProvider.almuerzo,
                            minutosAhora:
                                TimeUtils.toMinutes(TimeOfDay.now()),
                            onEditarInicio: (t) =>
                                registroProvider.editarInicioPausa(
                              indice,
                              t,
                              nombreUsuario: nombre,
                            ),
                            onEditarFin: (t) => registroProvider.editarFinPausa(
                              indice,
                              t,
                              nombreUsuario: nombre,
                            ),
                            onEliminar: () => registroProvider.eliminarPausa(
                              indice,
                              nombreUsuario: nombre,
                            ),
                            evidenciaInicio: pausa == registroProvider.almuerzo
                                ? registroProvider.evidenciaDe(
                                    ClaveUbicacion.almuerzoInicio)
                                : EvidenciaMarca.ninguna,
                            evidenciaFin: pausa == registroProvider.almuerzo
                                ? registroProvider
                                    .evidenciaDe(ClaveUbicacion.almuerzoFin)
                                : EvidenciaMarca.ninguna,
                          ),
                        ],
                        const Divider(height: 1),
                        MarkRow(
                          icon: Icons.logout,
                          label: 'Salida real',
                          horaTexto: TimeUtils.formatHHmm(
                              registroProvider.registroHoy?.salidaReal),
                          valorActual: registroProvider.salidaReal,
                          onEditar: (t) => registroProvider.editarManualmente(
                            MarcaTipo.salidaReal,
                            t,
                            nombreUsuario: nombre,
                          ),
                          evidencia: registroProvider
                              .evidenciaDe(ClaveUbicacion.salidaReal),
                        ),
                      ],
                    ),
                  ),
                  // Basta con haber entrado: quien no sale a almorzar nunca
                  // marca el regreso y, con la puerta atada a esa marca, se
                  // quedaba sin poder cerrar el día.
                  if (registroProvider.entrada1 != null) ...[
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
                    entradaHabilitada: registroProvider.entrada1 == null &&
                        registroProvider.salidaReal == null,
                    // Se puede pausar tantas veces como haga falta, siempre
                    // que la jornada esté abierta y no se esté ya en una.
                    pausaHabilitada: registroProvider.entrada1 != null &&
                        registroProvider.salidaReal == null &&
                        registroProvider.pausaAbierta == null,
                    continuarHabilitada:
                        registroProvider.pausaAbierta != null,
                    onEntrada: () => registroProvider.marcar(
                      MarcaTipo.entrada1,
                      nombreUsuario: nombre,
                    ),
                    onPausa: () => registroProvider.marcar(
                      MarcaTipo.pausa,
                      nombreUsuario: nombre,
                    ),
                    onContinuar: () => registroProvider.marcar(
                      MarcaTipo.reanudar,
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

/// Sugiere marcar el día como festivo cuando cae un asueto de ley.
///
/// Es una sugerencia y no una escritura automática a propósito: hay quien
/// trabaja los asuetos, y en ese caso las horas del día son tiempo extra,
/// no una ausencia justificada. La app no puede saber cuál de los dos casos
/// es sin preguntar.
class _AvisoAsueto extends StatelessWidget {
  final Asueto asueto;
  final VoidCallback onMarcar;
  final VoidCallback onDescartar;

  const _AvisoAsueto({
    required this.asueto,
    required this.onMarcar,
    required this.onDescartar,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      color: tema.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.celebration_outlined,
                  color: tema.colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Hoy es ${asueto.nombre}',
                    style: tema.textTheme.titleSmall?.copyWith(
                      color: tema.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Si no trabajas, márcalo como festivo y el día dejará de '
              'exigirte horas.',
              style: tema.textTheme.bodySmall?.copyWith(
                color: tema.colorScheme.onSecondaryContainer,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDescartar,
                  child: const Text('Hoy trabajo'),
                ),
                TextButton(
                  onPressed: onMarcar,
                  child: const Text('Marcar festivo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

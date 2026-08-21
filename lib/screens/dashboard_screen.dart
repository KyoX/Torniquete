import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

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

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarDatos());
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
                  const SizedBox(height: 16),
                  ExitBanner(
                    horaSalida: registroProvider.horaEstimadaSalida,
                    metaCumplida: registroProvider.metaCumplida,
                  ),
                  const SizedBox(height: 16),
                  ProgressCard(
                    progreso: registroProvider.progreso,
                    minutosTrabajados:
                        registroProvider.minutosTrabajadosHastaAhora,
                    metaMinutos: registroProvider.registroHoy?.metaMinutos ?? 0,
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

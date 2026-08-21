import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/registro.dart';
import '../providers/app_provider.dart';
import '../providers/registro_provider.dart';
import '../services/db_service.dart';
import '../services/reports_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_utils.dart';
import 'edit_day_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<Registro>> _historialFuture;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  void _cargarHistorial() {
    _historialFuture = DbService.instance.getHistorial();
  }

  String _formatearFecha(String fecha) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(fecha);
      return DateFormat('EEEE d MMMM yyyy', 'es').format(date);
    } catch (_) {
      return fecha;
    }
  }

  Future<void> _confirmarReinicio(Registro registro) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reiniciar día'),
        content: Text(
          'Se borrarán todas las marcas de ${_formatearFecha(registro.fecha)}. '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    await DbService.instance.eliminarRegistro(registro.fecha);

    if (registro.fecha == RegistroProvider.fechaHoy() && mounted) {
      final appProvider = context.read<AppProvider>();
      final metaMinutos =
          appProvider.metaMinutosParaDia(DateTime.now().weekday);
      await context.read<RegistroProvider>().cargarRegistroDeHoy(
            metaMinutos,
            nombreUsuario: appProvider.nombre,
          );
    }

    if (!mounted) return;
    setState(_cargarHistorial);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Día ${_formatearFecha(registro.fecha)} reiniciado')),
    );
  }

  Future<void> _agregarDia() async {
    final ahora = DateTime.now();
    final fecha = await showDatePicker(
      context: context,
      initialDate: ahora,
      firstDate: DateTime(ahora.year - 2),
      lastDate: ahora,
      helpText: 'Selecciona el día a registrar',
    );
    if (fecha == null || !mounted) return;

    final fechaStr = DateFormat('yyyy-MM-dd').format(fecha);
    final existente = await DbService.instance.getRegistroPorFecha(fechaStr);
    if (!mounted) return;

    final appProvider = context.read<AppProvider>();
    final registro = existente ??
        Registro(
          fecha: fechaStr,
          metaMinutos: appProvider.metaMinutosParaDia(fecha.weekday),
        );

    await _editarDia(registro);
  }

  Future<void> _editarDia(Registro registro) async {
    final guardado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditDayScreen(registro: registro)),
    );
    if (guardado != true) return;

    if (registro.fecha == RegistroProvider.fechaHoy() && mounted) {
      final appProvider = context.read<AppProvider>();
      final metaMinutos =
          appProvider.metaMinutosParaDia(DateTime.now().weekday);
      await context.read<RegistroProvider>().cargarRegistroDeHoy(
            metaMinutos,
            nombreUsuario: appProvider.nombre,
          );
    }

    if (!mounted) return;
    setState(_cargarHistorial);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _agregarDia,
        icon: const Icon(Icons.add),
        label: const Text('Agregar día'),
      ),
      body: FutureBuilder<List<Registro>>(
        future: _historialFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final registros = snapshot.data ?? [];
          if (registros.isEmpty) {
            return const Center(
              child: Text('Aún no hay registros guardados.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: registros.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final r = registros[index];
              final minutos = ReportsService.minutosTrabajados(r);
              final sinRegistro = minutos <= 0;
              final cumplida = !sinRegistro && minutos >= r.metaMinutos;
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _editarDia(r),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _formatearFecha(r.fecha),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            Icon(
                              cumplida
                                  ? Icons.check_circle
                                  : (sinRegistro
                                      ? Icons.remove_circle_outline
                                      : Icons.error_outline),
                              color: cumplida
                                  ? AppColors.cumplido
                                  : (sinRegistro
                                      ? AppColors.neutro
                                      : AppColors.pendiente),
                            ),
                            IconButton(
                              tooltip: 'Editar día',
                              icon: const Icon(Icons.edit),
                              onPressed: () => _editarDia(r),
                            ),
                            IconButton(
                              tooltip: 'Reiniciar día',
                              icon: const Icon(Icons.restart_alt),
                              onPressed: () => _confirmarReinicio(r),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          runSpacing: 4,
                          children: [
                            _Marca('Entrada', r.entrada1),
                            _Marca('Salida almuerzo', r.salida1),
                            _Marca('Regreso', r.entrada2),
                            _Marca('Salida real', r.salidaReal),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          sinRegistro
                              ? 'Sin horas registradas'
                              : '${TimeUtils.formatDurationMinutes(minutos)} '
                                  'de ${TimeUtils.formatDurationMinutes(r.metaMinutos)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Marca extends StatelessWidget {
  final String label;
  final String? valor;

  const _Marca(this.label, this.valor);

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label: ${TimeUtils.formatHHmm(valor)}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

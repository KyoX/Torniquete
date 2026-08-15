import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/registro.dart';
import '../services/db_service.dart';
import '../services/reports_service.dart';
import '../utils/time_utils.dart';
import '../widgets/mark_row.dart';

/// Permite editar manualmente todas las marcas de un día específico del
/// historial (por si se olvidó marcar o se cometió un error).
class EditDayScreen extends StatefulWidget {
  final Registro registro;

  const EditDayScreen({super.key, required this.registro});

  @override
  State<EditDayScreen> createState() => _EditDayScreenState();
}

class _EditDayScreenState extends State<EditDayScreen> {
  TimeOfDay? _entrada1;
  TimeOfDay? _salida1;
  TimeOfDay? _entrada2;
  TimeOfDay? _salidaReal;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _entrada1 = TimeUtils.parseTimeOfDay(widget.registro.entrada1);
    _salida1 = TimeUtils.parseTimeOfDay(widget.registro.salida1);
    _entrada2 = TimeUtils.parseTimeOfDay(widget.registro.entrada2);
    _salidaReal = TimeUtils.parseTimeOfDay(widget.registro.salidaReal);
  }

  String get _fechaFormateada {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(widget.registro.fecha);
      return DateFormat('EEEE d MMMM yyyy', 'es').format(date);
    } catch (_) {
      return widget.registro.fecha;
    }
  }

  Registro get _registroActualizado {
    return widget.registro.copyWith(
      entrada1: _entrada1 != null ? TimeUtils.formatTimeOfDay(_entrada1!) : null,
      salida1: _salida1 != null ? TimeUtils.formatTimeOfDay(_salida1!) : null,
      entrada2: _entrada2 != null ? TimeUtils.formatTimeOfDay(_entrada2!) : null,
      salidaReal:
          _salidaReal != null ? TimeUtils.formatTimeOfDay(_salidaReal!) : null,
      clearEntrada1: _entrada1 == null,
      clearSalida1: _salida1 == null,
      clearEntrada2: _entrada2 == null,
      clearSalidaReal: _salidaReal == null,
    );
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final actualizado = _registroActualizado;
    final minutos = ReportsService.minutosDesdeMarcas(actualizado);
    await DbService.instance.guardarRegistro(
      actualizado.copyWith(minutosCumplidos: minutos),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final preview = _registroActualizado;
    final minutosPreview = ReportsService.minutosDesdeMarcas(preview);
    final cumple = minutosPreview >= preview.metaMinutos;

    return Scaffold(
      appBar: AppBar(title: const Text('Editar día')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _fechaFormateada,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                MarkRow(
                  icon: Icons.login,
                  label: 'Entrada mañana',
                  horaTexto:
                      _entrada1 != null ? TimeUtils.formatTimeOfDay(_entrada1!) : '--:--',
                  valorActual: _entrada1,
                  onEditar: (t) => setState(() => _entrada1 = t),
                  onLimpiar: () => setState(() => _entrada1 = null),
                ),
                const Divider(height: 1),
                MarkRow(
                  icon: Icons.lunch_dining,
                  label: 'Salida almuerzo',
                  horaTexto:
                      _salida1 != null ? TimeUtils.formatTimeOfDay(_salida1!) : '--:--',
                  valorActual: _salida1,
                  onEditar: (t) => setState(() => _salida1 = t),
                  onLimpiar: () => setState(() => _salida1 = null),
                ),
                const Divider(height: 1),
                MarkRow(
                  icon: Icons.keyboard_return,
                  label: 'Entrada tarde',
                  horaTexto:
                      _entrada2 != null ? TimeUtils.formatTimeOfDay(_entrada2!) : '--:--',
                  valorActual: _entrada2,
                  onEditar: (t) => setState(() => _entrada2 = t),
                  onLimpiar: () => setState(() => _entrada2 = null),
                ),
                const Divider(height: 1),
                MarkRow(
                  icon: Icons.logout,
                  label: 'Salida real',
                  horaTexto: _salidaReal != null
                      ? TimeUtils.formatTimeOfDay(_salidaReal!)
                      : '--:--',
                  valorActual: _salidaReal,
                  onEditar: (t) => setState(() => _salidaReal = t),
                  onLimpiar: () => setState(() => _salidaReal = null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        cumple ? Icons.check_circle : Icons.remove_circle_outline,
                        color: cumple ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${TimeUtils.formatDurationMinutes(minutosPreview)} de '
                        '${TimeUtils.formatDurationMinutes(preview.metaMinutos)}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _guardando ? null : _guardar,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _guardando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar cambios'),
          ),
        ],
      ),
    );
  }
}

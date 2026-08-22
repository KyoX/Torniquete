import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/registro.dart';
import '../models/tipo_dia.dart';
import '../models/ubicacion_marca.dart';
import '../services/db_service.dart';
import '../services/reports_service.dart';
import '../theme/app_theme.dart';
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
  late TipoDia _tipoDia;
  late final TextEditingController _notaController;
  bool _guardando = false;
  Map<String, UbicacionMarca> _ubicaciones = {};

  @override
  void initState() {
    super.initState();
    _entrada1 = TimeUtils.parseTimeOfDay(widget.registro.entrada1);
    _salida1 = TimeUtils.parseTimeOfDay(widget.registro.salida1);
    _entrada2 = TimeUtils.parseTimeOfDay(widget.registro.entrada2);
    _salidaReal = TimeUtils.parseTimeOfDay(widget.registro.salidaReal);
    _tipoDia = widget.registro.tipoDia;
    _notaController = TextEditingController(text: widget.registro.nota ?? '');
    _cargarUbicaciones();
  }

  @override
  void dispose() {
    _notaController.dispose();
    super.dispose();
  }

  Future<void> _cargarUbicaciones() async {
    final ubicaciones =
        await DbService.instance.getUbicacionesPorFecha(widget.registro.fecha);
    if (!mounted) return;
    setState(() => _ubicaciones = ubicaciones);
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
    final nota = _notaController.text.trim();
    return widget.registro.copyWith(
      entrada1: _entrada1 != null ? TimeUtils.formatTimeOfDay(_entrada1!) : null,
      salida1: _salida1 != null ? TimeUtils.formatTimeOfDay(_salida1!) : null,
      entrada2: _entrada2 != null ? TimeUtils.formatTimeOfDay(_entrada2!) : null,
      salidaReal:
          _salidaReal != null ? TimeUtils.formatTimeOfDay(_salidaReal!) : null,
      tipoDia: _tipoDia,
      nota: nota,
      clearEntrada1: _entrada1 == null,
      clearSalida1: _salida1 == null,
      clearEntrada2: _entrada2 == null,
      clearSalidaReal: _salidaReal == null,
      clearNota: nota.isEmpty,
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
    final metaExigida = preview.metaEfectivaMinutos;
    final cumple = _tipoDia.esJustificado || minutosPreview >= metaExigida;

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
                  ubicacion: _ubicaciones['entrada1'],
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
                  ubicacion: _ubicaciones['salida1'],
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
                  ubicacion: _ubicaciones['entrada2'],
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
                  ubicacion: _ubicaciones['salidaReal'],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _TipoDiaSelector(
            valor: _tipoDia,
            notaController: _notaController,
            onCambiar: (tipo) => setState(() => _tipoDia = tipo),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        cumple ? Icons.check_circle : Icons.remove_circle_outline,
                        color: cumple ? AppColors.cumplido : AppColors.pendiente,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          metaExigida > 0
                              ? '${TimeUtils.formatDurationMinutes(minutosPreview)} de '
                                  '${TimeUtils.formatDurationMinutes(metaExigida)}'
                              : '${TimeUtils.formatDurationMinutes(minutosPreview)} '
                                  'trabajados, sin meta que cumplir',
                        ),
                      ),
                    ],
                  ),
                  if (_tipoDia.esJustificado) ...[
                    const SizedBox(height: 8),
                    Text(
                      minutosPreview > 0
                          ? 'Al ser ${_tipoDia.etiqueta.toLowerCase()}, las '
                              '${TimeUtils.formatDurationMinutes(minutosPreview)} '
                              'trabajadas cuentan completas como tiempo extra.'
                          : 'Al ser ${_tipoDia.etiqueta.toLowerCase()}, este día '
                              'no exige horas ni resta del banco.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
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

/// Selector del tipo de día más el campo de nota. Cambiar el tipo a algo
/// distinto de "día normal" hace que ese día deje de exigir meta de horas.
class _TipoDiaSelector extends StatelessWidget {
  final TipoDia valor;
  final TextEditingController notaController;
  final ValueChanged<TipoDia> onCambiar;

  const _TipoDiaSelector({
    required this.valor,
    required this.notaController,
    required this.onCambiar,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.event_note_outlined),
                const SizedBox(width: 10),
                Text(
                  'Tipo de día',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tipo in TipoDia.values)
                  ChoiceChip(
                    label: Text(tipo.etiqueta),
                    selected: tipo == valor,
                    onSelected: (elegido) {
                      if (elegido) onCambiar(tipo);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notaController,
              decoration: const InputDecoration(
                labelText: 'Nota (opcional)',
                hintText: 'Festivo de la Independencia, cita médica...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLength: 120,
            ),
            Text(
              valor.exigeMeta
                  ? 'Un día normal exige cumplir la meta de horas.'
                  : 'Los días de ${valor.etiqueta.toLowerCase()} no exigen '
                      'horas: no generan déficit y todo lo trabajado en ellos '
                      'suma como tiempo extra.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

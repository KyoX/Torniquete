import 'package:flutter/material.dart';

import '../../models/movimiento_banco.dart';
import '../../models/registro.dart';
import '../../services/export_service.dart';
import '../../utils/time_utils.dart';

/// Abre la hoja para exportar el reporte de cumplimiento. Devuelve la ruta
/// del archivo generado, o null si el usuario se echó atrás.
Future<String?> mostrarHojaExportar(
  BuildContext context, {
  required List<Registro> registros,
  required List<MovimientoBanco> movimientos,
  required int metaDiariaMinutos,
  String? nombre,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _HojaExportar(
      registros: registros,
      movimientos: movimientos,
      metaDiariaMinutos: metaDiariaMinutos,
      nombre: nombre,
    ),
  );
}

/// Periodos ofrecidos sin tener que elegir fechas a mano.
enum _PeriodoRapido {
  esteMes('Este mes'),
  mesPasado('Mes pasado'),
  ultimos15('Últimos 15 días'),
  ultimos30('Últimos 30 días'),
  todo('Todo el historial'),
  personalizado('Elegir fechas');

  const _PeriodoRapido(this.etiqueta);

  final String etiqueta;
}

class _HojaExportar extends StatefulWidget {
  final List<Registro> registros;
  final List<MovimientoBanco> movimientos;
  final int metaDiariaMinutos;
  final String? nombre;

  const _HojaExportar({
    required this.registros,
    required this.movimientos,
    required this.metaDiariaMinutos,
    this.nombre,
  });

  @override
  State<_HojaExportar> createState() => _HojaExportarState();
}

class _HojaExportarState extends State<_HojaExportar> {
  _PeriodoRapido _elegido = _PeriodoRapido.esteMes;

  /// Fechas del periodo personalizado, si el usuario llegó a elegirlas.
  DateTimeRange? _rango;

  bool _ocupado = false;

  PeriodoReporte get _periodo {
    final hoy = DateTime.now();
    switch (_elegido) {
      case _PeriodoRapido.esteMes:
        return PeriodoReporte.mes(hoy);
      case _PeriodoRapido.mesPasado:
        return PeriodoReporte.mes(DateTime(hoy.year, hoy.month - 1, 1));
      case _PeriodoRapido.ultimos15:
        return PeriodoReporte.ultimosDias(15, hasta: hoy);
      case _PeriodoRapido.ultimos30:
        return PeriodoReporte.ultimosDias(30, hasta: hoy);
      case _PeriodoRapido.todo:
        return PeriodoReporte.todo;
      case _PeriodoRapido.personalizado:
        final rango = _rango;
        // Sin fechas elegidas todavía, el periodo cae en el mes actual para
        // que la vista previa siempre tenga algo que enseñar.
        if (rango == null) return PeriodoReporte.mes(hoy);
        return PeriodoReporte.rango(rango.start, rango.end);
    }
  }

  ReporteComprobacion get _reporte => ReporteComprobacion.construir(
        registros: widget.registros,
        movimientos: widget.movimientos,
        periodo: _periodo,
        metaDiariaMinutos: widget.metaDiariaMinutos,
        nombre: widget.nombre,
      );

  Future<void> _elegirRango() async {
    final hoy = DateTime.now();
    final rango = await showDateRangePicker(
      context: context,
      firstDate: DateTime(hoy.year - 5),
      lastDate: DateTime(hoy.year + 1, 12, 31),
      initialDateRange: _rango,
      helpText: 'Periodo del reporte',
    );
    if (rango == null) return;
    setState(() {
      _rango = rango;
      _elegido = _PeriodoRapido.personalizado;
    });
  }

  Future<void> _exportar(FormatoReporte formato) async {
    setState(() => _ocupado = true);
    try {
      final ruta = await ExportService.instance.exportar(_reporte, formato);
      if (!mounted) return;
      Navigator.of(context).pop(ruta);
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el reporte: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final reporte = _reporte;
    final resumen = reporte.resumen;
    final vacio = reporte.vacio;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Exportar reporte', style: tema.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Un documento con los totales del periodo y el detalle día por '
              'día, para comprobar que el horario se cumplió.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final opcion in _PeriodoRapido.values)
                  ChoiceChip(
                    label: Text(opcion.etiqueta),
                    selected: _elegido == opcion,
                    onSelected: _ocupado
                        ? null
                        : (_) {
                            if (opcion == _PeriodoRapido.personalizado) {
                              _elegirRango();
                            } else {
                              setState(() => _elegido = opcion);
                            }
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tema.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reporte.periodo.etiqueta,
                    style: tema.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vacio
                        ? 'No hay días registrados en este periodo.'
                        : '${resumen.diasConHoras} días con marcas · '
                            '${TimeUtils.formatDurationMinutes(resumen.totalTrabajado)} '
                            'de ${TimeUtils.formatDurationMinutes(resumen.totalMeta)} '
                            '(${resumen.porcentaje.toStringAsFixed(0)}%)',
                    style: tema.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _ocupado || vacio
                        ? null
                        : () => _exportar(FormatoReporte.pdf),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _ocupado || vacio
                        ? null
                        : () => _exportar(FormatoReporte.excel),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('Excel'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_ocupado)
              const Padding(
                padding: EdgeInsets.only(top: 4, bottom: 8),
                child: LinearProgressIndicator(),
              ),
            Text(
              'El PDF es para imprimir o adjuntar; el Excel trae las horas '
              'en celdas numéricas para que quien revise pueda sumarlas.',
              style: tema.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

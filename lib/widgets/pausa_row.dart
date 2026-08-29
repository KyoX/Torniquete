import 'package:flutter/material.dart';

import '../models/pausa.dart';
import '../models/ubicacion_marca.dart';
import '../utils/time_utils.dart';
import 'ubicacion_info.dart';

/// Una pausa del día: cuándo se paró, cuándo se volvió y cuánto duró.
///
/// Las dos horas se editan por separado porque casi siempre lo que falla es
/// una sola: se marcó la pausa y se olvidó continuar, o al revés.
class PausaRow extends StatelessWidget {
  /// Posición de la pausa en el día, empezando en 1.
  final int numero;

  final Pausa pausa;

  /// True si es la pausa que cuenta como almuerzo.
  final bool esAlmuerzo;

  /// Minuto del día contra el que se mide una pausa todavía abierta.
  final int? minutosAhora;

  final ValueChanged<TimeOfDay> onEditarInicio;
  final ValueChanged<TimeOfDay> onEditarFin;
  final VoidCallback? onEliminar;

  final EvidenciaMarca evidenciaInicio;
  final EvidenciaMarca evidenciaFin;

  const PausaRow({
    super.key,
    required this.numero,
    required this.pausa,
    required this.onEditarInicio,
    required this.onEditarFin,
    this.esAlmuerzo = false,
    this.minutosAhora,
    this.onEliminar,
    this.evidenciaInicio = EvidenciaMarca.ninguna,
    this.evidenciaFin = EvidenciaMarca.ninguna,
  });

  String get _titulo => esAlmuerzo ? 'Pausa $numero · Almuerzo' : 'Pausa $numero';

  /// Cuánto lleva, o cuánto duró. Una pausa abierta se mide contra la hora
  /// actual, así que va creciendo mientras se está fuera.
  String get _duracion {
    final minutos = pausa.duracion(hasta: minutosAhora);
    if (pausa.abierta) {
      return minutos > 0
          ? 'En curso · ${TimeUtils.formatDurationMinutes(minutos)}'
          : 'En curso';
    }
    return TimeUtils.formatDurationMinutes(minutos);
  }

  Future<void> _editar(
    BuildContext context, {
    required String? actual,
    required ValueChanged<TimeOfDay> onElegir,
  }) async {
    final elegida = await showTimePicker(
      context: context,
      initialTime: TimeUtils.parseTimeOfDay(actual) ?? TimeOfDay.now(),
    );
    if (elegida != null) onElegir(elegida);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return ListTile(
      leading: Icon(
        esAlmuerzo ? Icons.lunch_dining : Icons.pause_circle_outline,
        color: pausa.abierta ? tema.colorScheme.primary : null,
      ),
      title: Text(_titulo),
      subtitle: Text(_duracion, style: tema.textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UbicacionIndicador(
            ubicacion: evidenciaInicio.ubicacion,
            capturando: evidenciaInicio.capturando,
            etiqueta: '$_titulo · salida',
            geocerca: evidenciaInicio.geocerca,
          ),
          _Hora(
            texto: TimeUtils.formatHHmm(pausa.inicio),
            onPressed: () => _editar(
              context,
              actual: pausa.inicio,
              onElegir: onEditarInicio,
            ),
          ),
          const Text('→'),
          _Hora(
            texto: TimeUtils.formatHHmm(pausa.fin),
            onPressed: () => _editar(
              context,
              actual: pausa.fin,
              onElegir: onEditarFin,
            ),
          ),
          UbicacionIndicador(
            ubicacion: evidenciaFin.ubicacion,
            capturando: evidenciaFin.capturando,
            etiqueta: '$_titulo · regreso',
            geocerca: evidenciaFin.geocerca,
          ),
          if (onEliminar != null)
            IconButton(
              tooltip: 'Borrar pausa',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              icon: const Icon(Icons.close, size: 18),
              onPressed: onEliminar,
            ),
        ],
      ),
    );
  }
}

class _Hora extends StatelessWidget {
  final String texto;
  final VoidCallback onPressed;

  const _Hora({required this.texto, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        texto,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    );
  }
}

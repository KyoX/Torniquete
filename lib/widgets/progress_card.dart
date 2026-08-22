import 'package:flutter/material.dart';

import '../utils/time_utils.dart';

/// Indicador visual del progreso de tiempo trabajado respecto a la meta.
class ProgressCard extends StatelessWidget {
  final double progreso; // 0..1
  final int minutosTrabajados;
  final int metaMinutos;

  const ProgressCard({
    super.key,
    required this.progreso,
    required this.minutosTrabajados,
    required this.metaMinutos,
  });

  /// Festivos, vacaciones, incapacidades y permisos no piden horas.
  bool get _sinMeta => metaMinutos <= 0;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Progreso del día',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                // Sin meta no hay porcentaje que calcular: un 100% ahí no
                // significaría nada.
                Text(_sinMeta ? 'Sin meta' : '${(progreso * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progreso,
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _sinMeta
                  ? '${TimeUtils.formatDurationMinutes(minutosTrabajados)} '
                      'trabajados, todo como tiempo extra'
                  : '${TimeUtils.formatDurationMinutes(minutosTrabajados)} de '
                      '${TimeUtils.formatDurationMinutes(metaMinutos)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

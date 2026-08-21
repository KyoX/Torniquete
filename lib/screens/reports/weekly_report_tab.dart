import 'package:flutter/material.dart';

import '../../models/registro.dart';
import '../../services/reports_service.dart';
import '../../utils/time_utils.dart';

class WeeklyReportTab extends StatelessWidget {
  final List<Registro> registros;

  const WeeklyReportTab({super.key, required this.registros});

  @override
  Widget build(BuildContext context) {
    final semanas = ReportsService.weeklyStats(registros);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: semanas.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final s = semanas[index];
        final porcentaje = s.porcentaje.clamp(0, 100) / 100;
        final cumplioSemana = s.totalTrabajado >= s.totalMeta;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      s.nombreSemana,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      '${s.porcentaje.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cumplioSemana ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: porcentaje.toDouble(),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${TimeUtils.formatDurationMinutes(s.totalTrabajado)} de '
                  '${TimeUtils.formatDurationMinutes(s.totalMeta)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${s.diasCumplidos} de ${s.totalDias} días cumplieron la meta',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (s.diasSinRegistro > 0)
                  Text(
                    '${s.diasSinRegistro} '
                    '${s.diasSinRegistro == 1 ? 'día sin horas registradas' : 'días sin horas registradas'} '
                    '(no cuentan)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/registro.dart';
import '../../services/reports_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_utils.dart';

class MonthlyReportTab extends StatelessWidget {
  final List<Registro> registros;

  const MonthlyReportTab({super.key, required this.registros});

  @override
  Widget build(BuildContext context) {
    final meses = ReportsService.monthlyStats(registros);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: meses.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final m = meses[index];
        final porcentaje = m.porcentaje.clamp(0, 100) / 100;
        final cumplioMes = m.totalTrabajado >= m.totalMeta;

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
                      m.nombreMes,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      '${m.porcentaje.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: cumplioMes ? AppColors.cumplido : AppColors.pendiente,
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
                  '${TimeUtils.formatDurationMinutes(m.totalTrabajado)} de '
                  '${TimeUtils.formatDurationMinutes(m.totalMeta)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '${m.diasCumplidos} de ${m.totalDias} días cumplieron la meta',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (m.diasSinRegistro > 0)
                  Text(
                    '${m.diasSinRegistro} '
                    '${m.diasSinRegistro == 1 ? 'día sin horas registradas' : 'días sin horas registradas'} '
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

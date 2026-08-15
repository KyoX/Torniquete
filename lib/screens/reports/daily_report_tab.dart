import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/registro.dart';
import '../../services/reports_service.dart';
import '../../utils/time_utils.dart';

class DailyReportTab extends StatelessWidget {
  final List<Registro> registros;

  const DailyReportTab({super.key, required this.registros});

  String _formatearFecha(String fecha) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(fecha);
      return DateFormat('EEEE d MMMM', 'es').format(date);
    } catch (_) {
      return fecha;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = ReportsService.dailyStats(registros);

    final ahora = DateTime.now();
    final yearMonthActual =
        '${ahora.year.toString().padLeft(4, '0')}-${ahora.month.toString().padLeft(2, '0')}';
    final delMes =
        stats.where((s) => s.registro.fecha.startsWith(yearMonthActual)).toList();
    final cumplidosMes = delMes.where((s) => s.cumplida).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Este mes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '$cumplidosMes de ${delMes.length} días cumplieron la meta',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...stats.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(
                        s.cumplida ? Icons.check_circle : Icons.remove_circle_outline,
                        color: s.cumplida ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _formatearFecha(s.registro.fecha),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${TimeUtils.formatDurationMinutes(s.minutosTrabajados)} '
                              'de ${TimeUtils.formatDurationMinutes(s.registro.metaMinutos)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        (s.diferenciaMinutos >= 0 ? '+' : '') +
                            TimeUtils.formatDurationMinutes(s.diferenciaMinutos),
                        style: TextStyle(
                          color: s.diferenciaMinutos >= 0 ? Colors.green : Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )),
      ],
    );
  }
}

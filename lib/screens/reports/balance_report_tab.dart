import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/registro.dart';
import '../../services/reports_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_utils.dart';

/// Banco de horas: balance acumulado (extra u déficit) entre lo trabajado
/// y la meta de cada día, a lo largo de todo el historial.
class BalanceReportTab extends StatelessWidget {
  final List<Registro> registros;

  const BalanceReportTab({super.key, required this.registros});

  String _formatearFecha(String fecha) {
    try {
      final date = DateFormat('yyyy-MM-dd').parse(fecha);
      return DateFormat('d MMM yyyy', 'es').format(date);
    } catch (_) {
      return fecha;
    }
  }

  @override
  Widget build(BuildContext context) {
    final balances = ReportsService.balanceHistorico(registros);
    final ordenDesc = balances.reversed.toList();
    final balanceTotal =
        balances.isEmpty ? 0 : balances.last.balanceAcumuladoMinutos;
    final scheme = Theme.of(context).colorScheme;
    final positivo = balanceTotal >= 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: positivo ? scheme.primaryContainer : scheme.errorContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Text(
                'Balance acumulado',
                style: TextStyle(
                  color: positivo
                      ? scheme.onPrimaryContainer
                      : scheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                (positivo ? '+' : '') +
                    TimeUtils.formatDurationMinutes(balanceTotal),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 32,
                  color: positivo
                      ? scheme.onPrimaryContainer
                      : scheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                positivo
                    ? 'Tienes tiempo extra acumulado'
                    : 'Estás en déficit de horas',
                style: TextStyle(
                  color: positivo
                      ? scheme.onPrimaryContainer
                      : scheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ...ordenDesc.map((b) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(_formatearFecha(b.fecha)),
                subtitle: Text(
                  b.sinRegistro
                      ? 'Sin horas registradas · balance sin cambios: '
                          '${b.balanceAcumuladoMinutos >= 0 ? '+' : ''}'
                          '${TimeUtils.formatDurationMinutes(b.balanceAcumuladoMinutos)}'
                      : 'Balance acumulado: '
                          '${b.balanceAcumuladoMinutos >= 0 ? '+' : ''}'
                          '${TimeUtils.formatDurationMinutes(b.balanceAcumuladoMinutos)}',
                ),
                trailing: Text(
                  b.sinRegistro
                      ? '—'
                      : (b.diferenciaMinutos >= 0 ? '+' : '') +
                          TimeUtils.formatDurationMinutes(b.diferenciaMinutos),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: b.sinRegistro
                        ? AppColors.neutro
                        : (b.diferenciaMinutos >= 0
                            ? AppColors.cumplido
                            : AppColors.rojo),
                  ),
                ),
              ),
            )),
      ],
    );
  }
}

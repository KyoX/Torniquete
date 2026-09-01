import 'package:flutter/material.dart';

import '../../models/registro.dart';
import '../../services/prefs_service.dart';
import '../../services/reports_service.dart';
import '../../utils/time_utils.dart';

/// Patrones del historial completo: hora habitual de entrada y salida, el
/// día que más rinde y la racha de cumplimiento. A diferencia de las demás
/// pestañas, que comparan contra la meta de un periodo, esta no juzga nada:
/// solo describe el hábito.
class PersonalStatsTab extends StatelessWidget {
  final List<Registro> registros;

  const PersonalStatsTab({super.key, required this.registros});

  @override
  Widget build(BuildContext context) {
    final stats = ReportsService.estadisticasPersonales(registros);

    if (stats.diasConHoras == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Todavía no hay suficientes días con horas registradas.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Tarjeta(
          icono: Icons.login,
          titulo: 'Hora habitual de entrada',
          valor: stats.minutosEntradaPromedio == null
              ? 'Sin datos'
              : TimeUtils.formatAmPm(
                  TimeUtils.fromMinutes(stats.minutosEntradaPromedio!)),
        ),
        const SizedBox(height: 10),
        _Tarjeta(
          icono: Icons.logout,
          titulo: 'Hora habitual de salida',
          valor: stats.minutosSalidaPromedio == null
              ? 'Sin días cerrados todavía'
              : TimeUtils.formatAmPm(
                  TimeUtils.fromMinutes(stats.minutosSalidaPromedio!)),
        ),
        const SizedBox(height: 10),
        _Tarjeta(
          icono: Icons.emoji_events_outlined,
          titulo: 'Día más productivo',
          valor: stats.diaMasProductivo == null
              ? 'Sin datos'
              : DiasSemana.capitalizar(
                  DiasSemana.nombre(stats.diaMasProductivo!)),
          detalle: stats.diaMasProductivo == null
              ? null
              : 'En promedio, '
                  '${TimeUtils.formatDurationMinutes(stats.minutosDiaMasProductivo)} '
                  'trabajadas',
        ),
        const SizedBox(height: 10),
        _Tarjeta(
          icono: Icons.local_fire_department_outlined,
          titulo: 'Racha actual de días cumplidos',
          valor: stats.rachaActual == 1
              ? '1 día'
              : '${stats.rachaActual} días',
          detalle: stats.mejorRacha > stats.rachaActual
              ? 'La mejor racha fue de ${stats.mejorRacha} días'
              : (stats.mejorRacha > 0 ? '¡Es tu mejor racha!' : null),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Calculado sobre ${stats.diasConHoras} '
            '${stats.diasConHoras == 1 ? 'día con horas registradas' : 'días con horas registradas'}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String valor;
  final String? detalle;

  const _Tarjeta({
    required this.icono,
    required this.titulo,
    required this.valor,
    this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icono, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    valor,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  if (detalle != null)
                    Text(detalle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

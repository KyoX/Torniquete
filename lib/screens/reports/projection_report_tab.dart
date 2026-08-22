import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/registro.dart';
import '../../providers/app_provider.dart';
import '../../services/reports_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_utils.dart';

class ProjectionReportTab extends StatelessWidget {
  final List<Registro> registros;

  const ProjectionReportTab({super.key, required this.registros});

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final proyeccion = ReportsService.proyeccionMesActual(
      registros,
      appProvider,
      DateTime.now(),
    );
    final vaACumplir = proyeccion.vaACumplir;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: vaACumplir
                ? scheme.primaryContainer
                : scheme.errorContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Icon(
                vaACumplir ? Icons.trending_up : Icons.warning_amber_rounded,
                size: 40,
                color: vaACumplir
                    ? scheme.onPrimaryContainer
                    : scheme.onErrorContainer,
              ),
              const SizedBox(height: 10),
              Text(
                vaACumplir
                    ? 'Vas en camino a cumplir la meta del mes'
                    : 'En riesgo de no cumplir la meta del mes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: vaACumplir
                      ? scheme.onPrimaryContainer
                      : scheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Semana ${proyeccion.semanaActual} de ${proyeccion.totalSemanasMes}',
                style: TextStyle(
                  color: vaACumplir
                      ? scheme.onPrimaryContainer
                      : scheme.onErrorContainer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _InfoCard(
          titulo: 'Trabajado hasta hoy',
          valor: TimeUtils.formatDurationMinutes(
              proyeccion.trabajadoHastaHoyMinutos),
        ),
        _InfoCard(
          titulo: 'Proyección a fin de mes',
          valor: TimeUtils.formatDurationMinutes(
              proyeccion.proyeccionTotalMinutos),
        ),
        _InfoCard(
          titulo: 'Meta del mes',
          valor: TimeUtils.formatDurationMinutes(proyeccion.metaMesMinutos),
        ),
        _InfoCard(
          titulo: proyeccion.diferenciaMinutos >= 0
              ? 'Excedente proyectado'
              : 'Déficit proyectado',
          valor: TimeUtils.formatDurationMinutes(
              proyeccion.diferenciaMinutos.abs()),
          destacado: true,
          positivo: proyeccion.diferenciaMinutos >= 0,
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String titulo;
  final String valor;
  final bool destacado;
  final bool positivo;

  const _InfoCard({
    required this.titulo,
    required this.valor,
    this.destacado = false,
    this.positivo = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(titulo),
            Text(
              valor,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: destacado
                    ? (positivo ? AppColors.cumplidoDe(context) : AppColors.rojoDe(context))
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../models/tipo_dia.dart';
import '../theme/app_theme.dart';
import '../utils/time_utils.dart';

/// Banner destacado superior con la hora exacta de salida (o un mensaje
/// indicando qué falta para poder calcularla).
class ExitBanner extends StatelessWidget {
  final TimeOfDay? horaSalida;
  final bool metaCumplida;

  /// En un festivo, unas vacaciones o una incapacidad no hay hora de salida
  /// que calcular, así que el banner dice otra cosa.
  final TipoDia tipoDia;

  const ExitBanner({
    super.key,
    required this.horaSalida,
    required this.metaCumplida,
    this.tipoDia = TipoDia.normal,
  });

  @override
  Widget build(BuildContext context) {
    final tieneHora = horaSalida != null;
    final justificado = tipoDia.esJustificado;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.azul, AppColors.azulMedio],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            justificado
                ? 'Hoy no exige horas'
                : (tieneHora ? '🎉 Hora de salida' : 'Hora de salida estimada'),
            style: const TextStyle(
              color: AppColors.blanco,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            justificado
                ? tipoDia.etiqueta
                : (tieneHora
                    ? TimeUtils.formatAmPm(horaSalida!)
                    : 'Registra tus marcas para calcularla'),
            style: TextStyle(
              color: tieneHora && !justificado
                  ? AppColors.amarillo
                  : AppColors.blanco,
              fontWeight: FontWeight.bold,
              fontSize: tieneHora && !justificado ? 34 : 18,
            ),
          ),
          if (justificado) ...[
            const SizedBox(height: 6),
            const Text(
              'Lo que trabajes hoy cuenta completo como tiempo extra',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.blanco, fontSize: 13),
            ),
          ] else if (metaCumplida) ...[
            const SizedBox(height: 6),
            const Text(
              '✅ Meta de horas cumplida',
              style: TextStyle(
                color: AppColors.blanco,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

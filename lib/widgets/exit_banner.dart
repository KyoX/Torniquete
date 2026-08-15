import 'package:flutter/material.dart';

import '../utils/time_utils.dart';

/// Banner destacado superior con la hora exacta de salida (o un mensaje
/// indicando qué falta para poder calcularla).
class ExitBanner extends StatelessWidget {
  final TimeOfDay? horaSalida;
  final bool metaCumplida;

  const ExitBanner({
    super.key,
    required this.horaSalida,
    required this.metaCumplida,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tieneHora = horaSalida != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.primary.withValues(alpha: 0.35)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            tieneHora ? '🎉 Hora de salida' : 'Hora de salida estimada',
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tieneHora
                ? TimeUtils.formatAmPm(horaSalida!)
                : 'Registra tus marcas para calcularla',
            style: TextStyle(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.bold,
              fontSize: tieneHora ? 34 : 18,
            ),
          ),
          if (metaCumplida) ...[
            const SizedBox(height: 6),
            Text(
              '✅ Meta de horas cumplida',
              style: TextStyle(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Los tres botones de marca del día.
///
/// "Pausa" y "Continuar" sustituyen a la salida y el regreso del almuerzo:
/// un día puede tener varias interrupciones —una diligencia a media mañana y
/// luego la comida— y con un solo par de marcas había que elegir cuál de las
/// dos registrar. Cuál de las pausas fue el almuerzo lo deduce la app por la
/// hora, así que no hay nada que decidir al marcar.
class QuickActionButtons extends StatelessWidget {
  final bool entradaHabilitada;
  final bool pausaHabilitada;
  final bool continuarHabilitada;
  final VoidCallback onEntrada;
  final VoidCallback onPausa;
  final VoidCallback onContinuar;

  const QuickActionButtons({
    super.key,
    required this.entradaHabilitada,
    required this.pausaHabilitada,
    required this.continuarHabilitada,
    required this.onEntrada,
    required this.onPausa,
    required this.onContinuar,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Entrada',
            icon: Icons.login,
            enabled: entradaHabilitada,
            onPressed: onEntrada,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            label: 'Pausa',
            icon: Icons.pause_circle_outline,
            enabled: pausaHabilitada,
            onPressed: onPausa,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            label: 'Continuar',
            icon: Icons.play_circle_outline,
            enabled: continuarHabilitada,
            onPressed: onContinuar,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: enabled ? onPressed : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

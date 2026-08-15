import 'package:flutter/material.dart';

/// 3 botones de acción rápida para las marcas del día.
class QuickActionButtons extends StatelessWidget {
  final bool entrada1Habilitada;
  final bool salida1Habilitada;
  final bool entrada2Habilitada;
  final VoidCallback onEntrada;
  final VoidCallback onSalidaComer;
  final VoidCallback onRegresoComer;

  const QuickActionButtons({
    super.key,
    required this.entrada1Habilitada,
    required this.salida1Habilitada,
    required this.entrada2Habilitada,
    required this.onEntrada,
    required this.onSalidaComer,
    required this.onRegresoComer,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            label: 'Entrada',
            icon: Icons.login,
            enabled: entrada1Habilitada,
            onPressed: onEntrada,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            label: 'Salida\nComer',
            icon: Icons.lunch_dining,
            enabled: salida1Habilitada,
            onPressed: onSalidaComer,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            label: 'Regreso\nComer',
            icon: Icons.keyboard_return,
            enabled: entrada2Habilitada,
            onPressed: onRegresoComer,
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

import 'package:flutter/material.dart';

/// Fila que muestra una marca de tiempo (icono + etiqueta + hora) y permite
/// editarla manualmente mediante un TimePicker por si se olvidó marcar.
class MarkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String horaTexto;
  final TimeOfDay? valorActual;
  final ValueChanged<TimeOfDay> onEditar;

  const MarkRow({
    super.key,
    required this.icon,
    required this.label,
    required this.horaTexto,
    required this.valorActual,
    required this.onEditar,
  });

  Future<void> _editar(BuildContext context) async {
    final resultado = await showTimePicker(
      context: context,
      initialTime: valorActual ?? TimeOfDay.now(),
    );
    if (resultado != null) {
      onEditar(resultado);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: TextButton.icon(
        onPressed: () => _editar(context),
        icon: const Icon(Icons.edit, size: 16),
        label: Text(
          horaTexto,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}

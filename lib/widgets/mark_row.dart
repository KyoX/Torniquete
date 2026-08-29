import 'package:flutter/material.dart';

import '../models/ubicacion_marca.dart';
import 'ubicacion_info.dart';

/// Fila que muestra una marca de tiempo (icono + etiqueta + hora) y permite
/// editarla manualmente mediante un TimePicker por si se olvidó marcar.
class MarkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String horaTexto;
  final TimeOfDay? valorActual;
  final ValueChanged<TimeOfDay> onEditar;
  final VoidCallback? onLimpiar;

  /// Dónde se registró la marca, si el usuario habilitó la ubicación.
  final EvidenciaMarca evidencia;

  const MarkRow({
    super.key,
    required this.icon,
    required this.label,
    required this.horaTexto,
    required this.valorActual,
    required this.onEditar,
    this.onLimpiar,
    this.evidencia = EvidenciaMarca.ninguna,
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UbicacionIndicador(
            ubicacion: evidencia.ubicacion,
            capturando: evidencia.capturando,
            etiqueta: label,
            geocerca: evidencia.geocerca,
          ),
          TextButton.icon(
            onPressed: () => _editar(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.edit, size: 16),
            label: Text(
              horaTexto,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          if (onLimpiar != null && valorActual != null)
            IconButton(
              tooltip: 'Borrar marca',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              icon: const Icon(Icons.close, size: 18),
              onPressed: onLimpiar,
            ),
        ],
      ),
    );
  }
}

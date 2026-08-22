import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/ubicacion_marca.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../utils/geo_utils.dart';

/// Muestra el detalle de la ubicación guardada para una marca, con la opción
/// de copiar las coordenadas o el enlace de mapa (útil en una auditoría).
Future<void> mostrarUbicacionMarca(
  BuildContext context,
  UbicacionMarca ubicacion,
  String etiqueta, {
  EvaluacionGeocerca? geocerca,
}) {
  final messenger = ScaffoldMessenger.of(context);

  Future<void> copiar(String texto, String aviso) async {
    await Clipboard.setData(ClipboardData(text: texto));
    messenger.showSnackBar(SnackBar(content: Text(aviso)));
  }

  Future<void> abrirEnMapas() async {
    final abierto = await LocationService.instance.abrirEnMapas(
      latitud: ubicacion.latitud,
      longitud: ubicacion.longitud,
      etiqueta: etiqueta,
    );
    if (abierto) return;
    // Sin app de mapas ni navegador: al menos que se lleve el enlace.
    await copiar(
      ubicacion.enlaceMaps,
      'No se encontró una app de mapas. Enlace copiado.',
    );
  }

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Ubicación · $etiqueta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detalle('Marca', '${ubicacion.fecha} a las ${ubicacion.hora}'),
          _detalle('Coordenadas', ubicacion.coordenadas),
          if (geocerca != null)
            _detalle(
              'Sede',
              geocerca.dentro
                  ? 'Dentro del radio (${geocerca.distanciaLegible})'
                  : 'A ${geocerca.distanciaLegible}, fuera del radio de '
                      '${geocerca.radioMetros} m',
            ),
          if (ubicacion.precisionMetros != null)
            _detalle('Precisión',
                '± ${ubicacion.precisionMetros!.toStringAsFixed(0)} m'),
          _detalle(
            'Capturada',
            DateFormat('d MMM yyyy HH:mm:ss', 'es')
                .format(ubicacion.capturadoEn),
          ),
          if (ubicacion.manual)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'La hora se escribió a mano: la ubicación corresponde al '
                'momento en que se editó la marca.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: abrirEnMapas,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Abrir en Maps'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => copiar(ubicacion.coordenadas, 'Coordenadas copiadas'),
          child: const Text('Copiar coordenadas'),
        ),
        TextButton(
          onPressed: () => copiar(ubicacion.enlaceMaps, 'Enlace copiado'),
          child: const Text('Copiar enlace'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

Widget _detalle(String etiqueta, String valor) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(etiqueta,
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        Expanded(child: Text(valor)),
      ],
    ),
  );
}

/// Icono que acompaña a una marca: girando mientras se captura el GPS,
/// verde cuando hay ubicación guardada (tocable para ver el detalle).
class UbicacionIndicador extends StatelessWidget {
  final UbicacionMarca? ubicacion;
  final bool capturando;
  final String etiqueta;

  /// Comparación con la geocerca de la sede, si está configurada.
  final EvaluacionGeocerca? geocerca;

  const UbicacionIndicador({
    super.key,
    required this.ubicacion,
    required this.etiqueta,
    this.capturando = false,
    this.geocerca,
  });

  @override
  Widget build(BuildContext context) {
    if (capturando) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final guardada = ubicacion;
    if (guardada == null) return const SizedBox.shrink();
    // El alfiler cambia de color cuando la marca cayó fuera de la sede, para
    // que se note sin tener que abrir el detalle.
    final fuera = geocerca?.fuera ?? false;
    return IconButton(
      tooltip: fuera
          ? 'Marcada a ${geocerca!.distanciaLegible} de la sede'
          : 'Ver ubicación registrada',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      icon: Icon(
        fuera ? Icons.wrong_location : Icons.place,
        size: 18,
        color: fuera ? AppColors.pendiente : AppColors.azul,
      ),
      onPressed: () => mostrarUbicacionMarca(
        context,
        guardada,
        etiqueta,
        geocerca: geocerca,
      ),
    );
  }
}

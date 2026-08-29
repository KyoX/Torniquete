import '../utils/geo_utils.dart';

/// Ubicación capturada en el momento en que se registró una marca del día.
/// Sirve como evidencia (por ejemplo, ante una auditoría) de que la persona
/// estaba en el lugar de trabajo al marcar.
class UbicacionMarca {
  final int? id;
  final String fecha; // YYYY-MM-DD
  /// Qué marca es, por su clave: ver `ClaveUbicacion`. Solo llevan evidencia
  /// la entrada, la salida real y las dos horas de la pausa del almuerzo.
  final String tipo;
  final String hora; // HH:mm de la marca
  final double latitud;
  final double longitud;
  final double? precisionMetros;
  final DateTime capturadoEn;

  /// true cuando la marca se escribió a mano (no con los botones rápidos);
  /// la ubicación corresponde al momento de la edición, no al de la marca.
  final bool manual;

  const UbicacionMarca({
    this.id,
    required this.fecha,
    required this.tipo,
    required this.hora,
    required this.latitud,
    required this.longitud,
    this.precisionMetros,
    required this.capturadoEn,
    this.manual = false,
  });

  /// Coordenadas en el formato que entienden Google Maps y similares.
  String get coordenadas =>
      '${latitud.toStringAsFixed(6)}, ${longitud.toStringAsFixed(6)}';

  String get enlaceMaps =>
      'https://www.google.com/maps/search/?api=1&query=$latitud,$longitud';

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'fecha': fecha,
      'tipo': tipo,
      'hora': hora,
      'latitud': latitud,
      'longitud': longitud,
      'precision_m': precisionMetros,
      'capturado_en': capturadoEn.toIso8601String(),
      'manual': manual ? 1 : 0,
    };
  }

  factory UbicacionMarca.fromMap(Map<String, Object?> map) {
    return UbicacionMarca(
      id: map['id'] as int?,
      fecha: map['fecha'] as String,
      tipo: map['tipo'] as String,
      hora: map['hora'] as String? ?? '--:--',
      latitud: (map['latitud'] as num).toDouble(),
      longitud: (map['longitud'] as num).toDouble(),
      precisionMetros: (map['precision_m'] as num?)?.toDouble(),
      capturadoEn:
          DateTime.tryParse(map['capturado_en'] as String? ?? '') ??
              DateTime.now(),
      manual: (map['manual'] as int? ?? 0) == 1,
    );
  }
}

/// Todo lo que se sabe de dónde se registró una marca, en un solo objeto.
///
/// Va junto porque las tres cosas se enseñan en el mismo sitio y las tres
/// pueden faltar a la vez: sin el ajuste de ubicación activado no hay nada
/// que contar.
class EvidenciaMarca {
  final UbicacionMarca? ubicacion;

  /// True mientras el GPS está respondiendo a esta marca en concreto.
  final bool capturando;

  /// Qué tan lejos de la sede quedó, si la geocerca está configurada.
  final EvaluacionGeocerca? geocerca;

  const EvidenciaMarca({
    this.ubicacion,
    this.capturando = false,
    this.geocerca,
  });

  static const EvidenciaMarca ninguna = EvidenciaMarca();
}

/// Ubicación capturada en el momento en que se registró una marca del día.
/// Sirve como evidencia (por ejemplo, ante una auditoría) de que la persona
/// estaba en el lugar de trabajo al marcar.
class UbicacionMarca {
  final int? id;
  final String fecha; // YYYY-MM-DD
  final String tipo; // entrada1 | salida1 | entrada2 | salidaReal
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

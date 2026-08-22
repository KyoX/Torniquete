import 'dart:math' as math;

/// Resultado de comparar una marca contra la geocerca de la sede.
class EvaluacionGeocerca {
  /// Distancia en metros entre la marca y la sede.
  final double distanciaMetros;

  /// Radio configurado como "estoy en el trabajo".
  final int radioMetros;

  const EvaluacionGeocerca({
    required this.distanciaMetros,
    required this.radioMetros,
  });

  bool get dentro => distanciaMetros <= radioMetros;
  bool get fuera => !dentro;

  /// Distancia redondeada a algo legible: metros hasta el kilómetro, luego
  /// kilómetros con un decimal.
  String get distanciaLegible {
    if (distanciaMetros < 1000) return '${distanciaMetros.round()} m';
    return '${(distanciaMetros / 1000).toStringAsFixed(1)} km';
  }
}

/// Cálculos de distancia sobre la superficie terrestre.
class GeoUtils {
  const GeoUtils._();

  /// Radio medio de la Tierra en metros.
  static const double _radioTierraM = 6371008.8;

  /// Distancia en metros entre dos coordenadas (fórmula del haversine).
  ///
  /// Para las distancias que maneja la app —del orden de metros a unos pocos
  /// kilómetros— tratar la Tierra como una esfera sobra: el error frente a
  /// un cálculo elipsoidal es de centímetros.
  static double distanciaMetros(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _aRadianes(lat2 - lat1);
    final dLon = _aRadianes(lon2 - lon1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_aRadianes(lat1)) *
            math.cos(_aRadianes(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * _radioTierraM * math.asin(math.min(1, math.sqrt(a)));
  }

  static double _aRadianes(double grados) => grados * math.pi / 180;

  /// Compara una posición contra la sede. Devuelve null si la sede no tiene
  /// coordenadas guardadas todavía.
  static EvaluacionGeocerca? evaluar({
    required double? sedeLatitud,
    required double? sedeLongitud,
    required int radioMetros,
    required double latitud,
    required double longitud,
  }) {
    if (sedeLatitud == null || sedeLongitud == null) return null;
    return EvaluacionGeocerca(
      distanciaMetros:
          distanciaMetros(sedeLatitud, sedeLongitud, latitud, longitud),
      radioMetros: radioMetros,
    );
  }
}

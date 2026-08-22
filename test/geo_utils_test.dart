import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/utils/geo_utils.dart';

void main() {
  // Un punto cualquiera de Bogotá, que es donde vive el caso de uso.
  const sedeLat = 4.60971;
  const sedeLon = -74.08175;

  group('distanciaMetros', () {
    test('el mismo punto está a cero metros', () {
      expect(
        GeoUtils.distanciaMetros(sedeLat, sedeLon, sedeLat, sedeLon),
        closeTo(0, 0.001),
      );
    });

    test('una milésima de grado de latitud son unos 111 metros', () {
      expect(
        GeoUtils.distanciaMetros(sedeLat, sedeLon, sedeLat + 0.001, sedeLon),
        closeTo(111.2, 1),
      );
    });

    test('la distancia es simétrica', () {
      final ida = GeoUtils.distanciaMetros(sedeLat, sedeLon, 4.65, -74.05);
      final vuelta = GeoUtils.distanciaMetros(4.65, -74.05, sedeLat, sedeLon);
      expect(ida, closeTo(vuelta, 0.001));
    });
  });

  group('evaluar', () {
    test('sin coordenadas de sede no hay nada que evaluar', () {
      expect(
        GeoUtils.evaluar(
          sedeLatitud: null,
          sedeLongitud: null,
          radioMetros: 200,
          latitud: sedeLat,
          longitud: sedeLon,
        ),
        isNull,
      );
    });

    test('una marca junto a la sede queda dentro del radio', () {
      final evaluacion = GeoUtils.evaluar(
        sedeLatitud: sedeLat,
        sedeLongitud: sedeLon,
        radioMetros: 200,
        // Unos 55 metros al norte.
        latitud: sedeLat + 0.0005,
        longitud: sedeLon,
      )!;
      expect(evaluacion.dentro, isTrue);
      expect(evaluacion.fuera, isFalse);
      expect(evaluacion.distanciaMetros, closeTo(55.6, 1));
    });

    test('una marca a un kilómetro queda fuera', () {
      final evaluacion = GeoUtils.evaluar(
        sedeLatitud: sedeLat,
        sedeLongitud: sedeLon,
        radioMetros: 200,
        latitud: sedeLat + 0.01,
        longitud: sedeLon,
      )!;
      expect(evaluacion.fuera, isTrue);
      expect(evaluacion.distanciaLegible, '1.1 km');
    });

    test('la distancia legible pasa de metros a kilómetros en los 1000 m', () {
      const enMetros = EvaluacionGeocerca(
        distanciaMetros: 999.4,
        radioMetros: 200,
      );
      const enKilometros = EvaluacionGeocerca(
        distanciaMetros: 1500,
        radioMetros: 200,
      );
      expect(enMetros.distanciaLegible, '999 m');
      expect(enKilometros.distanciaLegible, '1.5 km');
    });

    test('justo en el borde del radio se considera dentro', () {
      const borde = EvaluacionGeocerca(distanciaMetros: 200, radioMetros: 200);
      expect(borde.dentro, isTrue);
    });
  });
}

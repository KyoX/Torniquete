import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/services/location_service.dart';
import 'package:torniquete/services/prefs_service.dart';

void main() {
  final servicio = LocationService.instance;

  // San Salvador, Plaza Cívica: coordenadas fijas para las dos sedes.
  const sedePrincipal = SedeConfig(
    activa: true,
    latitud: 13.6989,
    longitud: -89.1914,
    radioMetros: 100,
    nombre: 'Oficina principal',
  );

  group('evaluarSedes', () {
    test('sin ninguna sede vigente no hay nada que evaluar', () {
      final resultado = servicio.evaluarSedes(
        const SedeConfig(),
        latitud: 13.6989,
        longitud: -89.1914,
      );
      expect(resultado, isNull);
    });

    test('con una sola sede vigente, se evalúa contra ella', () {
      final resultado = servicio.evaluarSedes(
        sedePrincipal,
        latitud: 13.6989,
        longitud: -89.1914,
      );
      expect(resultado, isNotNull);
      expect(resultado!.nombre, 'Oficina principal');
      expect(resultado.evaluacion.dentro, isTrue);
    });

    test('si la marca cae dentro de la segunda sede, se prefiere esa', () {
      final sede2 = const SedeSecundaria(
        activa: true,
        latitud: 13.7000,
        longitud: -89.2000,
        radioMetros: 100,
        nombre: 'Coworking',
      );
      // Lejos de la principal, pero justo en la segunda.
      final resultado = servicio.evaluarSedes(
        sedePrincipal,
        sede2: sede2,
        latitud: 13.7000,
        longitud: -89.2000,
      );
      expect(resultado!.nombre, 'Coworking');
      expect(resultado.evaluacion.dentro, isTrue);
    });

    test('fuera de las dos, se queda con la más cercana', () {
      final sede2 = const SedeSecundaria(
        activa: true,
        // Mucho más lejos que la principal.
        latitud: 14.5,
        longitud: -90.5,
        radioMetros: 100,
        nombre: 'Sucursal lejana',
      );
      final resultado = servicio.evaluarSedes(
        sedePrincipal,
        sede2: sede2,
        // Un poco fuera del radio de la principal, muy lejos de la segunda.
        latitud: 13.699,
        longitud: -89.190,
      );
      expect(resultado!.nombre, 'Oficina principal');
      expect(resultado.evaluacion.dentro, isFalse);
    });

    test('una segunda sede inactiva no participa', () {
      final sede2 = const SedeSecundaria(
        activa: false,
        latitud: 13.7000,
        longitud: -89.2000,
        radioMetros: 100,
        nombre: 'Coworking',
      );
      final resultado = servicio.evaluarSedes(
        sedePrincipal,
        sede2: sede2,
        latitud: 13.7000,
        longitud: -89.2000,
      );
      expect(resultado!.nombre, 'Oficina principal');
      expect(resultado.evaluacion.dentro, isFalse);
    });
  });
}

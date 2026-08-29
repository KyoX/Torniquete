import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/services/prefs_service.dart';

/// Los días de la semana en los que se va a la sede.
///
/// Quien decide si hoy toca preguntar es el receptor nativo, que lee la
/// máscara de bits que se le manda; lo que se prueba aquí es la parte de la
/// que depende esa decisión: cuándo hay algo que vigilar y cómo se le cuenta
/// al usuario lo que eligió.
void main() {
  const sede = SedeConfig(
    latitud: 13.7,
    longitud: -89.2,
    avisarAlLlegar: true,
  );

  group('vigilanciaLlegadaVigente', () {
    test('de lunes a viernes por defecto', () {
      expect(sede.diasOficina, {1, 2, 3, 4, 5});
      expect(sede.vigilanciaLlegadaVigente, isTrue);
    });

    test('sin ningún día no hay nada que vigilar', () {
      // Registrar la geocerca igualmente dejaría a Android despertando a la
      // app para un aviso que nunca va a salir.
      expect(
        sede.copyWith(diasOficina: const {}).vigilanciaLlegadaVigente,
        isFalse,
      );
    });

    test('un solo día basta para vigilar', () {
      expect(
        sede.copyWith(diasOficina: const {3}).vigilanciaLlegadaVigente,
        isTrue,
      );
    });

    test('sin coordenadas los días no sirven de nada', () {
      const sinSede = SedeConfig(avisarAlLlegar: true);
      expect(sinSede.vigilanciaLlegadaVigente, isFalse);
    });
  });

  group('diasOficinaLegible', () {
    test('la semana laboral típica se dice de corrido', () {
      expect(sede.diasOficinaLegible, 'De lunes a viernes');
    });

    test('la semana entera', () {
      expect(
        sede.copyWith(diasOficina: const {1, 2, 3, 4, 5, 6, 7}).diasOficinaLegible,
        'Todos los días',
      );
    });

    test('ningún día se dice tal cual', () {
      expect(sede.copyWith(diasOficina: const {}).diasOficinaLegible,
          'Ningún día');
    });

    test('un solo día', () {
      expect(
        sede.copyWith(diasOficina: const {3}).diasOficinaLegible,
        'Miércoles',
      );
    });

    test('los días sueltos se enumeran', () {
      expect(
        sede.copyWith(diasOficina: const {1, 3, 5}).diasOficinaLegible,
        'Lunes, miércoles y viernes',
      );
    });

    test('dos días seguidos se enumeran en vez de decirse de corrido', () {
      // "De lunes a martes" es una forma rara de decir dos días.
      expect(
        sede.copyWith(diasOficina: const {1, 2}).diasOficinaLegible,
        'Lunes y martes',
      );
    });

    test('el orden en que se marcaron no cambia cómo se leen', () {
      expect(
        sede.copyWith(diasOficina: const {5, 1, 2}).diasOficinaLegible,
        'Lunes, martes y viernes',
      );
    });

    test('una semana que empieza el martes también se dice de corrido', () {
      expect(
        sede.copyWith(diasOficina: const {2, 3, 4}).diasOficinaLegible,
        'De martes a jueves',
      );
    });
  });
}

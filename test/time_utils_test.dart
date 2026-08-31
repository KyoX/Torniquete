import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/utils/time_utils.dart';

void main() {
  group('proximasOcurrenciasHabiles', () {
    // 21 de agosto de 2026 es viernes.
    final viernesTemprano = DateTime(2026, 8, 21, 7, 0);
    const ochoDeLaManana = 8 * 60;

    test('la primera cita es hoy si la hora todavía no ha llegado', () {
      final citas = TimeUtils.proximasOcurrenciasHabiles(
          viernesTemprano, ochoDeLaManana, 3);
      expect(citas.first, DateTime(2026, 8, 21, 8, 0));
    });

    test('salta el fin de semana', () {
      final citas = TimeUtils.proximasOcurrenciasHabiles(
          viernesTemprano, ochoDeLaManana, 3);
      expect(citas, [
        DateTime(2026, 8, 21, 8, 0), // viernes
        DateTime(2026, 8, 24, 8, 0), // lunes
        DateTime(2026, 8, 25, 8, 0), // martes
      ]);
    });

    test('si la hora de hoy ya pasó, empieza mañana', () {
      final viernesTarde = DateTime(2026, 8, 21, 9, 0);
      final citas = TimeUtils.proximasOcurrenciasHabiles(
          viernesTarde, ochoDeLaManana, 1);
      expect(citas.single, DateTime(2026, 8, 24, 8, 0));
    });

    test('omitirHoy descarta la cita de hoy aunque no haya llegado', () {
      final citas = TimeUtils.proximasOcurrenciasHabiles(
        viernesTemprano,
        ochoDeLaManana,
        1,
        omitirHoy: true,
      );
      expect(citas.single, DateTime(2026, 8, 24, 8, 0));
    });

    test('la hora exacta no se desplaza al avanzar los días', () {
      final citas = TimeUtils.proximasOcurrenciasHabiles(
          viernesTemprano, 7 * 60 + 50, 10);
      expect(citas, hasLength(10));
      for (final cita in citas) {
        expect(cita.hour, 7);
        expect(cita.minute, 50);
        expect(cita.weekday, lessThanOrEqualTo(DateTime.friday));
      }
    });

    test('pedir cero citas no devuelve ninguna', () {
      expect(
        TimeUtils.proximasOcurrenciasHabiles(viernesTemprano, ochoDeLaManana, 0),
        isEmpty,
      );
    });
  });

  group('proximasOcurrenciasHabiles con días de oficina', () {
    // 21 de agosto de 2026 es viernes; el 24 es lunes.
    final viernesTemprano = DateTime(2026, 8, 21, 7, 0);
    const ochoDeLaManana = 8 * 60;
    const martesJuevesViernes = {2, 4, 5};

    test('solo cita los días marcados', () {
      final citas = TimeUtils.proximasOcurrenciasHabiles(
        viernesTemprano,
        ochoDeLaManana,
        4,
        dias: martesJuevesViernes,
      );
      expect(citas, [
        DateTime(2026, 8, 21, 8, 0), // viernes
        DateTime(2026, 8, 25, 8, 0), // martes
        DateTime(2026, 8, 27, 8, 0), // jueves
        DateTime(2026, 8, 28, 8, 0), // viernes
      ]);
    });

    test('el lunes de teletrabajo no recibe ningún aviso', () {
      final lunes = DateTime(2026, 8, 24, 7, 0);
      final citas = TimeUtils.proximasOcurrenciasHabiles(
        lunes,
        ochoDeLaManana,
        3,
        dias: martesJuevesViernes,
      );
      expect(citas.map((c) => c.weekday), isNot(contains(DateTime.monday)));
      expect(citas.first, DateTime(2026, 8, 25, 8, 0));
    });

    test('sin ningún día marcado no se programa nada', () {
      expect(
        TimeUtils.proximasOcurrenciasHabiles(
          viernesTemprano,
          ochoDeLaManana,
          5,
          dias: const {},
        ),
        isEmpty,
      );
    });

    test('un solo día a la semana llena igual las diez citas', () {
      final citas = TimeUtils.proximasOcurrenciasHabiles(
        viernesTemprano,
        ochoDeLaManana,
        10,
        dias: const {3},
      );
      expect(citas, hasLength(10));
      for (final cita in citas) {
        expect(cita.weekday, DateTime.wednesday);
      }
    });

    test('un día de fin de semana sí se cita si está marcado', () {
      final citas = TimeUtils.proximasOcurrenciasHabiles(
        viernesTemprano,
        ochoDeLaManana,
        1,
        dias: const {6},
      );
      expect(citas.single, DateTime(2026, 8, 22, 8, 0)); // sábado
    });

    test('omitirHoy sigue valiendo dentro de los días marcados', () {
      final citas = TimeUtils.proximasOcurrenciasHabiles(
        viernesTemprano,
        ochoDeLaManana,
        1,
        omitirHoy: true,
        dias: martesJuevesViernes,
      );
      expect(citas.single, DateTime(2026, 8, 25, 8, 0)); // martes
    });
  });
}

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
}

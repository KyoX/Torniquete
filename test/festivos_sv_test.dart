import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/utils/festivos_sv.dart';

void main() {
  group('domingo de Pascua', () {
    // Fechas contrastadas contra el calendario litúrgico. De aquí cuelga toda
    // la Semana Santa, así que si esto se desvía un día se desvían tres
    // asuetos a la vez.
    const conocidas = {
      2024: '2024-03-31',
      2025: '2025-04-20',
      2026: '2026-04-05',
      2027: '2027-03-28',
      2028: '2028-04-16',
      2029: '2029-04-01',
      2030: '2030-04-21',
      2035: '2035-03-25',
      2038: '2038-04-25',
    };

    test('coincide con las fechas conocidas', () {
      conocidas.forEach((anio, esperada) {
        expect(
          FestivosSV.clave(FestivosSV.domingoDePascua(anio)),
          esperada,
          reason: 'Pascua de $anio',
        );
      });
    });
  });

  group('Semana Santa', () {
    test('jueves, viernes y sábado caen antes del domingo de Pascua', () {
      final santos = FestivosSV.delAnio(2026)
          .where((a) => a.movil)
          .map((a) => a.fecha)
          .toList();
      // Pascua 2026 cae el domingo 5 de abril.
      expect(santos, ['2026-04-02', '2026-04-03', '2026-04-04']);
    });

    test('se resuelve bien cuando la semana cruza de mes', () {
      // Pascua 2029 cae el 1 de abril: el Jueves Santo se va a marzo.
      final santos = FestivosSV.delAnio(2029)
          .where((a) => a.movil)
          .map((a) => a.fecha)
          .toList();
      expect(santos, ['2029-03-29', '2029-03-30', '2029-03-31']);
    });

    test('los días de Semana Santa caen en el día de la semana correcto', () {
      for (var anio = 2024; anio <= 2035; anio++) {
        final santos = FestivosSV.delAnio(anio).where((a) => a.movil).toList();
        expect(santos, hasLength(3), reason: 'año $anio');
        expect(DateTime.parse(santos[0].fecha).weekday, DateTime.thursday,
            reason: 'Jueves Santo de $anio');
        expect(DateTime.parse(santos[1].fecha).weekday, DateTime.friday,
            reason: 'Viernes Santo de $anio');
        expect(DateTime.parse(santos[2].fecha).weekday, DateTime.saturday,
            reason: 'Sábado Santo de $anio');
      }
    });
  });

  group('asuetos del año', () {
    test('el sector privado tiene los once días del Código de Trabajo', () {
      final fechas = FestivosSV.delAnio(2026).map((a) => a.fecha).toList();
      expect(fechas, hasLength(11));
      expect(
        fechas,
        containsAll([
          '2026-01-01', // Año Nuevo
          '2026-05-01', // Día del Trabajo
          '2026-05-10', // Día de la Madre
          '2026-06-17', // Día del Padre
          '2026-08-06', // Divino Salvador del Mundo
          '2026-09-15', // Independencia
          '2026-11-02', // Difuntos
          '2026-12-25', // Navidad
        ]),
      );
    });

    test('el sector público suma el 3 y el 5 de agosto', () {
      final publico = FestivosSV.delAnio(2026, sector: SectorLaboral.publico)
          .map((a) => a.fecha)
          .toList();
      expect(publico, hasLength(13));
      expect(publico, containsAll(['2026-08-03', '2026-08-05', '2026-08-06']));

      final privado = FestivosSV.delAnio(2026).map((a) => a.fecha).toSet();
      expect(privado.contains('2026-08-03'), isFalse);
      expect(privado.contains('2026-08-05'), isFalse);
    });

    test('vienen ordenados por fecha', () {
      final fechas = FestivosSV.delAnio(2027, sector: SectorLaboral.publico)
          .map((a) => a.fecha)
          .toList();
      final ordenadas = [...fechas]..sort();
      expect(fechas, ordenadas);
    });

    test('no se repite ninguna fecha', () {
      for (final sector in SectorLaboral.values) {
        for (var anio = 2024; anio <= 2035; anio++) {
          final fechas =
              FestivosSV.delAnio(anio, sector: sector).map((a) => a.fecha);
          expect(fechas.toSet(), hasLength(fechas.length),
              reason: '$sector en $anio');
        }
      }
    });
  });

  group('consulta por fecha', () {
    test('reconoce un asueto fijo y uno móvil', () {
      expect(FestivosSV.enFecha(DateTime(2026, 9, 15))?.nombre,
          'Día de la Independencia');
      expect(FestivosSV.enFecha(DateTime(2026, 4, 3))?.nombre, 'Viernes Santo');
    });

    test('un día corriente no devuelve nada', () {
      expect(FestivosSV.enFecha(DateTime(2026, 9, 16)), isNull);
    });

    test('la hora del día no afecta la búsqueda', () {
      // Las marcas llegan con hora; la fecha es lo único que importa.
      expect(
        FestivosSV.enFecha(DateTime(2026, 12, 25, 16, 42))?.nombre,
        'Navidad',
      );
    });

    test('enClave acepta la fecha tal como se guarda en la base', () {
      expect(FestivosSV.enClave('2026-05-10')?.nombre, 'Día de la Madre');
      expect(FestivosSV.enClave('2026-05-11'), isNull);
      expect(FestivosSV.enClave('no-es-fecha'), isNull);
      expect(FestivosSV.enClave(''), isNull);
    });

    test('el 3 de agosto solo es asueto para el sector público', () {
      final fecha = DateTime(2026, 8, 3);
      expect(FestivosSV.enFecha(fecha), isNull);
      expect(
        FestivosSV.enFecha(fecha, sector: SectorLaboral.publico)?.nombre,
        'Fiestas agostinas',
      );
    });
  });

  group('días hábiles', () {
    test('un asueto entre semana no es día hábil', () {
      // 15 de septiembre de 2026 cae martes.
      final independencia = DateTime(2026, 9, 15);
      expect(independencia.weekday, DateTime.tuesday);
      expect(FestivosSV.esDiaHabil(independencia), isFalse);
    });

    test('un miércoles corriente sí lo es', () {
      expect(FestivosSV.esDiaHabil(DateTime(2026, 9, 16)), isTrue);
    });

    test('el fin de semana nunca es día hábil', () {
      expect(FestivosSV.esDiaHabil(DateTime(2026, 9, 19)), isFalse);
      expect(FestivosSV.esDiaHabil(DateTime(2026, 9, 20)), isFalse);
    });
  });

  group('rango de fechas', () {
    test('devuelve solo los asuetos dentro del rango', () {
      final mayo =
          FestivosSV.entre(DateTime(2026, 5, 1), DateTime(2026, 5, 31));
      expect(mayo.map((a) => a.fecha), ['2026-05-01', '2026-05-10']);
    });

    test('cruza el cambio de año', () {
      final finDeAnio =
          FestivosSV.entre(DateTime(2026, 12, 20), DateTime(2027, 1, 5));
      expect(finDeAnio.map((a) => a.fecha), ['2026-12-25', '2027-01-01']);
    });

    test('un rango invertido no devuelve nada', () {
      expect(
        FestivosSV.entre(DateTime(2026, 5, 31), DateTime(2026, 5, 1)),
        isEmpty,
      );
    });

    test('los extremos del rango se incluyen', () {
      final exacto =
          FestivosSV.entre(DateTime(2026, 12, 25), DateTime(2026, 12, 25));
      expect(exacto.map((a) => a.fecha), ['2026-12-25']);
    });
  });

  group('sector laboral', () {
    test('una clave desconocida cae en privado', () {
      expect(SectorLaboral.desdeClave(null), SectorLaboral.privado);
      expect(SectorLaboral.desdeClave('otro'), SectorLaboral.privado);
      expect(SectorLaboral.desdeClave('publico'), SectorLaboral.publico);
    });
  });
}

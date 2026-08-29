import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/models/pausa.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/services/asuetos_service.dart';
import 'package:torniquete/services/reports_service.dart';
import 'package:torniquete/utils/festivos_sv.dart';

Registro reg(
  String fecha, {
  String? e1,
  String? s1,
  String? e2,
  String? sr,
  int meta = 510,
  TipoDia tipo = TipoDia.normal,
}) =>
    Registro(
      fecha: fecha,
      entrada1: e1,
      pausas: [if (s1 != null) Pausa(inicio: s1, fin: e2)],
      salidaReal: sr,
      metaMinutos: meta,
      tipoDia: tipo,
    );

void main() {
  group('revisión del historial', () {
    test('encuentra los días en blanco que cayeron en asueto', () {
      final candidatos = AsuetosService.candidatos(
        [
          reg('2026-09-15'), // Independencia, sin horas
          reg('2026-09-16'), // día corriente sin horas
          reg('2026-11-02'), // Difuntos, sin horas
        ],
        SectorLaboral.privado,
      );
      expect(
        candidatos.map((c) => c.registro.fecha),
        ['2026-11-02', '2026-09-15'],
      );
      expect(candidatos.last.asueto.nombre, 'Día de la Independencia');
    });

    test('no toca un día en el que sí se trabajó', () {
      // Trabajar en un asueto es tiempo extra, pero marcarlo cambiaría el
      // banco de horas: esa decisión se deja al usuario.
      final candidatos = AsuetosService.candidatos(
        [reg('2026-09-15', e1: '08:00', s1: '12:00', e2: '13:00', sr: '17:00')],
        SectorLaboral.privado,
      );
      expect(candidatos, isEmpty);
    });

    test('no vuelve a proponer un día ya marcado', () {
      final candidatos = AsuetosService.candidatos(
        [
          reg('2026-09-15', tipo: TipoDia.festivo),
          reg('2026-11-02', tipo: TipoDia.vacaciones),
        ],
        SectorLaboral.privado,
      );
      expect(candidatos, isEmpty);
    });

    test('el sector cambia qué días se proponen', () {
      final registros = [reg('2026-08-03'), reg('2026-08-06')];

      expect(
        AsuetosService.candidatos(registros, SectorLaboral.privado)
            .map((c) => c.registro.fecha),
        ['2026-08-06'],
      );
      expect(
        AsuetosService.candidatos(registros, SectorLaboral.publico)
            .map((c) => c.registro.fecha),
        ['2026-08-06', '2026-08-03'],
      );
    });

    test('un historial sin asuetos no propone nada', () {
      final candidatos = AsuetosService.candidatos(
        [reg('2026-09-16'), reg('2026-09-17')],
        SectorLaboral.privado,
      );
      expect(candidatos, isEmpty);
    });
  });

  group('plazo del banco de horas', () {
    // El 21 de agosto de 2026 es viernes.
    final viernes = DateTime.parse('2026-08-21');

    test('sin sector solo se saltan los fines de semana', () {
      expect(
        ReportsService.fechaTrasDiasHabiles(viernes, 5),
        DateTime(2026, 8, 28),
      );
    });

    test('con sector también se salta el asueto', () {
      // El 15 de septiembre de 2026 (Independencia) cae martes, así que el
      // plazo se corre un día respecto al cálculo que solo mira el fin de
      // semana.
      final antes = DateTime.parse('2026-09-11'); // viernes
      expect(
        ReportsService.fechaTrasDiasHabiles(antes, 3),
        DateTime(2026, 9, 16),
      );
      expect(
        ReportsService.fechaTrasDiasHabiles(
          antes,
          3,
          sector: SectorLaboral.privado,
        ),
        DateTime(2026, 9, 17),
      );
    });

    test('planCompensacion traslada el sector a la fecha límite', () {
      final plan = ReportsService.planCompensacion(
        saldoMinutos: -300,
        diasHabiles: 3,
        desde: DateTime.parse('2026-09-11'),
        sector: SectorLaboral.privado,
      );
      expect(plan.fechaLimite, DateTime(2026, 9, 17));
      expect(plan.minutosExtraPorDia, 100);
    });

    test('el asueto que cae en fin de semana no corre el plazo', () {
      // El 2 de noviembre de 2026 cae lunes; el 1 de enero de 2027, viernes.
      // Se comprueba que no se descuente dos veces un día ya descartado.
      final sabado = DateTime.parse('2026-10-31');
      expect(
        ReportsService.fechaTrasDiasHabiles(
          sabado,
          1,
          sector: SectorLaboral.privado,
        ),
        // El lunes 2 es asueto, así que el primer día laboral es el martes 3.
        DateTime(2026, 11, 3),
      );
    });
  });
}

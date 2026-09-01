import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/models/movimiento_banco.dart';
import 'package:torniquete/models/pausa.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/services/reports_service.dart';

Registro reg(
  String fecha, {
  String? e1,
  String? s1,
  String? e2,
  String? sr,
  int meta = 510,
  TipoDia tipo = TipoDia.normal,
}) {
  return Registro(
    fecha: fecha,
    entrada1: e1,
    pausas: [if (s1 != null) Pausa(inicio: s1, fin: e2)],
    salidaReal: sr,
    metaMinutos: meta,
    tipoDia: tipo,
  );
}

MovimientoBanco mov(String fecha, int minutos,
    {MotivoMovimiento motivo = MotivoMovimiento.canje}) {
  return MovimientoBanco(
    fecha: fecha,
    minutos: minutos,
    motivo: motivo,
    creadoEn: DateTime.parse('2026-08-21T10:00:00'),
  );
}

void main() {
  final registros = [
    // 8h 00m trabajadas, meta 8h 30m -> -30
    reg('2026-08-14', e1: '08:00', s1: '12:00', e2: '13:00', sr: '17:00'),
    // día sin marcas -> no debe restar
    reg('2026-08-17'),
    // 9h 00m trabajadas, meta 8h 30m -> +30
    reg('2026-08-18', e1: '08:00', s1: '12:00', e2: '13:00', sr: '18:00'),
    // otro día vacío
    reg('2026-08-19'),
  ];

  test('los días sin horas no restan en el balance', () {
    final balance = ReportsService.balanceHistorico(registros);
    expect(balance.map((b) => b.diferenciaMinutos).toList(), [-30, 0, 30, 0]);
    expect(balance.last.balanceAcumuladoMinutos, 0);
    expect(balance.where((b) => b.sinRegistro).length, 2);
  });

  test('los días sin horas no cuentan como incumplidos ni suman meta', () {
    final diario = ReportsService.dailyStats(registros);
    expect(diario.where((d) => d.sinRegistro).length, 2);
    expect(diario.where((d) => d.diferenciaMinutos < 0).length, 1);

    final mes = ReportsService.monthlyStats(registros).single;
    expect(mes.totalDias, 2);
    expect(mes.diasSinRegistro, 2);
    expect(mes.totalMeta, 510 * 2);
    expect(mes.totalTrabajado, 480 + 540);
  });

  group('minutosEnVivo', () {
    const nueve = 9 * 60;
    const once = 11 * 60;
    const dosPm = 14 * 60;

    test('la mañana cuenta en vivo desde la entrada', () {
      final hoy = reg('2026-08-21', e1: '08:00');
      expect(ReportsService.minutosEnVivo(hoy, nueve), 60);
      expect(ReportsService.minutosEnVivo(hoy, once), 180);
    });

    test('la mañana se congela al marcar la salida a almuerzo', () {
      final hoy = reg('2026-08-21', e1: '08:00', s1: '12:00');
      expect(ReportsService.minutosEnVivo(hoy, dosPm), 240);
    });

    test('el almuerzo no cuenta como trabajado', () {
      final hoy = reg('2026-08-21', e1: '08:00', s1: '12:00', e2: '13:00');
      // 4h de la mañana + 1h de tarde a las 14:00.
      expect(ReportsService.minutosEnVivo(hoy, dosPm), 300);
    });

    test('cada pausa descuenta lo que duró', () {
      final hoy = Registro(
        fecha: '2026-08-21',
        entrada1: '08:00',
        pausas: const [
          Pausa(inicio: '09:30', fin: '10:00'),
          Pausa(inicio: '12:00', fin: '12:45'),
        ],
        metaMinutos: 510,
      );
      // De 08:00 a 14:00 son seis horas menos 1h 15m de pausas.
      expect(ReportsService.minutosEnVivo(hoy, dosPm), 285);
    });

    test('la pausa en curso congela el reloj', () {
      final hoy = Registro(
        fecha: '2026-08-21',
        entrada1: '08:00',
        pausas: const [Pausa(inicio: '12:00')],
        metaMinutos: 510,
      );
      expect(ReportsService.minutosEnVivo(hoy, dosPm), 240);
      expect(ReportsService.minutosEnVivo(hoy, 15 * 60), 240);
      // Y sin salida real el día se cierra donde empezó la pausa.
      expect(ReportsService.minutosDesdeMarcas(hoy), 240);
    });

    test('con salida real el total ya no depende de la hora actual', () {
      final hoy =
          reg('2026-08-21', e1: '08:00', s1: '12:00', e2: '13:00', sr: '17:00');
      expect(ReportsService.minutosEnVivo(hoy, dosPm), 480);
      expect(ReportsService.minutosEnVivo(hoy, 23 * 60), 480);
    });

    test('un día sin marcas no acumula nada', () {
      expect(ReportsService.minutosEnVivo(reg('2026-08-21'), dosPm), 0);
    });
  });

  group('tipos de día', () {
    test('un festivo trabajado suma todo como tiempo extra', () {
      final festivo = reg('2026-08-17',
          e1: '08:00', s1: '12:00', e2: '13:00', sr: '16:00',
          tipo: TipoDia.festivo);
      // 7h trabajadas contra una meta de cero: las 7h son extra.
      expect(ReportsService.metaEfectiva(festivo), 0);
      expect(ReportsService.diferenciaMinutos(festivo), 420);
    });

    test('un día de vacaciones sin marcas no resta nada', () {
      final vacaciones = reg('2026-08-17', tipo: TipoDia.vacaciones);
      expect(ReportsService.diferenciaMinutos(vacaciones), 0);
      expect(ReportsService.metaEfectiva(vacaciones), 0);
    });

    test('una incapacidad no cuenta como día sin registrar', () {
      final mes = ReportsService.monthlyStats([
        reg('2026-08-14', e1: '08:00', s1: '12:00', e2: '13:00', sr: '17:00'),
        reg('2026-08-17', tipo: TipoDia.incapacidad),
        reg('2026-08-18'),
      ]).single;
      expect(mes.diasJustificados, 1);
      // Solo el 18, que es un día laboral en blanco.
      expect(mes.diasSinRegistro, 1);
      // La meta del mes solo la pone el día trabajado.
      expect(mes.totalMeta, 510);
    });

    test('un mes que solo tiene días justificados sigue apareciendo', () {
      final meses = ReportsService.monthlyStats([
        reg('2026-12-25', tipo: TipoDia.festivo),
      ]);
      expect(meses, hasLength(1));
      expect(meses.single.diasJustificados, 1);
      expect(meses.single.totalMeta, 0);
    });

    test('el permiso aparece marcado en el balance', () {
      final balance = ReportsService.balanceHistorico([
        reg('2026-08-17', tipo: TipoDia.permiso),
      ]).single;
      expect(balance.justificado, isTrue);
      // Un día justificado no es un día "sin registrar": no falta nada.
      expect(balance.sinRegistro, isFalse);
      expect(balance.diferenciaMinutos, 0);
    });
  });

  group('banco de horas', () {
    final dias = [
      // -30 minutos
      reg('2026-08-14', e1: '08:00', s1: '12:00', e2: '13:00', sr: '17:00'),
      // +30 minutos
      reg('2026-08-18', e1: '08:00', s1: '12:00', e2: '13:00', sr: '18:00'),
    ];

    test('el saldo suma los días y los movimientos anotados', () {
      final estado = ReportsService.estadoBanco(
        registros: dias,
        movimientos: [mov('2026-08-19', -120)],
        metaDiariaMinutos: 510,
      );
      expect(estado.minutosDeDias, 0);
      expect(estado.minutosDeMovimientos, -120);
      expect(estado.saldoMinutos, -120);
      expect(estado.aFavor, isFalse);
      expect(estado.deficitMinutos, 120);
    });

    test('el saldo a favor se traduce a días de compensatorio', () {
      final estado = ReportsService.estadoBanco(
        registros: dias,
        movimientos: [mov('2026-08-19', 510, motivo: MotivoMovimiento.ajuste)],
        metaDiariaMinutos: 510,
      );
      expect(estado.saldoMinutos, 510);
      expect(estado.diasEquivalentes, 1.0);
    });

    test('el déficit se reparte redondeando hacia arriba', () {
      // 100 minutos en 3 días son 33,3: si se redondeara hacia abajo el
      // banco quedaría en rojo al terminar el plazo.
      final plan = ReportsService.planCompensacion(
        saldoMinutos: -100,
        diasHabiles: 3,
        desde: DateTime.parse('2026-08-21'),
      );
      expect(plan.minutosExtraPorDia, 34);
      expect(plan.hayDeficit, isTrue);
      expect(plan.minutosDisponibles, 0);
    });

    test('sin déficit el plan solo reporta lo disponible', () {
      final plan = ReportsService.planCompensacion(
        saldoMinutos: 240,
        diasHabiles: 5,
        desde: DateTime.parse('2026-08-21'),
      );
      expect(plan.hayDeficit, isFalse);
      expect(plan.minutosExtraPorDia, 0);
      expect(plan.minutosDisponibles, 240);
    });

    test('el plazo salta los fines de semana', () {
      // El 21 de agosto de 2026 es viernes: el primer día laboral es el
      // lunes 24 y el quinto, el viernes 28.
      final viernes = DateTime.parse('2026-08-21');
      expect(ReportsService.fechaTrasDiasHabiles(viernes, 1),
          DateTime(2026, 8, 24));
      expect(ReportsService.fechaTrasDiasHabiles(viernes, 5),
          DateTime(2026, 8, 28));
      expect(ReportsService.fechaTrasDiasHabiles(viernes, 6),
          DateTime(2026, 8, 31));
    });
  });

  group('estadisticasPersonales', () {
    test('promedia hora de entrada y de salida', () {
      final registros = [
        reg('2026-08-17', e1: '08:00', sr: '16:00', meta: 480),
        reg('2026-08-18', e1: '08:30', sr: '17:00', meta: 480),
      ];
      final stats = ReportsService.estadisticasPersonales(
        registros,
        ahora: DateTime.parse('2026-08-18'),
      );
      expect(stats.minutosEntradaPromedio, 8 * 60 + 15);
      expect(stats.minutosSalidaPromedio, 16 * 60 + 30);
    });

    test('encuentra el día de la semana que más rinde', () {
      final registros = [
        reg('2026-08-17', e1: '08:00', sr: '17:00', meta: 480), // lunes, 9h
        reg('2026-08-24', e1: '08:00', sr: '17:00', meta: 480), // lunes, 9h
        reg('2026-08-18', e1: '08:00', sr: '13:00', meta: 480), // martes, 5h
      ];
      final stats = ReportsService.estadisticasPersonales(
        registros,
        ahora: DateTime.parse('2026-08-24'),
      );
      expect(stats.diaMasProductivo, DateTime.monday);
      expect(stats.minutosDiaMasProductivo, 9 * 60);
    });

    test('la racha cuenta días laborales consecutivos cumplidos', () {
      final registros = [
        reg('2026-08-17', e1: '08:00', sr: '16:00', meta: 480), // lunes, cumple
        reg('2026-08-18', e1: '08:00', sr: '16:00', meta: 480), // martes, cumple
        reg('2026-08-19', e1: '08:00', sr: '13:00', meta: 480), // miércoles, no
      ];
      final stats = ReportsService.estadisticasPersonales(
        registros,
        ahora: DateTime.parse('2026-08-19'),
      );
      expect(stats.rachaActual, 0);
      expect(stats.mejorRacha, 2);
    });

    test('un día festivo no rompe la racha', () {
      final registros = [
        reg('2026-08-17', e1: '08:00', sr: '16:00', meta: 480),
        reg('2026-08-18', meta: 0, tipo: TipoDia.festivo),
        reg('2026-08-19', e1: '08:00', sr: '16:00', meta: 480),
      ];
      final stats = ReportsService.estadisticasPersonales(
        registros,
        ahora: DateTime.parse('2026-08-19'),
      );
      expect(stats.rachaActual, 2);
    });

    test('el día de hoy en curso, sin salida, no rompe la racha', () {
      final registros = [
        reg('2026-08-17', e1: '08:00', sr: '16:00', meta: 480),
        reg('2026-08-18', e1: '08:00', meta: 480), // hoy, sin salida todavía
      ];
      final stats = ReportsService.estadisticasPersonales(
        registros,
        ahora: DateTime.parse('2026-08-18'),
      );
      expect(stats.rachaActual, 1);
    });

    test('sin días con horas no hay nada que calcular', () {
      final stats = ReportsService.estadisticasPersonales(const []);
      expect(stats.diasConHoras, 0);
      expect(stats.minutosEntradaPromedio, isNull);
      expect(stats.diaMasProductivo, isNull);
    });
  });
}

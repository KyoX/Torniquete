import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/services/reports_service.dart';

Registro reg(String fecha,
    {String? e1, String? s1, String? e2, String? sr, int meta = 510}) {
  return Registro(
    fecha: fecha,
    entrada1: e1,
    salida1: s1,
    entrada2: e2,
    salidaReal: sr,
    metaMinutos: meta,
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
}

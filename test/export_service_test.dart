import 'dart:convert';

import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:torniquete/models/movimiento_banco.dart';
import 'package:torniquete/models/pausa.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/services/export_service.dart';

Registro reg(
  String fecha, {
  String? e1,
  String? s1,
  String? e2,
  String? sr,
  int meta = 510,
  TipoDia tipo = TipoDia.normal,
  String? nota,
}) {
  return Registro(
    fecha: fecha,
    entrada1: e1,
    pausas: [if (s1 != null) Pausa(inicio: s1, fin: e2)],
    salidaReal: sr,
    metaMinutos: meta,
    tipoDia: tipo,
    nota: nota,
  );
}

/// Al releer el archivo, una hora entera vuelve como entero y una con
/// minutos como decimal: al comprobar solo importa el número.
num numeroDe(xls.Data? celda) => (celda?.value as dynamic).value as num;

String textoDe(xls.Data? celda) =>
    (celda?.value as xls.TextCellValue).value.toString();

void main() {
  setUpAll(() async {
    // El reporte escribe los meses y los días en español.
    await initializeDateFormatting('es');
  });

  final registros = [
    // 8h 00m contra una meta de 8h 30m -> -30
    reg('2026-07-31', e1: '08:00', s1: '12:00', e2: '13:00', sr: '17:00'),
    // 9h 00m -> +30
    reg('2026-08-03', e1: '08:00', s1: '12:00', e2: '13:00', sr: '18:00'),
    // 8h 30m -> justo en la meta
    reg('2026-08-04', e1: '08:00', s1: '12:00', e2: '13:00', sr: '17:30'),
    // día laboral en blanco: no resta
    reg('2026-08-05'),
    // festivo trabajado: 4h de tiempo extra
    reg('2026-08-06',
        e1: '08:00', s1: '12:00', e2: '12:00', sr: '12:00',
        tipo: TipoDia.festivo, nota: 'Asueto trabajado'),
  ];

  final movimientos = [
    MovimientoBanco(
      fecha: '2026-08-04',
      minutos: -60,
      motivo: MotivoMovimiento.canje,
      nota: 'Salida temprano',
      creadoEn: DateTime.parse('2026-08-04T18:00:00'),
    ),
    // Fuera del periodo de agosto: no debe contar.
    MovimientoBanco(
      fecha: '2026-07-15',
      minutos: 120,
      motivo: MotivoMovimiento.ajuste,
      creadoEn: DateTime.parse('2026-07-15T10:00:00'),
    ),
  ];

  ReporteComprobacion reporteDeAgosto() => ReporteComprobacion.construir(
        registros: registros,
        movimientos: movimientos,
        periodo: PeriodoReporte.mes(DateTime(2026, 8, 1)),
        metaDiariaMinutos: 510,
        nombre: 'Ana Pérez',
        generado: DateTime.parse('2026-08-22T09:30:00'),
      );

  test('el periodo recorta días y movimientos a sus fechas', () {
    final reporte = reporteDeAgosto();
    expect(reporte.registros.map((r) => r.fecha),
        ['2026-08-03', '2026-08-04', '2026-08-05', '2026-08-06']);
    expect(reporte.movimientos.map((m) => m.fecha), ['2026-08-04']);
    expect(reporte.periodo.etiqueta, 'Agosto 2026');
  });

  test('el resumen suma solo los días con horas y separa los justificados',
      () {
    final resumen = reporteDeAgosto().resumen;
    // 9h 00m + 8h 30m + 4h 00m del festivo.
    expect(resumen.totalTrabajado, 540 + 510 + 240);
    // El festivo no exige meta, el día en blanco tampoco suma.
    expect(resumen.totalMeta, 510 + 510);
    expect(resumen.diferenciaMinutos, 270);
    expect(resumen.diasConHoras, 3);
    expect(resumen.diasCumplidos, 3);
    expect(resumen.diasIncumplidos, 0);
    expect(resumen.diasSinRegistro, 1);
    expect(resumen.diasJustificados, 1);
    // Solo el canje de agosto entra.
    expect(resumen.minutosMovimientos, -60);
    expect(resumen.saldoMinutos, 210);
  });

  test('el saldo del banco que se reporta es el de todo el historial', () {
    final reporte = reporteDeAgosto();
    // Días: -30 +30 +0 +240; movimientos: -60 +120.
    expect(reporte.saldoHistoricoMinutos, 300);
  });

  test('el nombre del archivo dice el periodo y el formato', () {
    final reporte = reporteDeAgosto();
    expect(reporte.nombreArchivo(FormatoReporte.pdf),
        'torniquete-reporte-2026-08-20260822-0930.pdf');
    expect(
      ReporteComprobacion.construir(
        registros: registros,
        movimientos: movimientos,
        periodo: PeriodoReporte.rango(
            DateTime(2026, 8, 1), DateTime(2026, 8, 15)),
        metaDiariaMinutos: 510,
        generado: DateTime.parse('2026-08-22T09:30:00'),
      ).nombreArchivo(FormatoReporte.excel),
      'torniquete-reporte-2026-08-01_2026-08-15-20260822-0930.xlsx',
    );
  });

  test('el PDF se genera y trae los totales del periodo', () async {
    final bytes = await ExportService.construirPdf(reporteDeAgosto());
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('una nota con emoji no rompe la generación del PDF', () async {
    final reporte = ReporteComprobacion.construir(
      registros: [
        reg('2026-08-03',
            e1: '08:00', s1: '12:00', e2: '13:00', sr: '18:00',
            nota: 'Turno extra 🚀 — "guardia"'),
      ],
      movimientos: const [],
      periodo: PeriodoReporte.todo,
      metaDiariaMinutos: 510,
      nombre: 'Ana Pérez',
      generado: DateTime.parse('2026-08-22T09:30:00'),
    );
    final bytes = await ExportService.construirPdf(reporte);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('el Excel trae una hoja por reporte y las horas como número', () {
    final bytes = ExportService.construirXlsx(reporteDeAgosto());
    final libro = xls.Excel.decodeBytes(bytes);

    expect(
      libro.sheets.keys,
      containsAll(
          ['Resumen', 'Detalle diario', 'Semanal', 'Mensual', 'Banco de horas']),
    );
    expect(libro.sheets.containsKey('Sheet1'), isFalse);

    final diario = libro['Detalle diario'];
    // Encabezado + los cuatro días de agosto.
    expect(diario.maxRows, 5);
    final primerDia = diario.row(1);
    expect(textoDe(primerDia[0]), '2026-08-03');
    // Una hora de pausa, que es la que separa la presencia de lo trabajado.
    expect(textoDe(primerDia[7]), '1h 00m');
    // 9h 00m trabajadas.
    expect(numeroDe(primerDia[8]), 9);
    // 8h 30m exigidas.
    expect(numeroDe(primerDia[9]), 8.5);
    expect(numeroDe(primerDia[10]), 0.5);

    // El día festivo no exige meta y su nota viaja con él.
    final festivo = diario.row(4);
    expect(textoDe(festivo[2]), 'Festivo');
    expect(numeroDe(festivo[9]), 0);
    expect(textoDe(festivo[12]), 'Asueto trabajado');
  });

  test('el Excel es un archivo xlsx de verdad (zip)', () {
    final bytes = ExportService.construirXlsx(reporteDeAgosto());
    expect(utf8.decode(bytes.take(2).toList()), 'PK');
  });
}

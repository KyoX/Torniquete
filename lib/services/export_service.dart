import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/movimiento_banco.dart';
import '../models/registro.dart';
import '../utils/time_utils.dart';
import 'reports_service.dart';

/// En qué formato se entrega el reporte.
enum FormatoReporte {
  /// Documento listo para imprimir o adjuntar a un correo.
  pdf('PDF', 'pdf', 'application/pdf'),

  /// Hoja de cálculo con los números en celdas numéricas, para que quien
  /// revise pueda sumar y filtrar por su cuenta.
  excel('Excel', 'xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

  const FormatoReporte(this.etiqueta, this.extension, this.mimeType);

  final String etiqueta;
  final String extension;
  final String mimeType;
}

/// Tramo de fechas que cubre el reporte. Los extremos nulos dejan ese lado
/// abierto, así que un periodo sin extremos es todo el historial.
class PeriodoReporte {
  final DateTime? desde;
  final DateTime? hasta;

  /// Cómo se nombra el periodo en la portada y en el nombre del archivo.
  final String etiqueta;

  const PeriodoReporte({this.desde, this.hasta, required this.etiqueta});

  static const PeriodoReporte todo =
      PeriodoReporte(etiqueta: 'Todo el historial');

  factory PeriodoReporte.mes(DateTime mes) {
    final inicio = DateTime(mes.year, mes.month, 1);
    // Día 0 del mes siguiente es el último día de este mes.
    final fin = DateTime(mes.year, mes.month + 1, 0);
    final nombre = DateFormat('MMMM yyyy', 'es').format(inicio);
    return PeriodoReporte(
      desde: inicio,
      hasta: fin,
      etiqueta: nombre[0].toUpperCase() + nombre.substring(1),
    );
  }

  factory PeriodoReporte.rango(DateTime desde, DateTime hasta) {
    final inicio = DateTime(desde.year, desde.month, desde.day);
    final fin = DateTime(hasta.year, hasta.month, hasta.day);
    final formato = DateFormat('d MMM yyyy', 'es');
    return PeriodoReporte(
      desde: inicio,
      hasta: fin,
      etiqueta: '${formato.format(inicio)} al ${formato.format(fin)}',
    );
  }

  /// Los últimos [dias] días contando hoy, que es lo que suele pedirse
  /// cuando la quincena no coincide con el mes.
  factory PeriodoReporte.ultimosDias(int dias, {DateTime? hasta}) {
    final fin = hasta ?? DateTime.now();
    final inicio = DateTime(fin.year, fin.month, fin.day - (dias - 1));
    return PeriodoReporte.rango(inicio, fin);
  }

  /// Trozo del nombre del archivo: "2026-08", "2026-08-01_2026-08-15" o
  /// "historial".
  String get claveArchivo {
    if (desde == null && hasta == null) return 'historial';
    final inicio = desde == null ? '' : _clave(desde!);
    final fin = hasta == null ? '' : _clave(hasta!);
    // Un mes natural completo se nombra por el mes, que se lee mejor.
    if (desde != null &&
        hasta != null &&
        desde!.day == 1 &&
        hasta!.day == DateTime(hasta!.year, hasta!.month + 1, 0).day &&
        desde!.year == hasta!.year &&
        desde!.month == hasta!.month) {
      return inicio.substring(0, 7);
    }
    if (inicio.isEmpty) return 'hasta-$fin';
    if (fin.isEmpty) return 'desde-$inicio';
    return '${inicio}_$fin';
  }

  static String _clave(DateTime fecha) =>
      '${fecha.year.toString().padLeft(4, '0')}-'
      '${fecha.month.toString().padLeft(2, '0')}-'
      '${fecha.day.toString().padLeft(2, '0')}';
}

/// Todo lo que lleva el reporte de comprobación, ya recortado al periodo.
/// Es la entrada de los dos generadores (PDF y Excel), así que ambos
/// enseñan exactamente los mismos números.
class ReporteComprobacion {
  /// Nombre de quien marca, tal como se configuró en la app.
  final String? nombre;

  final PeriodoReporte periodo;
  final DateTime generado;

  /// Días del periodo, en orden ascendente.
  final List<Registro> registros;

  /// Movimientos del banco anotados dentro del periodo.
  final List<MovimientoBanco> movimientos;

  /// Meta de un día laboral típico, para traducir saldos a días.
  final int metaDiariaMinutos;

  /// Saldo del banco con **todo** el historial, no solo el periodo: es el
  /// que de verdad se debe o se tiene a favor hoy.
  final int saldoHistoricoMinutos;

  const ReporteComprobacion({
    required this.nombre,
    required this.periodo,
    required this.generado,
    required this.registros,
    required this.movimientos,
    required this.metaDiariaMinutos,
    required this.saldoHistoricoMinutos,
  });

  /// Recorta el historial completo al periodo pedido y calcula el saldo
  /// global de una vez.
  factory ReporteComprobacion.construir({
    required List<Registro> registros,
    required List<MovimientoBanco> movimientos,
    required PeriodoReporte periodo,
    required int metaDiariaMinutos,
    String? nombre,
    DateTime? generado,
  }) {
    final estado = ReportsService.estadoBanco(
      registros: registros,
      movimientos: movimientos,
      metaDiariaMinutos: metaDiariaMinutos,
    );
    return ReporteComprobacion(
      nombre: nombre,
      periodo: periodo,
      generado: generado ?? DateTime.now(),
      registros: ReportsService.registrosEnRango(
        registros,
        desde: periodo.desde,
        hasta: periodo.hasta,
      ),
      movimientos: ReportsService.movimientosEnRango(
        movimientos,
        desde: periodo.desde,
        hasta: periodo.hasta,
      ),
      metaDiariaMinutos: metaDiariaMinutos,
      saldoHistoricoMinutos: estado.saldoMinutos,
    );
  }

  /// Sin días ni movimientos no hay nada que comprobar.
  bool get vacio => registros.isEmpty && movimientos.isEmpty;

  ResumenPeriodo get resumen =>
      ReportsService.resumenPeriodo(registros, movimientos);

  /// Días del periodo del más antiguo al más reciente: un reporte se lee
  /// hacia adelante, al revés que la pantalla.
  List<DailyStat> get dias =>
      ReportsService.dailyStats(registros).reversed.toList();

  List<WeeklyStat> get semanas =>
      ReportsService.weeklyStats(registros).reversed.toList();

  List<MonthlyStat> get meses =>
      ReportsService.monthlyStats(registros).reversed.toList();

  String nombreArchivo(FormatoReporte formato) =>
      'torniquete-reporte-${periodo.claveArchivo}'
      '-${DateFormat('yyyyMMdd-HHmm').format(generado)}.${formato.extension}';
}

/// Genera el reporte de cumplimiento en PDF o en Excel y lo comparte.
///
/// El CSV de Ajustes (ver [BackupService]) sigue siendo el volcado crudo del
/// historial; esto es lo que se entrega cuando hay que **comprobar** ante
/// alguien que el horario se cumplió: trae totales, porcentaje de
/// cumplimiento y el detalle día por día ya interpretado.
class ExportService {
  ExportService._internal();
  static final ExportService instance = ExportService._internal();

  /// Genera el archivo y abre el menú de compartir. Devuelve su ruta.
  Future<String> exportar(
    ReporteComprobacion reporte,
    FormatoReporte formato,
  ) async {
    final bytes = await construir(reporte, formato);
    final archivo = await _escribir(reporte.nombreArchivo(formato), bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(archivo.path, mimeType: formato.mimeType)],
        text: 'Reporte de cumplimiento de horario '
            '(${reporte.periodo.etiqueta}) generado con Torniquete.',
        subject: 'Reporte de horario - ${reporte.periodo.etiqueta}',
      ),
    );
    return archivo.path;
  }

  /// Los bytes del reporte, sin tocar disco. Separado de [exportar] para
  /// poder probar el contenido.
  static Future<Uint8List> construir(
    ReporteComprobacion reporte,
    FormatoReporte formato,
  ) async {
    switch (formato) {
      case FormatoReporte.pdf:
        return construirPdf(reporte);
      case FormatoReporte.excel:
        return construirXlsx(reporte);
    }
  }

  Future<File> _escribir(String nombre, Uint8List bytes) async {
    // Igual que el respaldo: el temporal basta hasta que la app receptora
    // (correo, Drive, WhatsApp) se quede con su copia.
    final dir = await getTemporaryDirectory();
    final archivo = File(p.join(dir.path, nombre));
    await archivo.writeAsBytes(bytes, flush: true);
    return archivo;
  }

  // ------------------------------------------------------------------ PDF

  // Los mismos colores de la app (ver AppColors), para que el documento se
  // vea como lo que lo generó.
  static const PdfColor _tinta = PdfColor.fromInt(0xFF121A2B);
  static const PdfColor _tintaSuave = PdfColor.fromInt(0xFF5B6478);
  static const PdfColor _fondoCabecera = PdfColor.fromInt(0xFFE4EBF6);
  static const PdfColor _fondoCaja = PdfColor.fromInt(0xFFF4F6FA);
  static const PdfColor _borde = PdfColor.fromInt(0xFFD8DFEC);
  static const PdfColor _cumplido = PdfColor.fromInt(0xFF0D3C7E);
  static const PdfColor _pendiente = PdfColor.fromInt(0xFFB87400);

  static Future<Uint8List> construirPdf(ReporteComprobacion reporte) async {
    final doc = pw.Document(
      title: 'Reporte de cumplimiento de horario',
      author: reporte.nombre ?? 'Torniquete',
      creator: 'Torniquete',
    );
    final resumen = reporte.resumen;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 24),
        theme: pw.ThemeData.withFont().copyWith(
          defaultTextStyle: const pw.TextStyle(fontSize: 9, color: _tinta),
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _tintaSuave),
          ),
        ),
        build: (context) => [
          _encabezadoPdf(reporte),
          pw.SizedBox(height: 14),
          _resumenPdf(reporte, resumen),
          pw.SizedBox(height: 16),
          _tituloPdf('Detalle diario'),
          _tablaDiariaPdf(reporte),
          if (reporte.semanas.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _tituloPdf('Resumen semanal'),
            _tablaSemanalPdf(reporte),
          ],
          if (reporte.meses.length > 1) ...[
            pw.SizedBox(height: 16),
            _tituloPdf('Resumen mensual'),
            _tablaMensualPdf(reporte),
          ],
          if (reporte.movimientos.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _tituloPdf('Movimientos del banco de horas'),
            _tablaMovimientosPdf(reporte),
          ],
          pw.SizedBox(height: 18),
          _notaPdf(reporte),
        ],
      ),
    );

    return doc.save();
  }

  static pw.Widget _encabezadoPdf(ReporteComprobacion reporte) {
    final generado =
        DateFormat("d 'de' MMMM 'de' yyyy, HH:mm", 'es').format(reporte.generado);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _t('Reporte de cumplimiento de horario'),
          style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _t('Periodo: ${reporte.periodo.etiqueta}'),
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        if (reporte.nombre != null && reporte.nombre!.trim().isNotEmpty)
          pw.Text(_t('Persona: ${reporte.nombre!.trim()}')),
        pw.Text(
          _t('Generado el $generado'),
          style: const pw.TextStyle(fontSize: 9, color: _tintaSuave),
        ),
        pw.SizedBox(height: 8),
        pw.Divider(height: 1, color: _tintaSuave),
      ],
    );
  }

  static pw.Widget _resumenPdf(
    ReporteComprobacion reporte,
    ResumenPeriodo resumen,
  ) {
    final diferencia = resumen.diferenciaMinutos;
    return pw.Column(
      children: [
        pw.Row(
          children: [
            _casillaPdf('Horas trabajadas',
                TimeUtils.formatDurationMinutes(resumen.totalTrabajado)),
            _casillaPdf('Horas exigidas',
                TimeUtils.formatDurationMinutes(resumen.totalMeta)),
            _casillaPdf(
              diferencia >= 0 ? 'Tiempo a favor' : 'Tiempo pendiente',
              _conSigno(diferencia),
              color: diferencia >= 0 ? _cumplido : _pendiente,
            ),
            _casillaPdf(
              'Cumplimiento',
              '${resumen.porcentaje.toStringAsFixed(1)}%',
              color: resumen.metaCumplida ? _cumplido : _pendiente,
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          children: [
            _casillaPdf('Días con marcas', '${resumen.diasConHoras}'),
            _casillaPdf('Días que cumplieron la meta',
                '${resumen.diasCumplidos} de ${resumen.diasConHoras}'),
            _casillaPdf('Días justificados', '${resumen.diasJustificados}'),
            _casillaPdf('Días laborales sin marcar',
                '${resumen.diasSinRegistro}'),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: const pw.BoxDecoration(color: _fondoCaja),
          child: pw.Text(_t(_frasePeriodo(reporte, resumen))),
        ),
      ],
    );
  }

  /// Una línea que diga en palabras lo que dicen los números, para quien
  /// revise el reporte sin querer sumar nada.
  static String _frasePeriodo(
    ReporteComprobacion reporte,
    ResumenPeriodo resumen,
  ) {
    final buffer = StringBuffer();
    if (resumen.diasConHoras == 0) {
      buffer.write('El periodo no tiene días con horas registradas.');
    } else if (resumen.metaCumplida) {
      buffer.write('En el periodo se trabajaron '
          '${TimeUtils.formatDurationMinutes(resumen.totalTrabajado)} frente a '
          '${TimeUtils.formatDurationMinutes(resumen.totalMeta)} exigidas: '
          '${TimeUtils.formatDurationMinutes(resumen.diferenciaMinutos)} '
          'por encima de la meta.');
    } else {
      buffer.write('En el periodo se trabajaron '
          '${TimeUtils.formatDurationMinutes(resumen.totalTrabajado)} de las '
          '${TimeUtils.formatDurationMinutes(resumen.totalMeta)} exigidas: '
          'faltan ${TimeUtils.formatDurationMinutes(-resumen.diferenciaMinutos)}.');
    }
    if (resumen.minutosMovimientos != 0) {
      buffer.write(' Con los movimientos anotados en el banco de horas '
          '(${_conSigno(resumen.minutosMovimientos)}), el periodo cierra en '
          '${_conSigno(resumen.saldoMinutos)}.');
    }
    buffer.write(' Saldo acumulado del banco de horas a la fecha: '
        '${_conSigno(reporte.saldoHistoricoMinutos)}.');
    return buffer.toString();
  }

  static pw.Widget _casillaPdf(String titulo, String valor, {PdfColor? color}) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.only(right: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: pw.BoxDecoration(
          color: _fondoCaja,
          border: pw.Border.all(color: _borde, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              _t(titulo),
              style: const pw.TextStyle(fontSize: 7.5, color: _tintaSuave),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              _t(valor),
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: color ?? _tinta,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _tituloPdf(String texto) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Text(
          _t(texto),
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
      );

  static pw.Widget _tablaPdf({
    required List<String> encabezados,
    required List<List<String>> filas,
    Map<int, pw.Alignment>? alineaciones,
    Map<int, pw.TableColumnWidth>? anchos,
  }) {
    if (filas.isEmpty) {
      return pw.Text(
        _t('Sin datos en el periodo.'),
        style: const pw.TextStyle(color: _tintaSuave),
      );
    }
    return pw.TableHelper.fromTextArray(
      headers: encabezados.map(_t).toList(),
      data: filas.map((fila) => fila.map(_t).toList()).toList(),
      border: pw.TableBorder.all(color: _borde, width: 0.5),
      headerDecoration: const pw.BoxDecoration(color: _fondoCabecera),
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      oddRowDecoration: const pw.BoxDecoration(color: _fondoCaja),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: alineaciones,
      columnWidths: anchos,
    );
  }

  static pw.Widget _tablaDiariaPdf(ReporteComprobacion reporte) {
    final filas = reporte.dias.map((d) {
      final r = d.registro;
      return [
        _fechaCorta(r.fecha),
        TimeUtils.formatHHmm(r.entrada1),
        TimeUtils.formatHHmm(r.salida1),
        TimeUtils.formatHHmm(r.entrada2),
        TimeUtils.formatHHmm(r.salidaReal),
        TimeUtils.formatDurationMinutes(d.minutosTrabajados),
        TimeUtils.formatDurationMinutes(ReportsService.metaEfectiva(r)),
        _conSigno(d.diferenciaMinutos),
        _estadoDia(d),
      ];
    }).toList();

    return _tablaPdf(
      encabezados: const [
        'Fecha',
        'Entrada',
        'Almuerzo',
        'Regreso',
        'Salida',
        'Trabajado',
        'Meta',
        'Dif.',
        'Estado',
      ],
      filas: filas,
      anchos: const {
        0: pw.FlexColumnWidth(2.2),
        8: pw.FlexColumnWidth(2.2),
      },
      alineaciones: const {
        1: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.center,
        4: pw.Alignment.center,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
      },
    );
  }

  static pw.Widget _tablaSemanalPdf(ReporteComprobacion reporte) {
    final filas = reporte.semanas.map((s) {
      final diferencia = s.totalTrabajado - s.totalMeta;
      return [
        s.nombreSemana,
        TimeUtils.formatDurationMinutes(s.totalTrabajado),
        TimeUtils.formatDurationMinutes(s.totalMeta),
        _conSigno(diferencia),
        '${s.porcentaje.toStringAsFixed(1)}%',
        '${s.diasCumplidos} de ${s.totalDias}',
      ];
    }).toList();

    return _tablaPdf(
      encabezados: const [
        'Semana',
        'Trabajado',
        'Meta',
        'Dif.',
        'Cumplimiento',
        'Días en meta',
      ],
      filas: filas,
      anchos: const {0: pw.FlexColumnWidth(2.4)},
      alineaciones: const {
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.center,
      },
    );
  }

  static pw.Widget _tablaMensualPdf(ReporteComprobacion reporte) {
    final filas = reporte.meses.map((m) {
      final diferencia = m.totalTrabajado - m.totalMeta;
      return [
        m.nombreMes,
        TimeUtils.formatDurationMinutes(m.totalTrabajado),
        TimeUtils.formatDurationMinutes(m.totalMeta),
        _conSigno(diferencia),
        '${m.porcentaje.toStringAsFixed(1)}%',
        '${m.diasCumplidos} de ${m.totalDias}',
      ];
    }).toList();

    return _tablaPdf(
      encabezados: const [
        'Mes',
        'Trabajado',
        'Meta',
        'Dif.',
        'Cumplimiento',
        'Días en meta',
      ],
      filas: filas,
      anchos: const {0: pw.FlexColumnWidth(2.4)},
      alineaciones: const {
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.center,
      },
    );
  }

  static pw.Widget _tablaMovimientosPdf(ReporteComprobacion reporte) {
    final filas = reporte.movimientos
        .map((m) => [
              _fechaCorta(m.fecha),
              m.motivo.etiqueta,
              _conSigno(m.minutos),
              m.nota ?? '',
            ])
        .toList();

    return _tablaPdf(
      encabezados: const ['Fecha', 'Motivo', 'Horas', 'Nota'],
      filas: filas,
      anchos: const {3: pw.FlexColumnWidth(3)},
      alineaciones: const {2: pw.Alignment.centerRight},
    );
  }

  static pw.Widget _notaPdf(ReporteComprobacion reporte) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Divider(height: 1, color: _borde),
        pw.SizedBox(height: 6),
        pw.Text(
          _t('Las horas salen de las marcas registradas en la app Torniquete '
              'en este teléfono. Un día marcado como festivo, vacaciones, '
              'incapacidad o permiso no exige meta: no resta y todo lo '
              'trabajado en él cuenta como tiempo extra. Los días laborales '
              'sin ninguna marca no restan tiempo, solo se listan.'),
          style: const pw.TextStyle(fontSize: 7.5, color: _tintaSuave),
        ),
      ],
    );
  }

  static String _estadoDia(DailyStat d) {
    if (d.justificado) return d.tipoDia.etiqueta;
    if (d.sinRegistro) return 'Sin marcas';
    return d.cumplida ? 'Cumple meta' : 'Bajo la meta';
  }

  static String _conSigno(int minutos) =>
      (minutos > 0 ? '+' : '') + TimeUtils.formatDurationMinutes(minutos);

  /// "lun 04 ago" a partir de "2026-08-04".
  static String _fechaCorta(String fecha) {
    try {
      return DateFormat('EEE d MMM', 'es').format(DateTime.parse(fecha));
    } catch (_) {
      return fecha;
    }
  }

  /// Las fuentes estándar del PDF solo hablan Latin-1: un emoji o una comilla
  /// tipográfica en una nota reventaría la generación entera, así que se
  /// traducen o se descartan antes de dibujar.
  static String _t(String valor) {
    const equivalencias = {
      '—': '-',
      '–': '-',
      '‘': "'",
      '’': "'",
      '“': '"',
      '”': '"',
      '…': '...',
      '•': '-',
      '→': '->',
      '≥': '>=',
      '≤': '<=',
      '✓': 'OK',
      ' ': ' ',
    };
    final salida = StringBuffer();
    for (final rune in valor.runes) {
      final caracter = String.fromCharCode(rune);
      final equivalente = equivalencias[caracter];
      if (equivalente != null) {
        salida.write(equivalente);
      } else if (rune <= 0xFF) {
        salida.write(caracter);
      }
      // Cualquier otra cosa (emojis, alfabetos que la fuente no tiene) se
      // omite: vale más una nota incompleta que un reporte que no se genera.
    }
    return salida.toString();
  }

  // ---------------------------------------------------------------- Excel

  static Uint8List construirXlsx(ReporteComprobacion reporte) {
    final libro = xls.Excel.createExcel();
    final resumen = reporte.resumen;

    _hojaResumen(libro, reporte, resumen);
    _hojaDiaria(libro, reporte);
    _hojaSemanal(libro, reporte);
    _hojaMensual(libro, reporte);
    _hojaBanco(libro, reporte, resumen);

    // La hoja vacía que crea el paquete solo estorba; se borra al final,
    // cuando ya hay otras hojas que puedan quedarse.
    if (libro.sheets.containsKey('Sheet1')) libro.delete('Sheet1');
    libro.setDefaultSheet('Resumen');

    final bytes = libro.save();
    if (bytes == null) {
      throw StateError('No se pudo generar el archivo de Excel.');
    }
    return Uint8List.fromList(bytes);
  }

  /// Azul y azul claro de la marca (ver AppColors).
  static final xls.ExcelColor _azulExcel =
      xls.ExcelColor.fromHexString('FF0D3C7E');
  static final xls.ExcelColor _azulClaroExcel =
      xls.ExcelColor.fromHexString('FFE4EBF6');

  static xls.CellStyle get _estiloTitulo => xls.CellStyle(
        bold: true,
        fontSize: 14,
        fontColorHex: _azulExcel,
      );

  static xls.CellStyle get _estiloEncabezado => xls.CellStyle(
        bold: true,
        backgroundColorHex: _azulClaroExcel,
        fontColorHex: _azulExcel,
      );

  static xls.CellStyle get _estiloEtiqueta => xls.CellStyle(bold: true);

  static void _titulo(xls.Sheet hoja, String texto) {
    hoja.appendRow([xls.TextCellValue(texto)]);
    _estilar(hoja, hoja.maxRows - 1, 1, _estiloTitulo);
  }

  static void _encabezados(xls.Sheet hoja, List<String> columnas) {
    hoja.appendRow(columnas.map(xls.TextCellValue.new).toList());
    _estilar(hoja, hoja.maxRows - 1, columnas.length, _estiloEncabezado);
  }

  static void _estilar(
    xls.Sheet hoja,
    int fila,
    int columnas,
    xls.CellStyle estilo,
  ) {
    for (var c = 0; c < columnas; c++) {
      hoja
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: fila))
          .cellStyle = estilo;
    }
  }

  /// Fila "etiqueta: valor" de la hoja de resumen.
  static void _dato(xls.Sheet hoja, String etiqueta, xls.CellValue valor) {
    hoja.appendRow([xls.TextCellValue(etiqueta), valor]);
    _estilar(hoja, hoja.maxRows - 1, 1, _estiloEtiqueta);
  }

  /// Fila en blanco para separar bloques. Lleva una celda vacía a propósito:
  /// `appendRow([])` no hace nada.
  static void _vacia(xls.Sheet hoja) =>
      hoja.appendRow([xls.TextCellValue('')]);

  /// Las horas van como número decimal para que quien reciba el archivo
  /// pueda sumarlas; el texto "8h 30m" se deja en su propia columna.
  static xls.DoubleCellValue _horas(int minutos) =>
      xls.DoubleCellValue(double.parse((minutos / 60).toStringAsFixed(2)));

  static void _hojaResumen(
    xls.Excel libro,
    ReporteComprobacion reporte,
    ResumenPeriodo resumen,
  ) {
    final hoja = libro['Resumen'];
    hoja.setColumnWidth(0, 34);
    hoja.setColumnWidth(1, 22);

    _titulo(hoja, 'Reporte de cumplimiento de horario');
    _vacia(hoja);
    _dato(hoja, 'Periodo', xls.TextCellValue(reporte.periodo.etiqueta));
    if (reporte.nombre != null && reporte.nombre!.trim().isNotEmpty) {
      _dato(hoja, 'Persona', xls.TextCellValue(reporte.nombre!.trim()));
    }
    _dato(
      hoja,
      'Generado',
      xls.TextCellValue(
        DateFormat('yyyy-MM-dd HH:mm').format(reporte.generado),
      ),
    );
    _vacia(hoja);

    _encabezados(hoja, ['Concepto', 'Horas', 'Detalle']);
    hoja.appendRow([
      xls.TextCellValue('Horas trabajadas'),
      _horas(resumen.totalTrabajado),
      xls.TextCellValue(TimeUtils.formatDurationMinutes(resumen.totalTrabajado)),
    ]);
    hoja.appendRow([
      xls.TextCellValue('Horas exigidas'),
      _horas(resumen.totalMeta),
      xls.TextCellValue(TimeUtils.formatDurationMinutes(resumen.totalMeta)),
    ]);
    hoja.appendRow([
      xls.TextCellValue('Diferencia'),
      _horas(resumen.diferenciaMinutos),
      xls.TextCellValue(_conSigno(resumen.diferenciaMinutos)),
    ]);
    hoja.appendRow([
      xls.TextCellValue('Movimientos del banco en el periodo'),
      _horas(resumen.minutosMovimientos),
      xls.TextCellValue(_conSigno(resumen.minutosMovimientos)),
    ]);
    hoja.appendRow([
      xls.TextCellValue('Saldo del periodo'),
      _horas(resumen.saldoMinutos),
      xls.TextCellValue(_conSigno(resumen.saldoMinutos)),
    ]);
    hoja.appendRow([
      xls.TextCellValue('Saldo acumulado del banco de horas'),
      _horas(reporte.saldoHistoricoMinutos),
      xls.TextCellValue(_conSigno(reporte.saldoHistoricoMinutos)),
    ]);
    _vacia(hoja);

    _encabezados(hoja, ['Días', 'Cantidad']);
    hoja.appendRow([
      xls.TextCellValue('Días con marcas'),
      xls.IntCellValue(resumen.diasConHoras),
    ]);
    hoja.appendRow([
      xls.TextCellValue('Días que cumplieron la meta'),
      xls.IntCellValue(resumen.diasCumplidos),
    ]);
    hoja.appendRow([
      xls.TextCellValue('Días bajo la meta'),
      xls.IntCellValue(resumen.diasIncumplidos),
    ]);
    hoja.appendRow([
      xls.TextCellValue('Días justificados'),
      xls.IntCellValue(resumen.diasJustificados),
    ]);
    hoja.appendRow([
      xls.TextCellValue('Días laborales sin marcar'),
      xls.IntCellValue(resumen.diasSinRegistro),
    ]);
    _vacia(hoja);
    _dato(
      hoja,
      'Cumplimiento',
      xls.TextCellValue('${resumen.porcentaje.toStringAsFixed(1)}%'),
    );
    _vacia(hoja);
    hoja.appendRow([
      xls.TextCellValue(
        'Un día festivo, de vacaciones, de incapacidad o de permiso no exige '
        'meta: no resta y lo trabajado en él es tiempo extra. Los días '
        'laborales sin marcas tampoco restan.',
      ),
    ]);
  }

  static void _hojaDiaria(xls.Excel libro, ReporteComprobacion reporte) {
    final hoja = libro['Detalle diario'];
    hoja.setColumnWidth(0, 12);
    hoja.setColumnWidth(1, 12);
    hoja.setColumnWidth(2, 12);
    hoja.setColumnWidth(10, 16);
    hoja.setColumnWidth(11, 30);

    _encabezados(hoja, [
      'Fecha',
      'Día',
      'Tipo de día',
      'Entrada',
      'Salida almuerzo',
      'Regreso',
      'Salida',
      'Horas trabajadas',
      'Horas exigidas',
      'Diferencia',
      'Estado',
      'Nota',
    ]);

    for (final d in reporte.dias) {
      final r = d.registro;
      hoja.appendRow([
        xls.TextCellValue(r.fecha),
        xls.TextCellValue(_nombreDia(r.fecha)),
        xls.TextCellValue(r.tipoDia.etiqueta),
        xls.TextCellValue(TimeUtils.formatHHmm(r.entrada1)),
        xls.TextCellValue(TimeUtils.formatHHmm(r.salida1)),
        xls.TextCellValue(TimeUtils.formatHHmm(r.entrada2)),
        xls.TextCellValue(TimeUtils.formatHHmm(r.salidaReal)),
        _horas(d.minutosTrabajados),
        _horas(ReportsService.metaEfectiva(r)),
        _horas(d.diferenciaMinutos),
        xls.TextCellValue(_estadoDia(d)),
        xls.TextCellValue(r.nota ?? ''),
      ]);
    }
  }

  static void _hojaSemanal(xls.Excel libro, ReporteComprobacion reporte) {
    final hoja = libro['Semanal'];
    hoja.setColumnWidth(0, 26);
    _encabezados(hoja, [
      'Semana',
      'Horas trabajadas',
      'Horas exigidas',
      'Diferencia',
      'Cumplimiento %',
      'Días con marcas',
      'Días en meta',
      'Días justificados',
      'Días sin marcar',
    ]);
    for (final s in reporte.semanas) {
      hoja.appendRow([
        xls.TextCellValue(s.nombreSemana),
        _horas(s.totalTrabajado),
        _horas(s.totalMeta),
        _horas(s.totalTrabajado - s.totalMeta),
        xls.DoubleCellValue(
            double.parse(s.porcentaje.toStringAsFixed(1))),
        xls.IntCellValue(s.totalDias),
        xls.IntCellValue(s.diasCumplidos),
        xls.IntCellValue(s.diasJustificados),
        xls.IntCellValue(s.diasSinRegistro),
      ]);
    }
  }

  static void _hojaMensual(xls.Excel libro, ReporteComprobacion reporte) {
    final hoja = libro['Mensual'];
    hoja.setColumnWidth(0, 20);
    _encabezados(hoja, [
      'Mes',
      'Horas trabajadas',
      'Horas exigidas',
      'Diferencia',
      'Cumplimiento %',
      'Días con marcas',
      'Días en meta',
      'Días justificados',
      'Días sin marcar',
    ]);
    for (final m in reporte.meses) {
      hoja.appendRow([
        xls.TextCellValue(m.nombreMes),
        _horas(m.totalTrabajado),
        _horas(m.totalMeta),
        _horas(m.totalTrabajado - m.totalMeta),
        xls.DoubleCellValue(
            double.parse(m.porcentaje.toStringAsFixed(1))),
        xls.IntCellValue(m.totalDias),
        xls.IntCellValue(m.diasCumplidos),
        xls.IntCellValue(m.diasJustificados),
        xls.IntCellValue(m.diasSinRegistro),
      ]);
    }
  }

  static void _hojaBanco(
    xls.Excel libro,
    ReporteComprobacion reporte,
    ResumenPeriodo resumen,
  ) {
    final hoja = libro['Banco de horas'];
    hoja.setColumnWidth(0, 14);
    hoja.setColumnWidth(1, 20);
    hoja.setColumnWidth(3, 30);

    _encabezados(hoja, ['Fecha', 'Motivo', 'Horas', 'Nota']);
    for (final m in reporte.movimientos) {
      hoja.appendRow([
        xls.TextCellValue(m.fecha),
        xls.TextCellValue(m.motivo.etiqueta),
        _horas(m.minutos),
        xls.TextCellValue(m.nota ?? ''),
      ]);
    }
    _vacia(hoja);
    _dato(hoja, 'Movimientos del periodo',
        _horas(resumen.minutosMovimientos));
    _dato(hoja, 'Aportado por los días del periodo',
        _horas(resumen.diferenciaMinutos));
    _dato(hoja, 'Saldo del periodo', _horas(resumen.saldoMinutos));
    _dato(hoja, 'Saldo acumulado a la fecha',
        _horas(reporte.saldoHistoricoMinutos));
    if (reporte.metaDiariaMinutos > 0) {
      _dato(
        hoja,
        'Equivale a (días de trabajo)',
        xls.DoubleCellValue(double.parse(
          (reporte.saldoHistoricoMinutos / reporte.metaDiariaMinutos)
              .toStringAsFixed(2),
        )),
      );
    }
  }

  static String _nombreDia(String fecha) {
    try {
      return DateFormat('EEEE', 'es').format(DateTime.parse(fecha));
    } catch (_) {
      return '';
    }
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/models/ubicacion_marca.dart';
import 'package:torniquete/services/backup_service.dart';

void main() {
  setUpAll(() async {
    // El CSV incluye el nombre del día en español.
    await initializeDateFormatting('es');
  });

  List<String> filasDe(String csv) => csv.split('\r\n');

  test('el encabezado y las filas tienen las mismas columnas', () {
    final csv = BackupService.construirCsv([
      Registro(
        fecha: '2026-08-21',
        entrada1: '08:00',
        salida1: '12:00',
        entrada2: '13:00',
        salidaReal: '17:00',
        metaMinutos: 510,
      ),
    ], const {});

    final filas = filasDe(csv);
    expect(filas, hasLength(2));
    expect(filas[0].split(';').length, filas[1].split(';').length);
    expect(filas[0], startsWith('fecha;dia_semana;tipo_dia'));
  });

  test('las horas van con coma decimal, como espera Excel en español', () {
    final csv = BackupService.construirCsv([
      Registro(
        fecha: '2026-08-21',
        entrada1: '08:00',
        salida1: '12:00',
        entrada2: '13:00',
        salidaReal: '17:30',
        metaMinutos: 510,
      ),
    ], const {});
    // 8h 30m trabajadas = 8,50 horas.
    expect(filasDe(csv)[1], contains(';8,50;510;'));
  });

  test('una nota con punto y coma no rompe las columnas', () {
    final csv = BackupService.construirCsv([
      Registro(
        fecha: '2026-08-21',
        metaMinutos: 510,
        tipoDia: TipoDia.permiso,
        nota: 'Cita médica; volví tarde y dije "listo"',
      ),
    ], const {});

    final fila = filasDe(csv)[1];
    // La nota queda entrecomillada y con las comillas internas duplicadas,
    // así que el número de columnas no cambia.
    expect(fila, contains('"Cita médica; volví tarde y dije ""listo"""'));
    expect(fila.split(';').length, greaterThan(1));
    expect(fila, contains('Permiso'));
  });

  test('un día justificado exporta meta exigida cero', () {
    final csv = BackupService.construirCsv([
      Registro(
        fecha: '2026-12-25',
        metaMinutos: 510,
        tipoDia: TipoDia.festivo,
      ),
    ], const {});
    final columnas = filasDe(csv)[1].split(';');
    final encabezado = filasDe(csv)[0].split(';');
    expect(columnas[encabezado.indexOf('meta_minutos')], '510');
    expect(columnas[encabezado.indexOf('meta_exigida_minutos')], '0');
  });

  test('las filas salen de la más antigua a la más reciente', () {
    final csv = BackupService.construirCsv([
      Registro(fecha: '2026-08-21', metaMinutos: 510),
      Registro(fecha: '2026-08-14', metaMinutos: 510),
    ], const {});
    final filas = filasDe(csv);
    expect(filas[1], startsWith('2026-08-14'));
    expect(filas[2], startsWith('2026-08-21'));
  });

  test('la ubicación de la entrada se adjunta al día', () {
    final csv = BackupService.construirCsv(
      [Registro(fecha: '2026-08-21', entrada1: '08:00', metaMinutos: 510)],
      {
        '2026-08-21|entrada1': UbicacionMarca(
          fecha: '2026-08-21',
          tipo: 'entrada1',
          hora: '08:00',
          latitud: 4.609710,
          longitud: -74.081750,
          capturadoEn: DateTime.parse('2026-08-21T08:00:00'),
        ),
      },
    );
    expect(filasDe(csv)[1], contains('4.609710, -74.081750'));
  });
}

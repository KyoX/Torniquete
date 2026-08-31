import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/models/pausa.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/services/jornadas_abiertas_service.dart';
import 'package:torniquete/services/reports_service.dart';

/// Los días que se quedaron con la entrada marcada y sin salida.
///
/// Es el agujero que más caro sale: sin salida real el día cuenta lo último
/// que se alcanzó a guardar, así que las horas trabajadas después de la
/// última marca desaparecen del banco sin que nada lo diga.
void main() {
  const hoy = '2026-08-31'; // lunes

  Registro dia(
    String fecha, {
    String? entrada,
    String? salida,
    List<Pausa> pausas = const [],
    int meta = 510, // 8h 30m
    int descuento = 0,
    int cumplidos = 0,
    TipoDia tipo = TipoDia.normal,
  }) =>
      Registro(
        fecha: fecha,
        entrada1: entrada,
        salidaReal: salida,
        pausas: pausas,
        metaMinutos: meta,
        minutosCumplidos: cumplidos,
        descuentoAlmuerzoMinutos: descuento,
        tipoDia: tipo,
      );

  group('qué días se consideran abiertos', () {
    test('el día de hoy no cuenta: todavía se está trabajando', () {
      final abiertas = JornadasAbiertasService.detectar(
        [dia(hoy, entrada: '08:00')],
        hoy: hoy,
      );
      expect(abiertas, isEmpty);
    });

    test('un día futuro tampoco', () {
      final abiertas = JornadasAbiertasService.detectar(
        [dia('2026-09-01', entrada: '08:00')],
        hoy: hoy,
      );
      expect(abiertas, isEmpty);
    });

    test('un día sin entrada es un día en blanco, no una jornada a medias',
        () {
      final abiertas = JornadasAbiertasService.detectar(
        [dia('2026-08-28')],
        hoy: hoy,
      );
      expect(abiertas, isEmpty);
    });

    test('un día ya cerrado no se vuelve a preguntar', () {
      final abiertas = JornadasAbiertasService.detectar(
        [dia('2026-08-28', entrada: '08:00', salida: '17:30')],
        hoy: hoy,
      );
      expect(abiertas, isEmpty);
    });

    test('los abiertos salen del más reciente al más antiguo', () {
      final abiertas = JornadasAbiertasService.detectar(
        [
          dia('2026-08-25', entrada: '08:00'),
          dia('2026-08-28', entrada: '08:00'),
          dia('2026-08-26', entrada: '08:00', salida: '17:00'),
        ],
        hoy: hoy,
      );
      expect(abiertas.map((j) => j.fecha), ['2026-08-28', '2026-08-25']);
    });
  });

  group('qué hora se propone', () {
    JornadaAbierta unica(Registro registro) =>
        JornadasAbiertasService.detectar([registro], hoy: hoy).single;

    test('sin pausas, la hora a la que tocaba salir', () {
      final jornada = unica(dia('2026-08-28', entrada: '08:00'));
      expect(jornada.horaSugerida, '16:30');
      expect(jornada.desdePausa, isFalse);
    });

    test('cada pausa empuja la propuesta lo que duró', () {
      final jornada = unica(dia(
        '2026-08-28',
        entrada: '08:00',
        pausas: [Pausa(inicio: '12:00', fin: '13:00')],
      ));
      expect(jornada.horaSugerida, '17:30');
    });

    test('el almuerzo que la empresa descuenta también', () {
      // Media hora que se descuenta salga o no a comer, y ese día no se salió.
      final jornada = unica(dia('2026-08-28', entrada: '08:00', descuento: 30));
      expect(jornada.horaSugerida, '17:00');
    });

    test('con una pausa sin cerrar se propone el inicio de la pausa', () {
      // Quien se fue y no volvió dejó de contar ahí: es hasta ese punto donde
      // se sabe que estuvo trabajando.
      final jornada = unica(dia(
        '2026-08-28',
        entrada: '08:00',
        pausas: [Pausa(inicio: '12:15')],
      ));
      expect(jornada.horaSugerida, '12:15');
      expect(jornada.desdePausa, isTrue);
    });

    test('un festivo trabajado propone una jornada, no la hora de entrada',
        () {
      // El día no exige meta, pero si tiene entrada es que se trabajó, y esas
      // horas son tiempo extra que se pierde igual.
      final jornada = unica(
        dia('2026-08-28', entrada: '08:00', tipo: TipoDia.festivo),
      );
      expect(jornada.horaSugerida, '16:30');
    });

    test('la propuesta nunca se pasa de la medianoche', () {
      final jornada = unica(dia('2026-08-28', entrada: '23:00'));
      expect(jornada.minutoSugerido, JornadasAbiertasService.finDelDia);
      expect(jornada.horaSugerida, '23:59');
    });
  });

  group('cuánto se recupera', () {
    test('un día que se quedó en la última marca devuelve el resto', () {
      // Se marcó la vuelta del almuerzo, se guardaron esos minutos y ahí se
      // quedó el día: la tarde entera falta del banco.
      final registro = dia(
        '2026-08-28',
        entrada: '08:00',
        pausas: [Pausa(inicio: '12:00', fin: '13:00')],
        cumplidos: 240,
      );
      final jornada =
          JornadasAbiertasService.detectar([registro], hoy: hoy).single;

      expect(ReportsService.minutosTrabajados(registro), 240);
      expect(jornada.minutosRecuperados, 510 - 240);
    });

    test('cerrar el día deja exactamente la meta cuando se salió a la hora',
        () {
      final registro = dia('2026-08-28', entrada: '08:00');
      final jornada =
          JornadasAbiertasService.detectar([registro], hoy: hoy).single;
      final cerrado = registro.copyWith(salidaReal: jornada.horaSugerida);

      expect(ReportsService.minutosTrabajados(cerrado), 510);
    });
  });
}

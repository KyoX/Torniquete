import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/models/pausa.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/services/pausas_service.dart';
import 'package:torniquete/services/reports_service.dart';

/// Las pausas del día y la franja del almuerzo.
///
/// Lo que se prueba aquí es sobre todo la distinción que da sentido a la
/// función: una salida a media mañana es tiempo fuera, pero no es el almuerzo
/// que la empresa descuenta salga uno a comer o no.
void main() {
  Registro dia({
    String? entrada = '08:00',
    String? salida,
    List<Pausa> pausas = const [],
    int descuento = 0,
    int cumplidos = 0,
  }) =>
      Registro(
        fecha: '2026-08-28',
        entrada1: entrada,
        salidaReal: salida,
        pausas: pausas,
        metaMinutos: 510,
        minutosCumplidos: cumplidos,
        descuentoAlmuerzoMinutos: descuento,
      );

  group('formato guardado', () {
    test('una lista de pausas va y vuelve igual', () {
      const pausas = [
        Pausa(inicio: '09:30', fin: '10:00'),
        Pausa(inicio: '12:00', fin: '12:20'),
      ];
      expect(Pausa.parsear(Pausa.serializarLista(pausas)), pausas);
    });

    test('una pausa abierta se guarda sin fin', () {
      const abierta = [Pausa(inicio: '12:00')];
      expect(Pausa.serializarLista(abierta), '12:00-');
      expect(Pausa.parsear('12:00-'), abierta);
    });

    test('sin pausas no se guarda nada', () {
      expect(Pausa.serializarLista(const []), '');
      expect(Pausa.parsear(''), isEmpty);
      expect(Pausa.parsear(null), isEmpty);
    });

    test('lo que no se entiende se descarta sin perder el resto', () {
      // Un día con el texto a medio escribir no puede tumbar la carga del
      // historial entero.
      expect(
        Pausa.parsear('basura;12:00-12:30;;25:xx-'),
        [const Pausa(inicio: '12:00', fin: '12:30')],
      );
    });

    test('se guardan en orden aunque se escriban al revés', () {
      expect(
        Pausa.parsear('15:00-15:20;09:30-10:00').first.inicio,
        '09:30',
      );
    });
  });

  group('minutos fuera', () {
    test('se suman todas las pausas', () {
      expect(
        PausasService.minutosPausados(const [
          Pausa(inicio: '09:30', fin: '10:00'),
          Pausa(inicio: '12:00', fin: '12:20'),
        ]),
        50,
      );
    });

    test('la pausa en curso crece contra la hora que se le pase', () {
      const enCurso = [Pausa(inicio: '12:00')];
      expect(PausasService.minutosPausados(enCurso, hasta: 12 * 60 + 15), 15);
      // Y sin esa hora todavía no ha durado nada: no hay contra qué medirla.
      expect(PausasService.minutosPausados(enCurso), 0);
    });

    test('una pausa que termina antes de empezar no regala tiempo', () {
      expect(
        PausasService.minutosPausados(
          const [Pausa(inicio: '13:00', fin: '12:00')],
        ),
        0,
      );
    });
  });

  group('franja del almuerzo', () {
    test('una pausa a media mañana no es almuerzo', () {
      const mandado = [Pausa(inicio: '09:30', fin: '10:00')];
      expect(PausasService.minutosDeAlmuerzo(mandado), 0);
      expect(PausasService.pausaDeAlmuerzo(mandado), isNull);
    });

    test('solo cuentan los minutos que caen dentro de la franja', () {
      // De 13:45 a 14:15 solo los quince primeros minutos son almuerzo.
      expect(
        PausasService.minutosDeAlmuerzo(
          const [Pausa(inicio: '13:45', fin: '14:15')],
        ),
        15,
      );
      // Y por el otro extremo, de 11:00 a 12:00 solo la media hora final.
      expect(
        PausasService.minutosDeAlmuerzo(
          const [Pausa(inicio: '11:00', fin: '12:00')],
        ),
        30,
      );
    });

    test('el almuerzo es la pausa que más minutos mete en la franja', () {
      expect(
        PausasService.pausaDeAlmuerzo(const [
          Pausa(inicio: '09:30', fin: '10:00'),
          Pausa(inicio: '12:00', fin: '12:45'),
          Pausa(inicio: '13:50', fin: '14:30'),
        ]),
        const Pausa(inicio: '12:00', fin: '12:45'),
      );
    });

    test('la pausa en curso ya se reconoce como almuerzo', () {
      // Si no, el día se quedaría sin almuerzo identificado justo mientras se
      // está almorzando.
      expect(
        PausasService.pausaDeAlmuerzo(const [Pausa(inicio: '12:00')]),
        const Pausa(inicio: '12:00'),
      );
    });
  });

  group('horas del día', () {
    test('cada pausa se descuenta de lo trabajado', () {
      final jornada = dia(
        salida: '17:00',
        pausas: const [
          Pausa(inicio: '09:30', fin: '10:00'),
          Pausa(inicio: '12:00', fin: '12:20'),
        ],
      );
      // Nueve horas de presencia menos cincuenta minutos fuera.
      expect(ReportsService.minutosTrabajados(jornada), 490);
    });

    test('el mandado de la mañana no cubre el descuento del almuerzo', () {
      // Este es el caso que motiva la franja: si la media hora de las nueve
      // y media contara como almuerzo, la app daría por cumplido un descuento
      // que la empresa va a hacer igual y adelantaría la salida.
      final jornada = dia(
        salida: '17:00',
        descuento: 30,
        pausas: const [
          Pausa(inicio: '09:30', fin: '10:00'),
          Pausa(inicio: '12:00', fin: '12:20'),
        ],
      );
      expect(ReportsService.descuentoPendiente(jornada), 10);
      expect(ReportsService.minutosTrabajados(jornada), 480);
    });

    test('un almuerzo largo cubre el descuento y no resta dos veces', () {
      final jornada = dia(
        salida: '17:00',
        descuento: 30,
        pausas: const [Pausa(inicio: '12:00', fin: '13:00')],
      );
      expect(ReportsService.descuentoPendiente(jornada), 0);
      expect(ReportsService.minutosTrabajados(jornada), 480);
    });

    test('quien se va y no vuelve deja de contar en la pausa', () {
      // Salida real marcada pero la pausa quedó abierta: la tarde no se
      // trabajó, aunque el día se cerrara a las cinco.
      final jornada = dia(
        salida: '17:00',
        pausas: const [Pausa(inicio: '15:00')],
      );
      expect(ReportsService.minutosTrabajados(jornada), 420);
    });

    test('sin salida real el día cae al valor guardado', () {
      final jornada = dia(cumplidos: 240, pausas: const [Pausa(inicio: '12:00')]);
      expect(ReportsService.minutosTrabajados(jornada), 240);
    });
  });

  group('resumen', () {
    test('una sola pausa se enseña como tramo', () {
      expect(
        PausasService.resumen(const [Pausa(inicio: '12:00', fin: '12:30')]),
        '12:00–12:30',
      );
    });

    test('la pausa en curso se queda sin cerrar', () {
      expect(PausasService.resumen(const [Pausa(inicio: '12:00')]), '12:00–...');
    });

    test('varias pausas se cuentan y se suman', () {
      expect(
        PausasService.resumen(const [
          Pausa(inicio: '09:30', fin: '10:00'),
          Pausa(inicio: '12:00', fin: '12:20'),
        ]),
        '2 pausas (0h 50m)',
      );
    });

    test('un día sin pausas no enseña nada', () {
      expect(PausasService.resumen(const []), '--:--');
    });
  });
}

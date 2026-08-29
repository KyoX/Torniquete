import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/models/pausa.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/services/reports_service.dart';
import 'package:torniquete/services/widget_service.dart';

/// El almuerzo que la empresa descuenta salgas o no a comer.
///
/// La regla es que el descuento configurado es un *mínimo*: el almuerzo real
/// cuenta contra él y solo se resta lo que falte. Estas pruebas fijan las tres
/// situaciones que se dan de verdad —almuerzo corto, largo y no tomado— más el
/// caso de quien nunca marca almuerzo, que antes de este ajuste no se podía
/// registrar.
void main() {
  Registro dia({
    String? e1,
    String? s1,
    String? e2,
    String? sr,
    int meta = 510,
    int descuento = 30,
    TipoDia tipo = TipoDia.normal,
  }) =>
      Registro(
        fecha: '2026-08-28',
        entrada1: e1,
        pausas: [if (s1 != null) Pausa(inicio: s1, fin: e2)],
        salidaReal: sr,
        metaMinutos: meta,
        tipoDia: tipo,
        descuentoAlmuerzoMinutos: descuento,
      );

  int enVivo(Registro r, String hora) {
    final partes = hora.split(':');
    return ReportsService.minutosEnVivo(
      r,
      int.parse(partes[0]) * 60 + int.parse(partes[1]),
    );
  }

  group('descuentoPendiente', () {
    test('sin descuento configurado nunca hay nada pendiente', () {
      expect(
        ReportsService.descuentoPendiente(
          dia(e1: '08:00', s1: '12:00', e2: '12:10', descuento: 0),
        ),
        0,
      );
    });

    test('un día que no ha empezado no descuenta almuerzo', () {
      expect(ReportsService.descuentoPendiente(dia()), 0);
    });

    test('sin salir a comer se descuenta el mínimo entero', () {
      expect(ReportsService.descuentoPendiente(dia(e1: '08:00')), 30);
    });

    test('un almuerzo corto solo debe la diferencia', () {
      expect(
        ReportsService.descuentoPendiente(
          dia(e1: '08:00', s1: '12:00', e2: '12:20'),
        ),
        10,
      );
    });

    test('un almuerzo más largo que el mínimo no debe nada', () {
      expect(
        ReportsService.descuentoPendiente(
          dia(e1: '08:00', s1: '12:00', e2: '13:00'),
        ),
        0,
      );
    });

    test('el almuerzo en curso se va acreditando minuto a minuto', () {
      final r = dia(e1: '08:00', s1: '12:00');
      // Sin esto el progreso caería 30 minutos de golpe al salir a almorzar
      // para recuperarlos enteros al marcar el regreso.
      expect(ReportsService.descuentoPendiente(r, minutosAhora: 12 * 60), 30);
      expect(
        ReportsService.descuentoPendiente(r, minutosAhora: 12 * 60 + 10),
        20,
      );
      expect(
        ReportsService.descuentoPendiente(r, minutosAhora: 12 * 60 + 45),
        0,
      );
    });
  });

  group('el día ya cerrado', () {
    test('un almuerzo corto no adelanta la salida', () {
      // De 08:00 a 17:00 hay 9h de presencia. Con un almuerzo de 20 minutos
      // se descuenta igual el mínimo de 30, así que quedan 8h 30m: las mismas
      // que si se hubiera almorzado la media hora entera.
      expect(
        ReportsService.minutosTrabajados(
          dia(e1: '08:00', s1: '12:00', e2: '12:20', sr: '17:00'),
        ),
        510,
      );
      expect(
        ReportsService.minutosTrabajados(
          dia(e1: '08:00', s1: '12:00', e2: '12:30', sr: '17:00'),
        ),
        510,
      );
    });

    test('un almuerzo largo se descuenta entero, no solo el mínimo', () {
      // Hora y media fuera son hora y media que no se trabajaron: el mínimo
      // no las recorta.
      expect(
        ReportsService.minutosTrabajados(
          dia(e1: '08:00', s1: '12:00', e2: '13:30', sr: '17:00'),
        ),
        450,
      );
    });

    test('una jornada corrida se calcula sin caer al valor guardado', () {
      // Antes, sin las cuatro marcas, esto devolvía `minutosCumplidos`, que
      // solo era correcto si la app estaba abierta justo al salir.
      expect(
        ReportsService.minutosTrabajados(dia(e1: '08:00', sr: '17:00')),
        510,
      );
    });

    test('el descuento no puede dejar el día en horas negativas', () {
      expect(
        ReportsService.minutosTrabajados(dia(e1: '08:00', sr: '08:10')),
        0,
      );
    });

    test('minutosDesdeMarcas coincide con el total del día', () {
      final r = dia(e1: '08:00', s1: '12:00', e2: '12:20', sr: '17:00');
      expect(
        ReportsService.minutosDesdeMarcas(r),
        ReportsService.minutosTrabajados(r),
      );
    });
  });

  group('el día en curso', () {
    test('el descuento se aplica desde el principio del día', () {
      // A las 09:00 hay una hora de presencia, pero media ya está apartada
      // para el almuerzo que la empresa va a descontar igual.
      expect(enVivo(dia(e1: '08:00'), '09:00'), 30);
    });

    test('sin marcar almuerzo el tramo corre hasta la hora actual', () {
      expect(enVivo(dia(e1: '08:00'), '14:00'), 330);
    });

    test('la salida real detiene una jornada corrida', () {
      // El tramo único tiene que cerrar con la salida real; si no, el
      // contador seguía corriendo después de haber salido.
      expect(enVivo(dia(e1: '08:00', sr: '17:00'), '19:00'), 510);
    });

    test('el progreso no salta al marcar la salida a almorzar', () {
      final antes = enVivo(dia(e1: '08:00'), '12:00');
      final justoDespues = enVivo(dia(e1: '08:00', s1: '12:00'), '12:00');
      expect(justoDespues, antes);
    });
  });

  test('sin descuento configurado el cálculo es el de siempre', () {
    final r = dia(e1: '08:00', s1: '12:00', e2: '12:20', sr: '17:00',
        descuento: 0);
    expect(ReportsService.minutosTrabajados(r), 520);
    expect(enVivo(r, '17:00'), 520);
  });

  test('el widget resta el mismo almuerzo que el resto de la app', () {
    final registro = dia(e1: '08:00');
    final ahora = DateTime(2026, 8, 28, 11, 0);
    final resumen = WidgetService.resumir(
      registro: registro,
      horaEstimadaSalida: const TimeOfDay(hour: 17, minute: 0),
      ahora: ahora,
    );
    // El widget suma por su cuenta los minutos del tramo abierto, así que el
    // descuento tiene que viajar ya restado del acumulado.
    expect(resumen.minutosBase, -30);
    expect(resumen.abiertoDesdeMinutos, 8 * 60);
    expect(
      resumen.minutosBase + (11 * 60 - resumen.abiertoDesdeMinutos),
      enVivo(registro, '11:00'),
    );
  });
}

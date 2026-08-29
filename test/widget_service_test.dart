import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/models/pausa.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/services/reports_service.dart';
import 'package:torniquete/services/widget_service.dart';

void main() {
  final ahora = DateTime(2026, 8, 21, 14, 5);

  WidgetResumen resumir(Registro? registro, {TimeOfDay? salida}) =>
      WidgetService.resumir(
        registro: registro,
        horaEstimadaSalida: salida,
        ahora: ahora,
      );

  Registro dia({
    String? e1,
    String? s1,
    String? e2,
    String? sr,
    TipoDia tipo = TipoDia.normal,
  }) =>
      Registro(
        fecha: '2026-08-21',
        entrada1: e1,
        pausas: [if (s1 != null) Pausa(inicio: s1, fin: e2)],
        salidaReal: sr,
        metaMinutos: 510,
        tipoDia: tipo,
      );

  test('sin registro el widget no inventa datos', () {
    final resumen = resumir(null);
    expect(resumen.minutosBase, 0);
    expect(resumen.hayTramoAbierto, isFalse);
    expect(resumen.metaMinutos, 0);
  });

  test('la mañana en curso viaja como tramo abierto, no como total', () {
    // El widget nativo sumará los minutos corridos desde las 08:00, así no
    // se congela entre una actualización y otra.
    final resumen = resumir(dia(e1: '08:00'));
    expect(resumen.minutosBase, 0);
    expect(resumen.abiertoDesdeMinutos, 8 * 60);
    expect(resumen.estado, 'Trabajando');
  });

  test('durante el almuerzo no hay ningún tramo corriendo', () {
    final resumen = resumir(dia(e1: '08:00', s1: '12:00'));
    expect(resumen.minutosBase, 240);
    expect(resumen.hayTramoAbierto, isFalse);
    expect(resumen.estado, 'En almuerzo');
  });

  test('la tarde en curso deja la mañana cerrada en el total', () {
    final resumen = resumir(
      dia(e1: '08:00', s1: '12:00', e2: '13:00'),
      salida: const TimeOfDay(hour: 17, minute: 30),
    );
    expect(resumen.minutosBase, 240);
    expect(resumen.abiertoDesdeMinutos, 13 * 60);
    expect(resumen.salida, 'Salida estimada 17:30');
  });

  test('con la jornada cerrada el total ya no corre', () {
    final resumen = resumir(dia(e1: '08:00', s1: '12:00', e2: '13:00', sr: '17:00'));
    expect(resumen.minutosBase, 480);
    expect(resumen.hayTramoAbierto, isFalse);
    expect(resumen.estado, 'Jornada cerrada');
    expect(resumen.salida, 'Saliste a las 17:00');
  });

  test('un festivo se anuncia como día sin meta', () {
    final resumen = resumir(dia(e1: '08:00', tipo: TipoDia.festivo));
    expect(resumen.estado, 'Festivo');
    expect(resumen.metaMinutos, 0);
    expect(resumen.salida, 'Día sin meta de horas');
  });

  test('las marcas se muestran en el orden del día', () {
    final resumen = resumir(dia(e1: '08:00', s1: '12:00'));
    expect(resumen.marcas, '08:00 · 12:00–... · --:--');
    expect(resumen.actualizado, '14:05');
  });

  test('con varias pausas el tramo abierto arranca en la última', () {
    final resumen = resumir(
      Registro(
        fecha: '2026-08-28',
        entrada1: '08:00',
        pausas: const [
          Pausa(inicio: '09:30', fin: '10:00'),
          Pausa(inicio: '12:00', fin: '12:45'),
        ],
        metaMinutos: 510,
      ),
    );
    // Las dos pausas suman 1h 15m, así que a las 12:45 se llevaban 3h 30m.
    expect(resumen.minutosBase, 210);
    expect(resumen.abiertoDesdeMinutos, 12 * 60 + 45);
    // Y el widget suma solos los minutos corridos desde entonces.
    expect(
      resumen.minutosBase + (14 * 60 + 5 - resumen.abiertoDesdeMinutos),
      ReportsService.minutosEnVivo(
        Registro(
          fecha: '2026-08-28',
          entrada1: '08:00',
          pausas: const [
            Pausa(inicio: '09:30', fin: '10:00'),
            Pausa(inicio: '12:00', fin: '12:45'),
          ],
          metaMinutos: 510,
        ),
        14 * 60 + 5,
      ),
    );
  });

  test('una pausa en curso congela el reloj del widget', () {
    final resumen = resumir(
      Registro(
        fecha: '2026-08-28',
        entrada1: '08:00',
        pausas: const [Pausa(inicio: '12:00')],
        metaMinutos: 510,
      ),
    );
    expect(resumen.estado, 'En almuerzo');
    expect(resumen.hayTramoAbierto, isFalse);
    expect(resumen.minutosBase, 240);
  });
}

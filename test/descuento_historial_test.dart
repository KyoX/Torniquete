import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/models/pausa.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/services/descuento_almuerzo_service.dart';
import 'package:torniquete/services/reports_service.dart';

/// Aplicar el descuento de almuerzo a los días ya guardados.
///
/// Es la única operación de la app que reescribe el pasado, así que lo que
/// se prueba aquí es sobre todo lo que NO debe tocar y que el número que se
/// le enseña al usuario antes de confirmar es el de verdad.
void main() {
  Registro dia(
    String fecha, {
    String? e1,
    String? s1,
    String? e2,
    String? sr,
    int descuento = 0,
    int cumplidos = 0,
    TipoDia tipo = TipoDia.normal,
  }) =>
      Registro(
        fecha: fecha,
        entrada1: e1,
        pausas: [if (s1 != null) Pausa(inicio: s1, fin: e2)],
        salidaReal: sr,
        metaMinutos: 510,
        minutosCumplidos: cumplidos,
        tipoDia: tipo,
        descuentoAlmuerzoMinutos: descuento,
      );

  /// Un día completo de 08:00 a 17:00 con veinte minutos de almuerzo: nueve
  /// horas de presencia que con media hora de descuento quedan en 8h 30m.
  Registro completo(String fecha, {int descuento = 0}) => dia(
        fecha,
        e1: '08:00',
        s1: '12:00',
        e2: '12:20',
        sr: '17:00',
        descuento: descuento,
      );

  const hoy = '2026-08-28';

  group('revisar', () {
    test('un historial que ya usa el descuento no da trabajo', () {
      final revision = DescuentoAlmuerzoService.revisar(
        [completo('2026-08-26', descuento: 30)],
        descuento: 30,
        hoy: hoy,
      );
      expect(revision.sinTrabajo, isTrue);
      expect(revision.cambios, isEmpty);
    });

    test('el día de hoy queda fuera', () {
      // Lo lleva el dashboard, que ya le aplica el ajuste vigente al
      // cargarlo. Reescribirlo desde aquí pelearía con esa copia en memoria.
      final revision = DescuentoAlmuerzoService.revisar(
        [completo(hoy)],
        descuento: 30,
        hoy: hoy,
      );
      expect(revision.sinTrabajo, isTrue);
    });

    test('cuenta cuánto se mueve el banco de horas', () {
      final revision = DescuentoAlmuerzoService.revisar(
        [completo('2026-08-26'), completo('2026-08-27')],
        descuento: 30,
        hoy: hoy,
      );
      expect(revision.aSellar, hasLength(2));
      expect(revision.cambios, hasLength(2));
      // 520 minutos pasan a 510 en cada día: el almuerzo real de 20 minutos
      // no llega al mínimo de 30 y se descuenta la diferencia.
      expect(revision.cambios.first.minutosAntes, 520);
      expect(revision.cambios.first.minutosDespues, 510);
      expect(revision.diferenciaMinutos, -20);
    });

    test('quitar el descuento devuelve las horas', () {
      final revision = DescuentoAlmuerzoService.revisar(
        [completo('2026-08-26', descuento: 30)],
        descuento: 0,
        hoy: hoy,
      );
      expect(revision.diferenciaMinutos, 10);
    });

    test('los días que no cambian de horas se sellan pero no se anuncian', () {
      // Un día en blanco, uno justificado y uno con un almuerzo de hora y
      // media: los tres cambian de regla sin cambiar de números, así que no
      // tienen por qué salir en la confirmación.
      final revision = DescuentoAlmuerzoService.revisar(
        [
          dia('2026-08-24'),
          dia('2026-08-25', tipo: TipoDia.festivo),
          dia('2026-08-26', e1: '08:00', s1: '12:00', e2: '13:30', sr: '17:00'),
        ],
        descuento: 30,
        hoy: hoy,
      );
      expect(revision.aSellar, hasLength(3));
      expect(revision.cambios, isEmpty);
      expect(revision.diferenciaMinutos, 0);
    });

    test('un día al que le faltan marcas conserva su total guardado', () {
      // Sin salida real no hay nada que recalcular: el día cae a lo que se
      // guardó en su momento y el descuento no puede tocarlo.
      final registros = [
        dia('2026-08-26', e1: '08:00', s1: '12:00', e2: '12:20', cumplidos: 240),
      ];
      final revision = DescuentoAlmuerzoService.revisar(
        registros,
        descuento: 30,
        hoy: hoy,
      );
      expect(revision.aSellar, hasLength(1));
      expect(revision.cambios, isEmpty);
      expect(
        ReportsService.minutosTrabajados(revision.aSellar.first),
        240,
      );
    });

    test('los cambios se listan del más reciente al más antiguo', () {
      final revision = DescuentoAlmuerzoService.revisar(
        [completo('2026-08-20'), completo('2026-08-27'), completo('2026-08-24')],
        descuento: 30,
        hoy: hoy,
      );
      expect(
        revision.cambios.map((c) => c.registro.fecha),
        ['2026-08-27', '2026-08-24', '2026-08-20'],
      );
    });

    test('lo que se guardará ya lleva la regla nueva', () {
      final revision = DescuentoAlmuerzoService.revisar(
        [completo('2026-08-26')],
        descuento: 45,
        hoy: hoy,
      );
      expect(revision.aSellar.single.descuentoAlmuerzoMinutos, 45);
      // Y las marcas siguen intactas: solo cambia la regla con la que se
      // interpretan.
      expect(revision.aSellar.single.entrada1, '08:00');
      expect(revision.aSellar.single.salidaReal, '17:00');
    });
  });
}

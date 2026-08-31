import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/models/pausa.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/providers/registro_provider.dart';

/// Qué marca ofrece cada aviso de la sede: el de llegada y el de salida.
///
/// Las reglas se prueban aquí y no en el lado nativo a propósito: Kotlin solo
/// lee el resultado que Dart le deja escrito, así que esta es la única
/// definición de "qué falta marcar" que existe en la app.
void main() {
  Registro dia({
    String? e1,
    String? s1,
    String? e2,
    String? sr,
    TipoDia tipo = TipoDia.normal,
  }) =>
      Registro(
        fecha: '2026-08-28',
        entrada1: e1,
        pausas: [if (s1 != null) Pausa(inicio: s1, fin: e2)],
        salidaReal: sr,
        metaMinutos: 510,
        tipoDia: tipo,
      );

  test('sin registro cargado no se ofrece nada', () {
    expect(RegistroProvider.marcaSugeridaAlLlegar(null), isNull);
  });

  test('un día en blanco ofrece la entrada de la mañana', () {
    expect(
      RegistroProvider.marcaSugeridaAlLlegar(dia()),
      MarcaTipo.entrada1,
    );
  });

  test('tras salir a almorzar ofrece el regreso', () {
    expect(
      RegistroProvider.marcaSugeridaAlLlegar(dia(e1: '08:00', s1: '12:00')),
      MarcaTipo.reanudar,
    );
  });

  test('sin la salida a almuerzo marcada no se ofrece el regreso', () {
    // Volver al radio a media mañana —un café, o registrar la geocerca otra
    // vez estando ya en la oficina— no es un regreso de almuerzo. Preguntarlo
    // ahí gastaría el aviso del día en el momento equivocado.
    expect(
      RegistroProvider.marcaSugeridaAlLlegar(dia(e1: '08:00')),
      isNull,
    );
  });

  test('con la tarde ya marcada no queda nada que ofrecer', () {
    expect(
      RegistroProvider.marcaSugeridaAlLlegar(
        dia(e1: '08:00', s1: '12:00', e2: '13:00'),
      ),
      isNull,
    );
  });

  test('una jornada cerrada no se reabre al volver a pasar por la sede', () {
    expect(
      RegistroProvider.marcaSugeridaAlLlegar(
        dia(e1: '08:00', s1: '12:00', e2: '13:00', sr: '17:30'),
      ),
      isNull,
    );
  });

  test('un día justificado no pide marcas', () {
    for (final tipo in TipoDia.values.where((t) => t.esJustificado)) {
      expect(
        RegistroProvider.marcaSugeridaAlLlegar(dia(tipo: tipo)),
        isNull,
        reason: 'un día de tipo ${tipo.etiqueta} no debería pedir marcas',
      );
    }
  });

  group('al salir de la sede', () {
    test('sin registro cargado no se ofrece nada', () {
      expect(RegistroProvider.marcaSugeridaAlSalir(null), isNull);
    });

    test('un día sin entrada no tiene jornada que cerrar', () {
      // Salir del radio sin haber entrado es irse de un sitio donde hoy no se
      // ha trabajado.
      expect(RegistroProvider.marcaSugeridaAlSalir(dia()), isNull);
    });

    test('con la jornada en marcha se ofrece la salida', () {
      expect(
        RegistroProvider.marcaSugeridaAlSalir(dia(e1: '08:00')),
        MarcaTipo.salidaReal,
      );
    });

    test('con una pausa abierta no se ofrece la salida', () {
      // Quien sale del radio con la pausa corriendo se fue a comer, no a su
      // casa. Si resulta que no vuelve, el día queda abierto y lo recoge la
      // revisión del día siguiente.
      expect(
        RegistroProvider.marcaSugeridaAlSalir(dia(e1: '08:00', s1: '12:00')),
        isNull,
      );
    });

    test('tras volver del almuerzo vuelve a ofrecerse', () {
      expect(
        RegistroProvider.marcaSugeridaAlSalir(
          dia(e1: '08:00', s1: '12:00', e2: '13:00'),
        ),
        MarcaTipo.salidaReal,
      );
    });

    test('una jornada ya cerrada no se ofrece dos veces', () {
      expect(
        RegistroProvider.marcaSugeridaAlSalir(
          dia(e1: '08:00', s1: '12:00', e2: '13:00', sr: '17:30'),
        ),
        isNull,
      );
    });

    test('un festivo trabajado también se puede cerrar', () {
      // El día no exige meta, pero si tiene entrada se está trabajando y esas
      // horas son tiempo extra que hay que registrar igual.
      expect(
        RegistroProvider.marcaSugeridaAlSalir(
          dia(e1: '08:00', tipo: TipoDia.festivo),
        ),
        MarcaTipo.salidaReal,
      );
    });
  });

  group('desde qué hora se pregunta por la salida', () {
    int? desde(Registro? registro, {int minutosAhora = 600}) =>
        RegistroProvider.minutoParaPreguntarSalida(
          registro,
          minutosAhora: minutosAhora,
        );

    test('media hora antes de la salida estimada', () {
      // Entrada a las 8:00 y meta de 8h 30m: la salida cae a las 16:30, así
      // que a partir de las 16:00 una salida ya es creíble.
      expect(desde(dia(e1: '08:00')), 16 * 60);
    });

    test('las pausas corren el umbral igual que corren la salida', () {
      expect(
        desde(dia(e1: '08:00', s1: '12:00', e2: '13:00')),
        17 * 60,
      );
    });

    test('sin salida que ofrecer no hay umbral', () {
      // Sin esto el lado nativo no tendría con qué callarse: preguntaría en
      // cada salida del radio.
      expect(desde(dia()), isNull);
      expect(desde(dia(e1: '08:00', sr: '17:30')), isNull);
      expect(desde(dia(e1: '08:00', s1: '12:00')), isNull);
    });

    test('una jornada que se pasa de la medianoche no abre la mañana', () {
      // Sin el tope, restar el margen a un cálculo que se sale del día daría
      // un minuto pequeño y se preguntaría desde primera hora.
      expect(desde(dia(e1: '23:00')), 24 * 60 - 1);
    });
  });
}

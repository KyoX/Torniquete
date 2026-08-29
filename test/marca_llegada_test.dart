import 'package:flutter_test/flutter_test.dart';
import 'package:torniquete/models/pausa.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/providers/registro_provider.dart';

/// Qué marca ofrece el aviso de llegada a la sede.
///
/// La regla se prueba aquí y no en el lado nativo a propósito: Kotlin solo
/// lee el resultado que Dart le deja escrito, así que esta es la única
/// definición de "qué falta marcar al llegar" que existe en la app.
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
}

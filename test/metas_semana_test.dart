import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/providers/app_provider.dart';
import 'package:torniquete/services/prefs_service.dart';
import 'package:torniquete/services/reports_service.dart';

/// La meta de horas de cada día de la semana.
///
/// Antes solo había dos —lunes a jueves y viernes— y el sábado heredaba la
/// del lunes, así que un 4x10, media jornada el miércoles o un sábado suelto
/// no cabían, y registrar un fin de semana inventaba un déficit de jornada
/// entera. Lo que se prueba aquí es que cada día pide lo suyo, que quien
/// venía de la versión anterior sigue con lo mismo y que un día sin meta
/// desaparece de las cuentas en vez de contar como libre a medias.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('la semana clásica', () {
    final metas = MetasSemana.clasica();

    test('es la de siempre: lunes a jueves, viernes aparte', () {
      expect(metas.minutosDe(DateTime.monday), 510);
      expect(metas.minutosDe(DateTime.thursday), 510);
      expect(metas.minutosDe(DateTime.friday), 390);
    });

    test('el fin de semana no pide horas', () {
      // Antes el sábado heredaba la meta del lunes: registrar uno abría un
      // déficit de ocho horas y media que nadie había prometido.
      expect(metas.minutosDe(DateTime.saturday), 0);
      expect(metas.exigeHoras(DateTime.sunday), isFalse);
    });

    test('la semana suma las cinco jornadas', () {
      expect(metas.minutosSemana, 510 * 4 + 390);
    });
  });

  group('una semana a medida', () {
    test('un 4x10 cabe: cuatro días de diez y el viernes libre', () {
      final metas = MetasSemana.desde({
        DateTime.monday: 10,
        DateTime.tuesday: 10,
        DateTime.wednesday: 10,
        DateTime.thursday: 10,
      });
      expect(metas.diasConMeta, [1, 2, 3, 4]);
      expect(metas.minutosSemana, 40 * 60);
      expect(metas.exigeHoras(DateTime.friday), isFalse);
    });

    test('medio sábado también', () {
      final metas = MetasSemana.clasica().conDia(DateTime.saturday, 4.5);
      expect(metas.minutosDe(DateTime.saturday), 270);
      expect(metas.minutosDe(DateTime.monday), 510);
    });

    test('cambiar un día no toca a los demás', () {
      final metas = MetasSemana.clasica().conDia(DateTime.wednesday, 0);
      expect(metas.exigeHoras(DateTime.wednesday), isFalse);
      expect(metas.diasConMeta, [1, 2, 4, 5]);
    });

    test('lo imposible se recorta en vez de guardarse', () {
      // Esto llega de las preferencias y de un respaldo escrito por otra
      // versión, así que no se confía en ello.
      final metas = MetasSemana.desde({
        DateTime.monday: -3,
        DateTime.tuesday: 40,
        9: 8, // no existe el día 9
      });
      expect(metas.minutosDe(DateTime.monday), 0);
      expect(metas.horasDe(DateTime.tuesday), MetasSemana.maxHoras);
      expect(metas.diasConMeta, [DateTime.tuesday]);
    });
  });

  group('el día típico', () {
    test('es el promedio de los días que piden horas, no el del lunes', () {
      // Es lo que traduce el banco a días: con la semana clásica, una semana
      // entera de banco tiene que dar cinco días justos, y dividir entre la
      // meta del lunes daría cuatro y pico.
      final metas = MetasSemana.clasica();
      expect(metas.minutosDiaTipico, metas.minutosSemana ~/ 5);
      expect(metas.minutosSemana / metas.minutosDiaTipico, 5);
    });

    test('los días libres no lo rebajan', () {
      final metas = MetasSemana.desde({
        DateTime.monday: 10,
        DateTime.tuesday: 10,
        DateTime.wednesday: 10,
        DateTime.thursday: 10,
      });
      expect(metas.minutosDiaTipico, 600);
    });

    test('una semana entera sin metas no divide entre cero', () {
      expect(MetasSemana.desde(const {}).minutosDiaTipico, 0);
    });
  });

  group('cómo se cuenta la semana', () {
    test('los días seguidos que piden lo mismo se dicen juntos', () {
      expect(
        MetasSemana.clasica().legible,
        'De lunes a jueves 8h 30m · Viernes 6h 30m',
      );
    });

    test('dos días sueltos se enlazan con una y', () {
      final metas = MetasSemana.desde({
        DateTime.tuesday: 8,
        DateTime.wednesday: 8,
        DateTime.saturday: 4,
      });
      expect(metas.legible, 'Martes y miércoles 8h 00m · Sábado 4h 00m');
    });

    test('una semana sin metas se dice, no se calla', () {
      expect(MetasSemana.desde(const {}).legible, 'Ningún día pide horas');
    });
  });

  group('cómo se guarda y se lee', () {
    test('la lista de siete va y vuelve igual', () {
      final metas = MetasSemana.clasica().conDia(DateTime.saturday, 4);
      expect(MetasSemana.desdeLista(metas.comoLista), metas);
    });

    test('media semana leída a medias se descarta entera', () {
      // Vale más el valor por defecto que una semana con tres días en cero
      // que nadie eligió.
      expect(MetasSemana.desdeLista([8, 8, 8]), isNull);
      expect(MetasSemana.desdeLista(null), isNull);
    });

    test('quien viene de la versión anterior sigue con sus dos metas',
        () async {
      SharedPreferences.setMockInitialValues({
        'meta_lj_horas': 9.0,
        'meta_viernes_horas': 5.0,
      });
      final metas = await PrefsService().getMetas();

      expect(metas.minutosDe(DateTime.monday), 540);
      expect(metas.minutosDe(DateTime.friday), 300);
      expect(metas.exigeHoras(DateTime.saturday), isFalse);
    });

    test('guardar la semana deja también las dos metas viejas al día',
        () async {
      // Son lo único que entiende una versión anterior de la app: si se
      // instala el APK de ayer sobre este, el lunes y el viernes siguen en su
      // sitio en vez de volver a los valores de fábrica.
      SharedPreferences.setMockInitialValues({});
      final prefs = PrefsService();
      await prefs.guardarMetas(
        MetasSemana.desde({DateTime.monday: 10, DateTime.friday: 6}),
      );

      final guardadas = await SharedPreferences.getInstance();
      expect(guardadas.getDouble('meta_lj_horas'), 10);
      expect(guardadas.getDouble('meta_viernes_horas'), 6);
      expect((await prefs.getMetas()).minutosDe(DateTime.monday), 600);
    });

    test('lo guardado manda sobre las dos metas viejas', () async {
      SharedPreferences.setMockInitialValues({
        'meta_lj_horas': 9.0,
        'meta_viernes_horas': 5.0,
        'metas_semana_horas': ['0', '0', '0', '0', '0', '6', '0'],
      });
      final metas = await PrefsService().getMetas();

      expect(metas.diasConMeta, [DateTime.saturday]);
      expect(metas.minutosDe(DateTime.saturday), 360);
    });
  });

  group('la proyección del mes', () {
    /// Agosto de 2026 empieza en sábado y tiene cinco de cada uno de los tres
    /// primeros días. Se mira desde el día 1 para que ningún día quede en el
    /// pasado: así la proyección suma el mes entero y se ve la meta de cada
    /// día de la semana.
    final primeroDeAgosto = DateTime(2026, 8, 1);

    AppProvider providerCon(MetasSemana metas) => AppProvider()
      ..metas = metas
      // Los asuetos de agosto son de El Salvador y no de esta prueba: aquí
      // solo se mira quién pone las horas.
      ..asuetosActivos = false;

    int metaDelMes(MetasSemana metas) => ReportsService.proyeccionMesActual(
          const <Registro>[],
          providerCon(metas),
          primeroDeAgosto,
        ).metaMesMinutos;

    test('la semana clásica no cuenta los fines de semana', () {
      // 5 lunes y 4 de martes a jueves a 8h 30m, más 4 viernes a 6h 30m.
      expect(metaDelMes(MetasSemana.clasica()), 17 * 510 + 4 * 390);
    });

    test('quien trabaja los sábados los ve contar', () {
      // Antes se descartaban por su nombre, así que el sábado trabajado salía
      // como horas extra sobre una meta que ignoraba el día entero.
      final conSabado = MetasSemana.clasica().conDia(DateTime.saturday, 4);
      expect(
        metaDelMes(conSabado),
        metaDelMes(MetasSemana.clasica()) + 5 * 240,
      );
    });

    test('quien libra el miércoles deja de deberlo', () {
      final sinMiercoles = MetasSemana.clasica().conDia(DateTime.wednesday, 0);
      expect(
        metaDelMes(sinMiercoles),
        metaDelMes(MetasSemana.clasica()) - 4 * 510,
      );
    });
  });
}

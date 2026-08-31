import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/providers/historial_provider.dart';
import 'package:torniquete/services/db_service.dart';

/// El historial largo: paginarlo, filtrarlo y saltar a un mes.
///
/// Antes se pedían 60 días de golpe y lo de más atrás no existía para la app.
/// Lo que se prueba aquí es justamente lo que hace falta para llegar a un día
/// viejo: que las páginas encajen una con otra sin repetir ni saltarse nada,
/// que el filtro no esconda días que sí cuentan y que el salto de mes caiga
/// donde debe.
void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DbService.versionEsquema,
        onCreate: DbService.crearEsquema,
      ),
    );
  });

  tearDown(() => db.close());

  Future<void> insertar(
    String fecha, {
    TipoDia tipo = TipoDia.normal,
    String? claveCruda,
  }) async {
    await db.insert('registros', {
      'fecha': fecha,
      'entrada_1': '08:00',
      'salida_real': '17:00',
      'meta_minutos': 510,
      'horas_cumplidas': 0,
      'tipo_dia': claveCruda ?? tipo.clave,
      'descuento_almuerzo_min': 0,
    });
  }

  /// Del 1 de junio al 31 de agosto de 2026: 92 días seguidos, tres meses.
  Future<void> sembrarTrimestre() async {
    var dia = DateTime(2026, 6, 1);
    while (!dia.isAfter(DateTime(2026, 8, 31))) {
      await insertar(
        '${dia.year}-${dia.month.toString().padLeft(2, '0')}-'
        '${dia.day.toString().padLeft(2, '0')}',
      );
      dia = dia.add(const Duration(days: 1));
    }
  }

  /// El provider hablando con la base de verdad: la paginación solo vale si
  /// la consulta que hay debajo devuelve lo que él supone.
  HistorialProvider provider({int tamanoPagina = 30}) => HistorialProvider(
        tamanoPagina: tamanoPagina,
        cargar: ({
          int limit = 60,
          String? antesDe,
          Set<TipoDia> tipos = const {},
        }) =>
            DbService.consultarHistorial(
          db,
          limit: limit,
          antesDe: antesDe,
          tipos: tipos,
        ),
      );

  group('la consulta', () {
    test('trae los días del más reciente al más antiguo', () async {
      await sembrarTrimestre();
      final pagina = await DbService.consultarHistorial(db, limit: 3);
      expect(
        pagina.map((r) => r.fecha),
        ['2026-08-31', '2026-08-30', '2026-08-29'],
      );
    });

    test('el corte por fecha no incluye el día del corte', () async {
      await sembrarTrimestre();
      final pagina = await DbService.consultarHistorial(
        db,
        limit: 2,
        antesDe: '2026-08-10',
      );
      expect(pagina.map((r) => r.fecha), ['2026-08-09', '2026-08-08']);
    });

    test('filtrar por tipo deja fuera todo lo demás', () async {
      await insertar('2026-08-03');
      await insertar('2026-08-04', tipo: TipoDia.vacaciones);
      await insertar('2026-08-05', tipo: TipoDia.incapacidad);

      final pagina = await DbService.consultarHistorial(
        db,
        tipos: {TipoDia.vacaciones, TipoDia.incapacidad},
      );
      expect(pagina.map((r) => r.fecha), ['2026-08-05', '2026-08-04']);
    });

    test('un tipo que esta versión no conoce sale entre los normales',
        () async {
      // Un día guardado por una versión posterior. Registro lo lee como día
      // normal, así que el filtro tiene que enseñarlo igual: si no, sería un
      // día visible en la lista completa que desaparece al filtrar.
      await insertar('2026-08-06', claveCruda: 'teletrabajo');
      await insertar('2026-08-07', tipo: TipoDia.festivo);

      final normales =
          await DbService.consultarHistorial(db, tipos: {TipoDia.normal});
      expect(normales.map((r) => r.fecha), ['2026-08-06']);
      expect(normales.single.tipoDia, TipoDia.normal);

      final festivos =
          await DbService.consultarHistorial(db, tipos: {TipoDia.festivo});
      expect(festivos.map((r) => r.fecha), ['2026-08-07']);
    });
  });

  group('la paginación', () {
    test('la primera página trae lo pedido y avisa de que hay más', () async {
      await sembrarTrimestre();
      final historial = provider(tamanoPagina: 30);
      await historial.recargar();

      expect(historial.dias, hasLength(30));
      expect(historial.dias.first.fecha, '2026-08-31');
      expect(historial.hayMas, isTrue);
    });

    test('la página siguiente continúa donde iba, sin repetir ni saltarse',
        () async {
      await sembrarTrimestre();
      final historial = provider(tamanoPagina: 30);
      await historial.recargar();
      await historial.cargarMas();

      final fechas = historial.dias.map((r) => r.fecha).toList();
      expect(fechas, hasLength(60));
      expect(fechas.toSet(), hasLength(60));
      expect(fechas.last, '2026-07-03'); // 60 días seguidos hacia atrás
    });

    test('al llegar al final se apaga el aviso de que hay más', () async {
      await sembrarTrimestre();
      final historial = provider(tamanoPagina: 50);
      await historial.recargar();
      await historial.cargarMas();

      expect(historial.dias, hasLength(92));
      expect(historial.hayMas, isFalse);

      // Y ya no se pide nada más aunque se insista.
      await historial.cargarMas();
      expect(historial.dias, hasLength(92));
    });

    test('borrar un día ya cargado no descuadra la página siguiente',
        () async {
      // Es lo que se gana paginando por fecha: con un desplazamiento
      // numérico, quitar un día de arriba haría que la página siguiente se
      // saltara uno.
      await sembrarTrimestre();
      final historial = provider(tamanoPagina: 30);
      await historial.recargar();

      await db
          .delete('registros', where: 'fecha = ?', whereArgs: ['2026-08-20']);
      await historial.cargarMas();

      final fechas = historial.dias.map((r) => r.fecha).toList();
      expect(fechas.toSet(), hasLength(fechas.length));
      // La segunda página arranca justo debajo del último día de la primera,
      // sin hueco.
      expect(fechas[29], '2026-08-02');
      expect(fechas[30], '2026-08-01');
    });

    test('recargar conserva los días que ya se habían bajado', () async {
      // Después de editar un día de hace dos meses, volver al principio de la
      // lista obligaría a bajar otra vez hasta él.
      await sembrarTrimestre();
      final historial = provider(tamanoPagina: 30);
      await historial.recargar();
      await historial.cargarMas();
      await historial.recargar();

      expect(historial.dias, hasLength(60));
      expect(historial.dias.first.fecha, '2026-08-31');
      expect(historial.dias.last.fecha, '2026-07-03');
    });
  });

  group('el salto a un mes', () {
    test('la lista empieza en el último día del mes elegido', () async {
      await sembrarTrimestre();
      final historial = provider(tamanoPagina: 5);
      await historial.irAlMes(DateTime(2026, 7, 14));

      expect(historial.dias.first.fecha, '2026-07-31');
      expect(historial.dias.last.fecha, '2026-07-27');
      expect(historial.filtrado, isTrue);
    });

    test('desde ahí se sigue bajando a los meses anteriores', () async {
      await sembrarTrimestre();
      final historial = provider(tamanoPagina: 31);
      await historial.irAlMes(DateTime(2026, 7, 14));
      await historial.cargarMas();

      expect(historial.dias.first.fecha, '2026-07-31');
      expect(historial.dias.last.fecha, '2026-06-01');
      expect(historial.hayMas, isFalse);
    });

    test('quitar el mes devuelve la lista al día más reciente', () async {
      await sembrarTrimestre();
      final historial = provider(tamanoPagina: 5);
      await historial.irAlMes(DateTime(2026, 6, 10));
      await historial.quitarMes();

      expect(historial.dias.first.fecha, '2026-08-31');
      expect(historial.filtrado, isFalse);
    });

    test('el mes y el tipo de día se aplican juntos', () async {
      await insertar('2026-07-05', tipo: TipoDia.festivo);
      await insertar('2026-07-20');
      await insertar('2026-08-15', tipo: TipoDia.festivo);

      final historial = provider(tamanoPagina: 10);
      await historial.irAlMes(DateTime(2026, 7, 1));
      await historial.filtrarPor({TipoDia.festivo});

      expect(historial.dias.map((r) => r.fecha), ['2026-07-05']);

      await historial.limpiarFiltros();
      expect(historial.dias, hasLength(3));
    });
  });

  group('llegar a un día concreto', () {
    test('mostrarMesDe quita los tipos y se planta en su mes', () async {
      // Al guardar un día que el filtro dejaba fuera, la lista no cambiaba y
      // parecía que no se había guardado nada.
      await insertar('2026-06-09');
      await insertar('2026-08-15', tipo: TipoDia.festivo);

      final historial = provider(tamanoPagina: 10);
      await historial.filtrarPor({TipoDia.festivo});
      expect(historial.dias.map((r) => r.fecha), ['2026-08-15']);

      await historial.mostrarMesDe(DateTime(2026, 6, 9));

      expect(historial.dias.map((r) => r.fecha), ['2026-06-09']);
      expect(historial.tipos, isEmpty);
      expect(historial.mes, DateTime(2026, 6));
    });
  });

  group('cambiar de filtro a media carga', () {
    test('la consulta que llega tarde no pisa a la que se pidió después',
        () async {
      // Tocar dos chips seguidos deja dos consultas en el aire, y la que se
      // pidió primero puede contestar de última.
      final historial = HistorialProvider(
        tamanoPagina: 5,
        cargar: ({
          int limit = 60,
          String? antesDe,
          Set<TipoDia> tipos = const {},
        }) async {
          if (tipos.isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
            return [const Registro(fecha: '2026-08-31', metaMinutos: 510)];
          }
          return [const Registro(fecha: '2026-08-15', metaMinutos: 510)];
        },
      );

      final lenta = historial.filtrarPor(const {});
      final rapida = historial.filtrarPor({TipoDia.festivo});
      await Future.wait([lenta, rapida]);

      expect(historial.dias.map((r) => r.fecha), ['2026-08-15']);
      expect(historial.cargando, isFalse);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:torniquete/models/pausa.dart';
import 'package:torniquete/models/registro.dart';
import 'package:torniquete/models/tipo_dia.dart';
import 'package:torniquete/services/db_service.dart';
import 'package:torniquete/services/reports_service.dart';

/// Comprueba que una instalación vieja sobrevive a la actualización.
///
/// Cada versión histórica se recrea con el esquema exacto que tenía en su
/// momento y con datos dentro, se abre con la versión actual —que dispara
/// [DbService.migrarEsquema]— y se verifica que ni un día se perdió. Importa
/// especialmente el salto de varias versiones de golpe: alguien que lleva
/// meses sin actualizar salta directo a la última.
void main() {
  sqfliteFfiInit();

  /// Esquema de la v1: sin `salida_real`, sin `ubicaciones`, sin banco.
  Future<void> crearV1(Database db) async {
    await db.execute('''
      CREATE TABLE registros (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT UNIQUE NOT NULL,
        entrada_1 TEXT,
        salida_1 TEXT,
        entrada_2 TEXT,
        meta_minutos INTEGER NOT NULL,
        horas_cumplidas INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert('registros', {
      'fecha': '2026-01-15',
      'entrada_1': '08:00',
      'salida_1': '12:00',
      'entrada_2': '13:00',
      'meta_minutos': 510,
      'horas_cumplidas': 240,
    });
  }

  /// Esquema de la v2: ya tiene `salida_real`, todavía no `ubicaciones`.
  Future<void> crearV2(Database db) async {
    await db.execute('''
      CREATE TABLE registros (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT UNIQUE NOT NULL,
        entrada_1 TEXT,
        salida_1 TEXT,
        entrada_2 TEXT,
        salida_real TEXT,
        meta_minutos INTEGER NOT NULL,
        horas_cumplidas INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert('registros', {
      'fecha': '2026-02-20',
      'entrada_1': '08:00',
      'salida_1': '12:00',
      'entrada_2': '13:00',
      'salida_real': '17:30',
      'meta_minutos': 510,
      'horas_cumplidas': 510,
    });
  }

  /// Esquema de la v3: el de la versión publicada antes de este cambio.
  Future<void> crearV3(Database db) async {
    await crearV2(db);
    await db.execute('''
      CREATE TABLE ubicaciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        tipo TEXT NOT NULL,
        hora TEXT NOT NULL,
        latitud REAL NOT NULL,
        longitud REAL NOT NULL,
        precision_m REAL,
        capturado_en TEXT NOT NULL,
        manual INTEGER NOT NULL DEFAULT 0,
        UNIQUE (fecha, tipo)
      )
    ''');
    await db.insert('ubicaciones', {
      'fecha': '2026-02-20',
      'tipo': 'entrada1',
      'hora': '08:00',
      'latitud': 4.60971,
      'longitud': -74.08175,
      'capturado_en': '2026-02-20T08:00:00.000',
      'manual': 0,
    });
  }

  /// Esquema de la v4: el de la versión publicada antes del descuento fijo
  /// de almuerzo.
  Future<void> crearV4(Database db) async {
    await db.execute('''
      CREATE TABLE registros (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT UNIQUE NOT NULL,
        entrada_1 TEXT,
        salida_1 TEXT,
        entrada_2 TEXT,
        salida_real TEXT,
        meta_minutos INTEGER NOT NULL,
        horas_cumplidas INTEGER NOT NULL DEFAULT 0,
        tipo_dia TEXT NOT NULL DEFAULT 'normal',
        nota TEXT
      )
    ''');
    await db.insert('registros', {
      'fecha': '2026-03-10',
      'entrada_1': '08:00',
      'salida_1': '12:00',
      'entrada_2': '12:20',
      'salida_real': '17:00',
      'meta_minutos': 510,
      'horas_cumplidas': 520,
      'tipo_dia': 'normal',
    });
  }

  /// Esquema de la v5: el de la versión publicada antes de las pausas, con
  /// el almuerzo todavía en un par de columnas fijas.
  Future<void> crearV5(Database db) async {
    await db.execute('''
      CREATE TABLE registros (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT UNIQUE NOT NULL,
        entrada_1 TEXT,
        salida_1 TEXT,
        entrada_2 TEXT,
        salida_real TEXT,
        meta_minutos INTEGER NOT NULL,
        horas_cumplidas INTEGER NOT NULL DEFAULT 0,
        tipo_dia TEXT NOT NULL DEFAULT 'normal',
        nota TEXT,
        descuento_almuerzo_min INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.insert('registros', {
      'fecha': '2026-04-06',
      'entrada_1': '08:00',
      'salida_1': '12:00',
      'entrada_2': '12:30',
      'salida_real': '17:00',
      'meta_minutos': 510,
      'horas_cumplidas': 510,
      'tipo_dia': 'normal',
      'descuento_almuerzo_min': 30,
    });
    // Una jornada corrida: no salió a comer, así que no hay pausa que crear.
    await db.insert('registros', {
      'fecha': '2026-04-07',
      'entrada_1': '08:00',
      'salida_real': '16:30',
      'meta_minutos': 510,
      'horas_cumplidas': 480,
      'tipo_dia': 'normal',
      'descuento_almuerzo_min': 30,
    });
    // Y un día en que se salió a comer y se olvidó marcar la vuelta.
    await db.insert('registros', {
      'fecha': '2026-04-08',
      'entrada_1': '08:00',
      'salida_1': '12:00',
      'meta_minutos': 510,
      'horas_cumplidas': 240,
      'tipo_dia': 'normal',
      'descuento_almuerzo_min': 30,
    });
  }

  /// Abre [ruta] tal y como lo hace la app: misma versión, mismo esquema y
  /// misma migración.
  Future<Database> abrirComoLaApp(String ruta) {
    return databaseFactoryFfi.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: DbService.versionEsquema,
        onCreate: DbService.crearEsquema,
        onUpgrade: DbService.migrarEsquema,
        // Sin esto sqflite devolvería la conexión ya cacheada al reabrir y
        // la migración nunca llegaría a correr.
        singleInstance: false,
      ),
    );
  }

  /// Ruta de trabajo propia de cada prueba, que se limpia al terminar.
  String rutaTemporal() {
    final dir = Directory.systemTemp.createTempSync('torniquete_migracion');
    addTearDown(() => dir.deleteSync(recursive: true));
    return p.join(dir.path, 'torniquete.db');
  }

  /// Crea una base con el esquema de [version] y la reabre con la actual,
  /// devolviendo la base ya migrada.
  ///
  /// Tiene que ser un archivo de verdad: una base en memoria se destruye al
  /// cerrarla, así que al reabrirla correría `onCreate` en vez de `onUpgrade`
  /// y la prueba pasaría sin haber migrado nada.
  Future<Database> migrarDesde(
    int version,
    Future<void> Function(Database) crear,
  ) async {
    final ruta = rutaTemporal();

    final vieja = await databaseFactoryFfi.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) => crear(db),
        singleInstance: false,
      ),
    );
    await vieja.close();

    return abrirComoLaApp(ruta);
  }

  Future<Set<String>> columnasDe(Database db, String tabla) async {
    final filas = await db.rawQuery('PRAGMA table_info($tabla)');
    return filas.map((f) => f['name'] as String).toSet();
  }

  Future<bool> existeTabla(Database db, String tabla) async {
    final filas = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tabla],
    );
    return filas.isNotEmpty;
  }

  group('migración a la versión actual', () {
    test('desde la v1 se aplican todos los pasos de corrido', () async {
      final db = await migrarDesde(1, crearV1);
      addTearDown(db.close);

      final columnas = await columnasDe(db, 'registros');
      // Paso 1 -> 2, paso 3 -> 4, paso 4 -> 5.
      expect(
        columnas,
        containsAll([
          'salida_real',
          'tipo_dia',
          'nota',
          'descuento_almuerzo_min',
          'pausas',
        ]),
      );
      // Paso 2 -> 3 y paso 3 -> 4.
      expect(await existeTabla(db, 'ubicaciones'), isTrue);
      expect(await existeTabla(db, 'movimientos_banco'), isTrue);
      expect(await db.getVersion(), DbService.versionEsquema);
    });

    test('desde la v1 el día guardado sobrevive intacto', () async {
      final db = await migrarDesde(1, crearV1);
      addTearDown(db.close);

      final registro = Registro.fromMap(
        (await db.query('registros', where: 'fecha = ?',
                whereArgs: ['2026-01-15']))
            .single,
      );
      expect(registro.entrada1, '08:00');
      // El almuerzo de siempre se convierte en la primera pausa del día, y
      // se sigue leyendo como almuerzo porque cae en la franja del mediodía.
      expect(registro.pausas, [const Pausa(inicio: '12:00', fin: '13:00')]);
      expect(registro.salida1, '12:00');
      expect(registro.entrada2, '13:00');
      expect(registro.metaMinutos, 510);
      expect(registro.minutosCumplidos, 240);
      // La columna nueva no existía: queda nula, que es lo correcto.
      expect(registro.salidaReal, isNull);
      // Los días viejos siguen siendo días normales y conservan su meta.
      expect(registro.tipoDia, TipoDia.normal);
      expect(registro.metaEfectivaMinutos, 510);
      expect(registro.nota, isNull);
    });

    test('desde la v2 se conserva la salida real', () async {
      final db = await migrarDesde(2, crearV2);
      addTearDown(db.close);

      final registro = Registro.fromMap(
        (await db.query('registros')).single,
      );
      expect(registro.salidaReal, '17:30');
      expect(registro.tipoDia, TipoDia.normal);
      expect(await existeTabla(db, 'movimientos_banco'), isTrue);
    });

    test('desde la v3 no se pierden las ubicaciones ya guardadas', () async {
      final db = await migrarDesde(3, crearV3);
      addTearDown(db.close);

      final ubicaciones = await db.query('ubicaciones');
      expect(ubicaciones, hasLength(1));
      expect(ubicaciones.single['latitud'], closeTo(4.60971, 0.00001));
      expect((await db.query('registros')).single['salida_real'], '17:30');
      expect(await existeTabla(db, 'movimientos_banco'), isTrue);
    });

    test('tras migrar se puede escribir usando las columnas nuevas', () async {
      final db = await migrarDesde(1, crearV1);
      addTearDown(db.close);

      // Lo que de verdad importa: que la app pueda seguir operando. Un
      // Registro completo incluye tipo_dia y nota, que la v1 no tenía.
      await db.insert(
        'registros',
        const Registro(
          fecha: '2026-12-25',
          metaMinutos: 510,
          tipoDia: TipoDia.festivo,
          nota: 'Navidad',
        ).toMap()
          ..remove('id'),
      );
      await db.insert('movimientos_banco', {
        'fecha': '2026-12-26',
        'minutos': -240,
        'motivo': 'canje',
        'creado_en': '2026-12-26T09:00:00.000',
      });

      final festivo = Registro.fromMap(
        (await db.query('registros', where: 'fecha = ?',
                whereArgs: ['2026-12-25']))
            .single,
      );
      expect(festivo.tipoDia, TipoDia.festivo);
      expect(festivo.nota, 'Navidad');
      expect((await db.query('movimientos_banco')).single['minutos'], -240);
    });

    test('desde la v4 los días viejos se quedan sin descuento de almuerzo',
        () async {
      final db = await migrarDesde(4, crearV4);
      addTearDown(db.close);

      final registro = Registro.fromMap((await db.query('registros')).single);
      // Cero, no el ajuste que el usuario acabe de configurar: ese día se
      // trabajó bajo la regla anterior y sus horas ya no se tocan.
      expect(registro.descuentoAlmuerzoMinutos, 0);
      expect(ReportsService.minutosTrabajados(registro), 520);
    });

    test('desde la v5 el almuerzo se convierte en la primera pausa', () async {
      final db = await migrarDesde(5, crearV5);
      addTearDown(db.close);

      final dias = {
        for (final fila in await db.query('registros'))
          fila['fecha'] as String: Registro.fromMap(fila),
      };

      final completo = dias['2026-04-06']!;
      expect(completo.pausas, [const Pausa(inicio: '12:00', fin: '12:30')]);
      // Y las horas del día no se mueven al cambiar de representación.
      expect(ReportsService.minutosTrabajados(completo), 510);

      // Sin salida a almuerzo no había pausa que convertir, y una lista vacía
      // no es lo mismo que una pausa vacía.
      expect(dias['2026-04-07']!.pausas, isEmpty);
      expect(ReportsService.minutosTrabajados(dias['2026-04-07']!), 480);

      // La salida sin regreso se convierte en una pausa que quedó abierta.
      final aMedias = dias['2026-04-08']!;
      expect(aMedias.pausas, [const Pausa(inicio: '12:00')]);
      expect(aMedias.pausaAbierta, isNotNull);
    });

    test('una instalación nueva queda igual que una migrada', () async {
      final nueva = await abrirComoLaApp(rutaTemporal());
      addTearDown(nueva.close);

      final migrada = await migrarDesde(1, crearV1);
      addTearDown(migrada.close);

      // Si estas dos divergieran, un usuario que actualiza y otro que instala
      // de cero acabarían con esquemas distintos.
      expect(
        await columnasDe(migrada, 'registros'),
        await columnasDe(nueva, 'registros'),
      );
      for (final tabla in ['ubicaciones', 'movimientos_banco']) {
        expect(await columnasDe(migrada, tabla), await columnasDe(nueva, tabla));
      }
    });
  });
}

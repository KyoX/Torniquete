import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/movimiento_banco.dart';
import '../models/registro.dart';
import '../models/ubicacion_marca.dart';

/// Maneja la base de datos SQLite local que almacena el historial
/// de marcaciones diarias del torniquete.
class DbService {
  DbService._internal();
  static final DbService instance = DbService._internal();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  /// Versión actual del esquema. Subirla obliga a añadir su paso en
  /// [migrarEsquema].
  static const int versionEsquema = 4;

  static const String _nombreArchivo = 'torniquete.db';

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, _nombreArchivo),
      version: versionEsquema,
      onCreate: crearEsquema,
      onUpgrade: migrarEsquema,
    );
  }

  /// Esquema completo para una instalación nueva.
  ///
  /// Es público (igual que [migrarEsquema] y [versionEsquema]) para que las
  /// pruebas puedan abrir una base de datos en memoria con exactamente la
  /// misma definición que usa la app: una migración que solo se ejercita en
  /// producción es una migración sin probar.
  static Future<void> crearEsquema(Database db, int version) async {
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
    await _crearTablaUbicaciones(db);
    await _crearTablaMovimientos(db);
  }

  /// Lleva una base de datos de [oldVersion] hasta [newVersion].
  ///
  /// Los pasos son acumulativos y van en orden, así que una instalación vieja
  /// que se salte varias versiones los aplica todos de corrido (una v1 llega
  /// a la v4 encadenando los tres). sqflite envuelve esto en una transacción:
  /// si un paso falla, la base queda como estaba en lugar de a medio migrar.
  static Future<void> migrarEsquema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE registros ADD COLUMN salida_real TEXT');
    }
    if (oldVersion < 3) {
      await _crearTablaUbicaciones(db);
    }
    if (oldVersion < 4) {
      // Los días ya guardados son días normales: mantienen su meta. El DEFAULT
      // no es solo para las filas nuevas, también es lo que SQLite exige para
      // poder añadir una columna NOT NULL a una tabla que ya tiene datos.
      await db.execute(
        "ALTER TABLE registros ADD COLUMN tipo_dia TEXT NOT NULL "
        "DEFAULT 'normal'",
      );
      await db.execute('ALTER TABLE registros ADD COLUMN nota TEXT');
      await _crearTablaMovimientos(db);
    }
  }

  /// Evidencia opcional de dónde se registró cada marca. Solo se llena si
  /// el usuario activa "Guardar ubicación" en Ajustes.
  static Future<void> _crearTablaUbicaciones(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ubicaciones (
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
  }

  /// Movimientos manuales del banco de horas: lo que la app no puede deducir
  /// de las marcas (canjes de compensatorio, saldos traídos de antes).
  static Future<void> _crearTablaMovimientos(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS movimientos_banco (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fecha TEXT NOT NULL,
        minutos INTEGER NOT NULL,
        motivo TEXT NOT NULL,
        nota TEXT,
        creado_en TEXT NOT NULL
      )
    ''');
  }

  Future<Registro?> getRegistroPorFecha(String fecha) async {
    final db = await database;
    final rows = await db.query(
      'registros',
      where: 'fecha = ?',
      whereArgs: [fecha],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Registro.fromMap(rows.first);
  }

  Future<Registro> guardarRegistro(Registro registro) async {
    final db = await database;
    final existente = await getRegistroPorFecha(registro.fecha);
    if (existente == null) {
      final id = await db.insert('registros', registro.toMap()..remove('id'));
      return registro.copyWith(id: id);
    } else {
      await db.update(
        'registros',
        registro.toMap()..remove('id'),
        where: 'id = ?',
        whereArgs: [existente.id],
      );
      return registro.copyWith(id: existente.id);
    }
  }

  Future<List<Registro>> getHistorial({int limit = 60}) async {
    final db = await database;
    final rows = await db.query(
      'registros',
      orderBy: 'fecha DESC',
      limit: limit,
    );
    return rows.map(Registro.fromMap).toList();
  }

  /// Todos los registros guardados, sin límite práctico. Usado para reportes.
  Future<List<Registro>> getTodosLosRegistros() async {
    final db = await database;
    final rows = await db.query('registros', orderBy: 'fecha DESC');
    return rows.map(Registro.fromMap).toList();
  }

  /// Elimina por completo el registro de un día (todas sus marcas y las
  /// ubicaciones asociadas).
  Future<void> eliminarRegistro(String fecha) async {
    final db = await database;
    await db.delete('registros', where: 'fecha = ?', whereArgs: [fecha]);
    await db.delete('ubicaciones', where: 'fecha = ?', whereArgs: [fecha]);
  }

  /// Guarda (o reemplaza) la ubicación de una marca concreta.
  Future<void> guardarUbicacion(UbicacionMarca ubicacion) async {
    final db = await database;
    await db.insert(
      'ubicaciones',
      ubicacion.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Ubicaciones de un día, indexadas por tipo de marca.
  Future<Map<String, UbicacionMarca>> getUbicacionesPorFecha(
      String fecha) async {
    final db = await database;
    final rows = await db.query(
      'ubicaciones',
      where: 'fecha = ?',
      whereArgs: [fecha],
    );
    return {
      for (final row in rows)
        row['tipo'] as String: UbicacionMarca.fromMap(row),
    };
  }

  /// Todas las ubicaciones indexadas por "fecha|tipo". Evita una consulta por
  /// día al exportar el historial completo.
  Future<Map<String, UbicacionMarca>> getUbicacionesPorTipoYFecha() async {
    final todas = await getTodasLasUbicaciones();
    return {for (final u in todas) '${u.fecha}|${u.tipo}': u};
  }

  /// Todas las ubicaciones guardadas, de la más reciente a la más antigua.
  Future<List<UbicacionMarca>> getTodasLasUbicaciones() async {
    final db = await database;
    final rows =
        await db.query('ubicaciones', orderBy: 'fecha DESC, hora DESC');
    return rows.map(UbicacionMarca.fromMap).toList();
  }

  /// Borra toda la evidencia de ubicación guardada.
  Future<void> borrarTodasLasUbicaciones() async {
    final db = await database;
    await db.delete('ubicaciones');
  }

  Future<int> guardarMovimiento(MovimientoBanco movimiento) async {
    final db = await database;
    if (movimiento.id == null) {
      return db.insert('movimientos_banco', movimiento.toMap()..remove('id'));
    }
    await db.update(
      'movimientos_banco',
      movimiento.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [movimiento.id],
    );
    return movimiento.id!;
  }

  Future<List<MovimientoBanco>> getMovimientos() async {
    final db = await database;
    final rows = await db.query(
      'movimientos_banco',
      orderBy: 'fecha DESC, id DESC',
    );
    return rows.map(MovimientoBanco.fromMap).toList();
  }

  Future<void> eliminarMovimiento(int id) async {
    final db = await database;
    await db.delete('movimientos_banco', where: 'id = ?', whereArgs: [id]);
  }

  /// Vacía las tres tablas. Solo lo usa la restauración de un respaldo, que
  /// reemplaza el contenido completo en una transacción.
  Future<void> reemplazarTodo({
    required List<Registro> registros,
    required List<UbicacionMarca> ubicaciones,
    required List<MovimientoBanco> movimientos,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('registros');
      await txn.delete('ubicaciones');
      await txn.delete('movimientos_banco');
      for (final r in registros) {
        await txn.insert('registros', r.toMap()..remove('id'));
      }
      for (final u in ubicaciones) {
        await txn.insert(
          'ubicaciones',
          u.toMap()..remove('id'),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final m in movimientos) {
        await txn.insert('movimientos_banco', m.toMap()..remove('id'));
      }
    });
  }
}

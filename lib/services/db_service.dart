import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

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

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'torniquete.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
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
        await _crearTablaUbicaciones(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE registros ADD COLUMN salida_real TEXT');
        }
        if (oldVersion < 3) {
          await _crearTablaUbicaciones(db);
        }
      },
    );
  }

  /// Evidencia opcional de dónde se registró cada marca. Solo se llena si
  /// el usuario activa "Guardar ubicación" en Ajustes.
  Future<void> _crearTablaUbicaciones(Database db) async {
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
}

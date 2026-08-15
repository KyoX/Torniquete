import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/registro.dart';

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
      version: 2,
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE registros ADD COLUMN salida_real TEXT');
        }
      },
    );
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
}

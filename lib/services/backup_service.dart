import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/movimiento_banco.dart';
import '../models/registro.dart';
import '../models/ubicacion_marca.dart';
import 'db_service.dart';
import 'prefs_service.dart';
import 'reports_service.dart';

/// Qué pasó al intentar restaurar un respaldo.
enum ResultadoRestauracion {
  ok,

  /// El usuario cerró el selector sin elegir nada.
  cancelado,

  /// El archivo no es un respaldo de Torniquete (o está corrupto).
  archivoInvalido,

  /// El respaldo viene de una versión de la app más nueva que esta.
  versionNoSoportada,

  error,
}

/// Resumen de lo que se restauró, para poder decírselo al usuario.
class ResumenRestauracion {
  final ResultadoRestauracion resultado;
  final int dias;
  final int ubicaciones;
  final int movimientos;
  final String? detalle;

  const ResumenRestauracion(
    this.resultado, {
    this.dias = 0,
    this.ubicaciones = 0,
    this.movimientos = 0,
    this.detalle,
  });

  bool get exitosa => resultado == ResultadoRestauracion.ok;
}

/// Exporta el historial a CSV (para revisarlo en Excel o adjuntarlo a un
/// reclamo) y hace respaldos completos en JSON que la propia app puede
/// volver a cargar.
class BackupService {
  BackupService._internal();
  static final BackupService instance = BackupService._internal();

  /// Formato del respaldo. Si algún día cambia la estructura de forma
  /// incompatible se sube este número y se migra al leer.
  static const int versionRespaldo = 1;
  static const String _marcaArchivo = 'torniquete';

  /// Excel en español espera punto y coma como separador y coma decimal;
  /// con coma como separador manda todas las columnas a una sola celda.
  static const String _separadorCsv = ';';

  final DbService _db = DbService.instance;
  final PrefsService _prefs = PrefsService();

  // ---------------------------------------------------------------- CSV

  /// Genera el CSV del historial y abre el menú de compartir de Android.
  /// Devuelve la ruta del archivo creado.
  Future<String> exportarCsv() async {
    final registros = await _db.getTodosLosRegistros();
    final ubicaciones = await _db.getUbicacionesPorTipoYFecha();
    final contenido = construirCsv(registros, ubicaciones);
    final archivo = await _escribir(
      nombre: 'torniquete-historial-${_selloDeTiempo()}.csv',
      // El BOM le dice a Excel que el archivo es UTF-8; sin él se comen
      // las tildes y las eñes.
      contenido: '﻿$contenido',
    );
    await _compartir(
      archivo,
      texto: 'Historial de marcaciones exportado desde Torniquete.',
      asunto: 'Historial Torniquete',
    );
    return archivo.path;
  }

  /// Arma el CSV a partir de los datos ya cargados. Es una función pura para
  /// poder verificar el formato en las pruebas sin tocar disco.
  static String construirCsv(
    List<Registro> registros,
    Map<String, UbicacionMarca> ubicacionesPorClave,
  ) {
    final ordenados = [...registros]..sort((a, b) => a.fecha.compareTo(b.fecha));
    final filas = <String>[
      _fila([
        'fecha',
        'dia_semana',
        'tipo_dia',
        'entrada_manana',
        'salida_almuerzo',
        'entrada_tarde',
        'salida_real',
        'horas_trabajadas',
        'minutos_trabajados',
        'meta_minutos',
        'meta_exigida_minutos',
        'diferencia_minutos',
        'ubicacion_entrada',
        'nota',
      ]),
    ];

    for (final r in ordenados) {
      final minutos = ReportsService.minutosTrabajados(r);
      final ubicacion = ubicacionesPorClave['${r.fecha}|entrada1'];
      filas.add(_fila([
        r.fecha,
        _nombreDiaSemana(r.fecha),
        r.tipoDia.etiqueta,
        r.entrada1 ?? '',
        r.salida1 ?? '',
        r.entrada2 ?? '',
        r.salidaReal ?? '',
        _horasDecimales(minutos),
        '$minutos',
        '${r.metaMinutos}',
        '${ReportsService.metaEfectiva(r)}',
        '${ReportsService.diferenciaMinutos(r)}',
        ubicacion == null ? '' : ubicacion.coordenadas,
        r.nota ?? '',
      ]));
    }
    return filas.join('\r\n');
  }

  static String _fila(List<String> celdas) =>
      celdas.map(_escapar).join(_separadorCsv);

  /// Entrecomilla una celda si contiene el separador, comillas o saltos de
  /// línea, duplicando las comillas internas (RFC 4180).
  static String _escapar(String valor) {
    final necesita = valor.contains(_separadorCsv) ||
        valor.contains('"') ||
        valor.contains('\n') ||
        valor.contains('\r');
    if (!necesita) return valor;
    return '"${valor.replaceAll('"', '""')}"';
  }

  /// Horas con coma decimal, que es lo que espera Excel en español.
  static String _horasDecimales(int minutos) =>
      (minutos / 60).toStringAsFixed(2).replaceAll('.', ',');

  static String _nombreDiaSemana(String fecha) {
    try {
      return DateFormat('EEEE', 'es').format(DateTime.parse(fecha));
    } catch (_) {
      return '';
    }
  }

  // ------------------------------------------------------------- Respaldo

  /// Crea el respaldo completo en JSON y lo comparte. Incluye la
  /// configuración, los días, las ubicaciones y los movimientos del banco.
  Future<String> crearRespaldo() async {
    final json = await construirRespaldo();
    final archivo = await _escribir(
      nombre: 'torniquete-respaldo-${_selloDeTiempo()}.json',
      contenido: const JsonEncoder.withIndent('  ').convert(json),
    );
    await _compartir(
      archivo,
      texto: 'Respaldo completo de Torniquete. Guárdalo en un lugar seguro.',
      asunto: 'Respaldo Torniquete',
    );
    return archivo.path;
  }

  Future<Map<String, Object?>> construirRespaldo() async {
    final registros = await _db.getTodosLosRegistros();
    final ubicaciones = await _db.getTodasLasUbicaciones();
    final movimientos = await _db.getMovimientos();
    final sede = await _prefs.getSede();

    return {
      'app': _marcaArchivo,
      'version': versionRespaldo,
      'generado': DateTime.now().toIso8601String(),
      'config': {
        'nombre': await _prefs.getNombre(),
        'meta_lj_horas': await _prefs.getMetaLJ(),
        'meta_viernes_horas': await _prefs.getMetaViernes(),
        'guardar_ubicacion': await _prefs.getGuardarUbicacion(),
        'sede': {
          'activa': sede.activa,
          'latitud': sede.latitud,
          'longitud': sede.longitud,
          'radio_m': sede.radioMetros,
          'nombre': sede.nombre,
        },
      },
      'registros': registros.map((r) => r.toMap()..remove('id')).toList(),
      'ubicaciones': ubicaciones.map((u) => u.toMap()..remove('id')).toList(),
      'movimientos': movimientos.map((m) => m.toMap()..remove('id')).toList(),
    };
  }

  /// Pide un archivo de respaldo y reemplaza con él **todo** el contenido de
  /// la app. El reemplazo va en una transacción: si algo falla a mitad, la
  /// base de datos queda como estaba.
  Future<ResumenRestauracion> restaurarDesdeArchivo() async {
    final PlatformFile? archivo;
    try {
      archivo = await FilePicker.pickFile(
        dialogTitle: 'Selecciona el respaldo de Torniquete',
      );
    } catch (e) {
      return ResumenRestauracion(
        ResultadoRestauracion.error,
        detalle: 'No se pudo abrir el selector de archivos: $e',
      );
    }
    if (archivo == null) {
      return const ResumenRestauracion(ResultadoRestauracion.cancelado);
    }

    try {
      final bytes = await archivo.readAsBytes();
      return await restaurarDesdeJson(utf8.decode(bytes));
    } catch (e) {
      return ResumenRestauracion(
        ResultadoRestauracion.error,
        detalle: 'No se pudo leer el archivo: $e',
      );
    }
  }

  Future<ResumenRestauracion> restaurarDesdeJson(String texto) async {
    final Map<String, Object?> datos;
    try {
      final decodificado = jsonDecode(texto);
      if (decodificado is! Map<String, Object?>) {
        return const ResumenRestauracion(ResultadoRestauracion.archivoInvalido);
      }
      datos = decodificado;
    } catch (_) {
      return const ResumenRestauracion(ResultadoRestauracion.archivoInvalido);
    }

    if (datos['app'] != _marcaArchivo) {
      return const ResumenRestauracion(ResultadoRestauracion.archivoInvalido);
    }
    final version = (datos['version'] as num?)?.toInt() ?? 0;
    if (version > versionRespaldo) {
      return ResumenRestauracion(
        ResultadoRestauracion.versionNoSoportada,
        detalle: 'El respaldo es de la versión $version y esta app entiende '
            'hasta la $versionRespaldo.',
      );
    }

    try {
      final registros = _mapas(datos['registros'])
          .map(Registro.fromMap)
          .toList();
      final ubicaciones = _mapas(datos['ubicaciones'])
          .map(UbicacionMarca.fromMap)
          .toList();
      final movimientos = _mapas(datos['movimientos'])
          .map(MovimientoBanco.fromMap)
          .toList();

      await _db.reemplazarTodo(
        registros: registros,
        ubicaciones: ubicaciones,
        movimientos: movimientos,
      );
      await _restaurarConfig(datos['config']);

      return ResumenRestauracion(
        ResultadoRestauracion.ok,
        dias: registros.length,
        ubicaciones: ubicaciones.length,
        movimientos: movimientos.length,
      );
    } catch (e) {
      return ResumenRestauracion(
        ResultadoRestauracion.error,
        detalle: 'El respaldo tiene datos que no se pudieron leer: $e',
      );
    }
  }

  Future<void> _restaurarConfig(Object? config) async {
    if (config is! Map) return;
    final nombre = config['nombre'] as String?;
    if (nombre != null && nombre.trim().isNotEmpty) {
      await _prefs.guardarConfiguracion(
        nombre: nombre,
        metaLJ: (config['meta_lj_horas'] as num?)?.toDouble() ??
            PrefsService.defaultMetaLJ,
        metaViernes: (config['meta_viernes_horas'] as num?)?.toDouble() ??
            PrefsService.defaultMetaViernes,
      );
    }
    final guardarUbicacion = config['guardar_ubicacion'];
    if (guardarUbicacion is bool) {
      await _prefs.setGuardarUbicacion(guardarUbicacion);
    }
    final sede = config['sede'];
    if (sede is Map) {
      await _prefs.guardarSede(SedeConfig(
        activa: sede['activa'] == true,
        latitud: (sede['latitud'] as num?)?.toDouble(),
        longitud: (sede['longitud'] as num?)?.toDouble(),
        radioMetros: (sede['radio_m'] as num?)?.toInt() ??
            SedeConfig.defaultRadioMetros,
        nombre: sede['nombre'] as String?,
      ));
    }
  }

  static List<Map<String, Object?>> _mapas(Object? valor) {
    if (valor is! List) return const [];
    return valor.whereType<Map>().map((m) {
      return {for (final entrada in m.entries) '${entrada.key}': entrada.value};
    }).toList();
  }

  // ------------------------------------------------------------- Archivos

  Future<File> _escribir({
    required String nombre,
    required String contenido,
  }) async {
    // El directorio temporal basta: el archivo solo tiene que sobrevivir
    // hasta que la app receptora (Drive, correo, WhatsApp) lo copie.
    final dir = await getTemporaryDirectory();
    final archivo = File(p.join(dir.path, nombre));
    await archivo.writeAsString(contenido, encoding: utf8);
    return archivo;
  }

  Future<void> _compartir(
    File archivo, {
    required String texto,
    required String asunto,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(archivo.path)],
        text: texto,
        subject: asunto,
      ),
    );
  }

  static String _selloDeTiempo() =>
      DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
}

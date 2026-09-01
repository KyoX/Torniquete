import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/movimiento_banco.dart';
import '../models/pausa.dart';
import '../models/registro.dart';
import '../models/ubicacion_marca.dart';
import '../utils/time_utils.dart';
import 'db_service.dart';
import 'pausas_service.dart';
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
  ///
  /// La 2 añade el descuento fijo de almuerzo a cada día. Una app vieja no
  /// tiene esa columna, así que subirlo es lo que hace que rechace el archivo
  /// con un mensaje claro en vez de reventar a mitad de la restauración. Al
  /// revés no hay problema: los respaldos de la 1 se siguen leyendo y sus
  /// días entran sin descuento, que es como se trabajaron.
  static const int versionRespaldo = 2;
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
        'pausas',
        'minutos_pausados',
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
        // Las columnas de almuerzo son la pausa que cayó en la franja del
        // mediodía; aquí van todas, para que las horas trabajadas se puedan
        // reconstruir aunque el día tuviera tres.
        Pausa.serializarLista(r.pausas),
        '${PausasService.minutosPausados(r.pausas, hasta: _minutos(r.salidaReal))}',
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

  static int? _minutos(String? hora) {
    final t = TimeUtils.parseTimeOfDay(hora);
    return t == null ? null : TimeUtils.toMinutes(t);
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
    final sede2 = await _prefs.getSede2();
    final metas = await _prefs.getMetas();

    return {
      'app': _marcaArchivo,
      'version': versionRespaldo,
      'generado': DateTime.now().toIso8601String(),
      'config': {
        'nombre': await _prefs.getNombre(),
        'metas_semana_horas': metas.comoLista,
        // Las dos metas de antes siguen viajando en el respaldo para que una
        // versión anterior de la app pueda leer este archivo.
        'meta_lj_horas': metas.horasDe(DateTime.monday),
        'meta_viernes_horas': metas.horasDe(DateTime.friday),
        'guardar_ubicacion': await _prefs.getGuardarUbicacion(),
        'descuento_almuerzo_min': await _prefs.getDescuentoAlmuerzo(),
        'sede': {
          'activa': sede.activa,
          'latitud': sede.latitud,
          'longitud': sede.longitud,
          'radio_m': sede.radioMetros,
          'nombre': sede.nombre,
          'aviso_llegada': sede.avisarAlLlegar,
          'dias_oficina': sede.diasOficina.toList()..sort(),
        },
        'sede2': {
          'activa': sede2.activa,
          'latitud': sede2.latitud,
          'longitud': sede2.longitud,
          'radio_m': sede2.radioMetros,
          'nombre': sede2.nombre,
          'aviso_llegada': sede2.avisarAlLlegar,
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

  /// Las metas del respaldo. Un archivo escrito por una versión que solo
  /// sabía de dos —lunes a jueves y viernes— trae únicamente esas, y de ahí
  /// sale la semana clásica.
  static MetasSemana _metas(Map config) {
    final lista = config['metas_semana_horas'];
    if (lista is List) {
      final semana = MetasSemana.desdeLista(
        lista.map((v) => (v as num?)?.toDouble()).toList(),
      );
      if (semana != null) return semana;
    }
    return MetasSemana.clasica(
      lunesAJueves: (config['meta_lj_horas'] as num?)?.toDouble() ??
          PrefsService.defaultMetaLJ,
      viernes: (config['meta_viernes_horas'] as num?)?.toDouble() ??
          PrefsService.defaultMetaViernes,
    );
  }

  Future<void> _restaurarConfig(Object? config) async {
    if (config is! Map) return;
    final nombre = config['nombre'] as String?;
    if (nombre != null && nombre.trim().isNotEmpty) {
      await _prefs.guardarConfiguracion(nombre: nombre, metas: _metas(config));
    }
    final guardarUbicacion = config['guardar_ubicacion'];
    if (guardarUbicacion is bool) {
      await _prefs.setGuardarUbicacion(guardarUbicacion);
    }
    final descuento = config['descuento_almuerzo_min'];
    if (descuento is num) {
      await _prefs.setDescuentoAlmuerzo(descuento.toInt());
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
        avisarAlLlegar: sede['aviso_llegada'] == true,
        diasOficina: _diasOficina(sede['dias_oficina']),
      ));
    }
    // Un respaldo anterior a la segunda sede simplemente no trae la clave, y
    // entonces se deja como está: sin sede2 no hay nada que restaurar.
    final sede2 = config['sede2'];
    if (sede2 is Map) {
      await _prefs.guardarSede2(SedeSecundaria(
        activa: sede2['activa'] == true,
        latitud: (sede2['latitud'] as num?)?.toDouble(),
        longitud: (sede2['longitud'] as num?)?.toDouble(),
        radioMetros: (sede2['radio_m'] as num?)?.toInt() ??
            SedeConfig.defaultRadioMetros,
        nombre: sede2['nombre'] as String?,
        avisarAlLlegar: sede2['aviso_llegada'] == true,
      ));
    }
  }

  /// Los días de oficina del respaldo. Un respaldo anterior a este ajuste no
  /// los trae, y entonces vale la semana laboral típica: es lo que el usuario
  /// tenía de hecho cuando lo generó.
  static Set<int> _diasOficina(Object? valor) {
    if (valor is! List) return SedeConfig.diasLaboralesTipicos;
    return {
      for (final dia in valor)
        if (dia is num && dia >= 1 && dia <= 7) dia.toInt(),
    };
  }

  static List<Map<String, Object?>> _mapas(Object? valor) {
    if (valor is! List) return const [];
    return valor.whereType<Map>().map((m) {
      return {for (final entrada in m.entries) '${entrada.key}': entrada.value};
    }).toList();
  }

  // ------------------------------------------------------- Respaldo automático

  /// Cuántos respaldos automáticos se conservan. Uno por semana, así que
  /// bastan para cubrir mes y medio sin llenar el teléfono de archivos.
  static const int maxRespaldosAutomaticos = 6;

  static const String _prefijoRespaldoAutomatico = 'auto-';

  /// Igual que [crearRespaldo], pero sin pasar por el selector de compartir:
  /// escribe el JSON en un directorio propio y persistente (no el temporal
  /// que usa el resto de exportaciones, que el sistema puede limpiar en
  /// cualquier momento) y borra los más viejos si ya hay
  /// [maxRespaldosAutomaticos]. Pensado para que lo dispare una tarea
  /// periódica en segundo plano, sin nadie mirando la pantalla.
  Future<File> crearRespaldoAutomatico() async {
    final json = await construirRespaldo();
    final dir = await _directorioRespaldosAutomaticos();
    final archivo = File(p.join(
      dir.path,
      '$_prefijoRespaldoAutomatico${_selloDeTiempo()}.json',
    ));
    await archivo.writeAsString(
      const JsonEncoder.withIndent('  ').convert(json),
      encoding: utf8,
    );
    await _rotar(dir);
    return archivo;
  }

  /// Los respaldos automáticos guardados, del más reciente al más viejo.
  Future<List<File>> respaldosAutomaticos() async {
    final dir = await _directorioRespaldosAutomaticos();
    return _ordenados(dir);
  }

  Future<Directory> _directorioRespaldosAutomaticos() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'respaldos_automaticos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Borra los respaldos automáticos que sobren por encima de
  /// [maxRespaldosAutomaticos], empezando por los más viejos.
  Future<void> _rotar(Directory dir) async {
    final archivos = await _ordenados(dir);
    for (final archivo in archivos.skip(maxRespaldosAutomaticos)) {
      await archivo.delete();
    }
  }

  /// Los archivos de respaldo automático del directorio, del más reciente al
  /// más viejo. El sello de tiempo del nombre ordena igual que la fecha real
  /// porque va de año a minuto, de mayor a menor unidad.
  Future<List<File>> _ordenados(Directory dir) async {
    final archivos = await dir
        .list()
        .where((e) =>
            e is File && p.basename(e.path).startsWith(_prefijoRespaldoAutomatico))
        .cast<File>()
        .toList();
    archivos.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return archivos;
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
